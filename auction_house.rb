require 'rubygems'
require 'mechanize'
require 'logger'
require 'cgi'
require 'active_support'
require 'mongo'
require 'yaml'

module WowArmory
	module AuctionHouse
		class Scanner
			attr_reader :requires_authenticator
			attr_reader :config
			attr_reader :db
			
			def initialize(yaml)
				@config = YAML::load(File.open(yaml).read)
				@agent = Mechanize.new {|agent| agent.user_agent = "Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US; rv:1.9.2.4) Gecko/20100513 Firefox/3.6.4" }
				@agent.pre_connect_hooks << lambda { |params| params[:request]['Connection'] = 'keep-alive' }

				@db = Mongo::Connection.new.db(@config["database"])
				@db["auctions"].create_index("auc", :unique => true)
				@db["auctions"].create_index([["n", Mongo::ASCENDING]])
			end
			
			def login!
				@agent.get(@config["root"]) do |page|
					login_result = page.form_with(:name => "loginForm") do |login|
						login.accountName = @config["user"]
						login.password = @config["pass"]
					end.submit
					
					if login_result.forms.first.action.match("authenticator.html") then
						@needs_auth = true
						return false
					else
						return true
					end
				end
			end
			
			def authenticate!(code)
				result = @agent.current_page.form_with(:action => /authenticator/) do |auth|
					auth.authValue = code
				end.submit
			end
			
			def needs_authenticator?
				!!@needs_auth
			end		
			
			def search(query)
				pieces = {}
				pieces["n"] = CGI::escape(query["query"]) unless query["query"].blank?
				pieces["qual"] = query["qual"] || 0
				pieces["minLvl"] = query["minLvl"] unless query["minLvl"].blank?
				pieces["filterId"] = query["filterId"] unless query["filterId"].blank?
				
				start = 0
				answers = []
				totalCt = nil
				while true do
					pieces["start"] = start
					break if totalCt and start >= totalCt
					url = sprintf(@config["query"], pieces.map {|k, v| "#{k}=#{v}"}.join("&"))
					# puts url
					result = @agent.get(url)
					startTime = Time.now.to_f

					page = JSON::load(result.body)
					if page["auctionSearch"].nil? then
						puts "Hit throttle! Skipping request..."
						next
					end
					totalCt ||= page["auctionSearch"]["total"]
					start += 50
					
					break if page["auctionSearch"]["auctions"].empty?
					answers += page["auctionSearch"]["auctions"]
					endTime = Time.now.to_f
					sleepTime = 0.55
					sleep(sleepTime)
				end
				return answers
			end
			
			def get_price_data(group_by, query)
				reduce = Mongo::Code.new <<-EOF
					function(obj, prev) {
						var price = obj.ppuBuy
						if(!price) price = obj.buy
						if(price) {
							prev.values[prev.values.length] = parseInt(price)
							prev.sum += parseInt(price)
							prev.name = obj.n
						}
					}
				EOF
				finalize = Mongo::Code.new <<-EOF
					function(out) {
						var values = out.values
						out.len = values.length
						out.mean = out.sum / values.length
						if(values.length  > 0) {
							var mid = Math.ceil(values.length / 2);
							if(values.length % 2 == 0) {
								out.median = (values[mid] + values[mid+1]) / 2
							} else {	
								out.median = values[mid]
							}
						}
						if(values.length > 1) {
							var sum = 0
							for(var i in out.values) {
								var val = out.values[i]
								sum += (val - out.mean) * (val - out.mean)
							}							
							out.stdDev = Math.pow(sum / (values.length - 1), 0.5)
						}
					}
				EOF
				@db["auctions"].group(group_by, query, {:values => [], :sum => 0}, reduce, finalize)
			end
			
			def get_sales(after, before, query = nil)
				q = (query || {}).merge(:date => {:$gte => after, :$lte => before}, :time => {:$gt => 1})
				@db["auctions"].find(q)
			end
		end
	end
end
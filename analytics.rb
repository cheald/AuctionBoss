require 'auction_house'
require 'utilities'
include WowArmory::AuctionHouse::Utilities

module WowArmory
	module AuctionHouse
		class Analytics
			def initialize(yml)
				@ah = WowArmory::AuctionHouse::Scanner.new(yml)
				db = Mongo::Connection.new.db(@ah.config["database"])
			end
			
			def get_stats(item = nil)
				query = {:date => {:$gt => 1.week.ago}}
				query[:name] = item unless item.nil?
				data = @ah.get_price_data([:n], query)
				data.each do |set|
					puts set["name"]
					puts "Samples: #{set["values"].length}"
					puts "Mean: " + raw_to_wow(set["mean"])
					puts "Median: " + raw_to_wow(set["median"])
					puts "Standard Deviation: " + raw_to_wow(set["stdDev"])
					puts ""
				end
			end

			def get_sales(after = 1.day.ago, before = 1.hour.ago, query = nil)
				volumes = {}
				list_datas = {}
				@ah.get_sales(after, before, query).each do |sale|
					price = (sale["ppuBuy"] || sale["buy"]).to_f
					next if price == 0
					puts "%s sold @ %s" % [sale["n"], raw_to_wow(price)]
					volumes[sale["n"]] ||= {:volume => 0, :min => nil, :max => nil, :sum => 0, :units => 0, :total => 0}
					t = volumes[sale["n"]]
					t[:volume] += 1
					t[:sum] += price
					t[:total] += sale["buy"].to_f
					t[:units] += (sale["quan"] || 0).to_i
					t[:min] = price if t[:min].nil? or price < t[:min]
					t[:max] = price if t[:max].nil? or price > t[:max]		
					list_datas[sale["n"]] ||= @ah.get_price_data([:n], query = {:n => sale["n"], :date => {:$gt => 6.hours.ago}}).first		
					t[:avglist] = list_datas[sale["n"]]["median"]
				end
				return volumes
			end
		end
	end
end

analytics = WowArmory::AuctionHouse::Analytics.new "auctionboss.yml"

nice = "%s: Moved %d lots (%d units), avg moving @ %s (%s min / %s max) [list @ %s, total %sg]"
csv = "%s,%d,%d,%s,%s,%s,%s,%s"
query = nil
item = ARGV.join(" ").chomp
query = {:n => item} unless item.blank?
analytics.get_sales(1.day.ago, 10.minutes.ago, query).each do |key, val|
	puts sprintf(nice, key, 
		val[:volume],
		val[:units],
		raw_to_wow(val[:sum] / val[:volume]),
		raw_to_wow(val[:min]),
		raw_to_wow(val[:max]),
		raw_to_wow(val[:avglist]),
		(val[:total] / 10000).floor
	)
end
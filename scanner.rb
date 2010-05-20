require 'auction_house'
require 'utilities'
include WowArmory::AuctionHouse::Utilities

def setup
	ah = WowArmory::AuctionHouse::Scanner.new("auctionboss.yml")
	if ah.login! then
		puts colorize("Logged in!", "1;32;40")
	elsif ah.needs_authenticator? then
		print colorize("Please enter the authenticator code for this account: ", "1;36;40")
		if ah.authenticate!(gets.chomp) then
			puts colorize("Logged in!", "1;32;40")
		end
	else	
		puts colorize("Invalid credentials or Armory not available", "1;31;40")
	end
	ah
end

ah = setup
while true do
	ah.db["queries"].find().each do |row|
		auctions = ah.search(row)
		puts "Found #{colorize auctions.length, "1;33;40"} auctions\t- #{colorize(row["query"] || row.inspect, "1;37;40")}"

		auctions.each do |auction|
			auction["date"] = Time.new
			ah.db["auctions"].update({"auc" => auction["auc"]}, auction, {:upsert => true})
		end
		ah.db["auctions"].update({:first_seen => {:$exists => false}}, {:$set => {:first_seen => Time.new}})
	end
	puts colorize(":: Scan finished\t- sleeping for 1 minutes ::", "1;32;40")
	sleep(60)
end
module WowArmory
	module AuctionHouse
		module Utilities
			def raw_to_wow(raw)
				return "nil" if !raw or raw.nan?
				m = raw.to_i
				gold = sprintf("%dg", m / 10000)
				silver = sprintf("%ds", (m / 100) % 100)
				copper = sprintf("%dc", m % 100)
				sprintf("%s %s %s", colorize(gold, "7;30;43"), colorize(silver, "7;30;47"), colorize(copper, "7;30;41"))
			end
			
			def colorize(text, color_code)
				"\033[#{color_code}m#{text}\033[0m"
			end
		end
	end
end

--League-Server by GRAND(Gerlamp) and Mohamed Amr Nady
--Research: SMc81, .andre92
--Special thank's: crabshank

local m = {}

-- Constants
local contentPath = ".\\content\\League-Server\\"
local startAddress = 0x00007FF4D0000000
local endAddress = 0x00007FF4EFFFFFF0
local hexPat = "0x%x+"
local BlankDate = "\xff\xff\xff\xff\x37\x00\x00\x00\x03\x00\x00\x00\xff\xff\xff\xff"
local _empty = {}
-- Variables
local compsMap
local mlteamnow = {}
local CalendarAddresses = {}
local Schedule = {}
local gamesSchedule = {}
local matchdays = {}
local teamNamestoHex = {}
local customMatchdaysData = {}
local fixtureNumberInterval = 0
-- Config
local isDebugging = false
-- local changeDate = false

function m.dispose()
	mlteamnow = {}
	CalendarAddresses = {}
	Schedule = {}
	gamesSchedule = {}
	matchdays = {}
	teamNamestoHex = {}
	customMatchdaysData = {}
	collectgarbage()
end

local function get_rlm_lib(ctx)
	return ctx.real_life_mode or _empty
end

local function date_to_totaldays(date)
	local days_in_each_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	local i, j = date:match("(%d+)/(%d+)")
	local month, day = tonumber(i), tonumber(j)
	if month > 0 and month <= 12 and day > 0 and day <= 31 then
		if day > days_in_each_month[month] then
			log("Incorrect Date: day should be smaller")
			return nil
		end
		local totaldays = day
		for i = 1, month - 1 do
			totaldays = totaldays + days_in_each_month[i]
		end
		return totaldays
	else
		log("Incorrect Date: be realistic plz")
		return nil
	end
end

local function teamHextoID(teamHex)
	function getBits(num)
		local x = {}
		while num > 0 do
			rest = num % 2
			table.insert(x, 1, rest)
			num = (num - rest) / 2
		end
		return table.concat(x) or x
	end

	function binToNum(binary)
		local bin, sum = tostring(binary):reverse(), 0
		for i = 1, #bin do
			num = bin:sub(i, i) == "1" and 1 or 0
			sum = sum + num * 2 ^ (i - 1)
		end
		return sum
	end

	return binToNum(getBits(memory.unpack("u32", teamHex)):sub(1, -15))
end

local function gamedayToTeamIDs(matchday)
	local t = {}
	for n = 1, 10 do
		local gameAddress = matchday[n]
		local homeHex = memory.read(gameAddress + 20, 4)
		local awayHex = memory.read(gameAddress + 24, 4)
		t[teamHextoID(homeHex)] = homeHex
		t[teamHextoID(awayHex)] = awayHex
	end
	return t
end

local function tableToTeamIDs(table)
	local t = {}
	for n = 1, #table do
		t[table[n].dec] = table[n].hex
		log(string.format("plz %d %s", table[n].dec, memory.hex(table[n].hex)))
	end
	return t
end

local function mapTeamIDs(teamIDs, namesMap)
	local t = {}
	-- loop 1: match available ids and leave unavailable untouched
	for name, id in pairs(namesMap) do
		if teamIDs[id] then -- available
			log(string.format("found %s id: %d", name, id))
			t[name] = teamIDs[id]
			teamIDs[id] = nil
			namesMap[name] = nil
		end
	end
	-- loop 2: match unavailable ids
	for name, id in pairs(namesMap) do
		if id then -- unavailable
			for newId, hex in pairs(teamIDs) do
				if hex then
					log(string.format("matched %s old: %d new: %d", name, id, newId))
					t[name] = hex
					teamIDs[newId] = nil
					break
				end
			end
		end
	end
	return t
end

local function getAddressWithVariableBytes(addrBeginning, variableByteLength, addrEndning, variableStartAddress)
	local addr = memory.safe_search(addrEndning, variableStartAddress, endAddress)
	if addr then
		if memory.read(addr - #addrBeginning - variableByteLength, #addrBeginning) == addrBeginning then
			return addr - variableByteLength - #addrBeginning
		else
			return getAddressWithVariableBytes(addrBeginning, variableByteLength, addrEndning, addr + #addrEndning)
		end
	else
		return nil
	end
end

local function getGamesOfLeagueUsingMemory(currentleagueid, matchdaytotal)
	local variableBytesLength = 20
	local addrEndning = "\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xFF"
	local returnValueOffset = -2

	local t = {}
	for i = 1, matchdaytotal do
		local all_found = false
		local variableStartAddress = startAddress
		local addrBeginning = "\x00\x00" .. currentleagueid .. memory.pack("u8", i - 1) .. "\x20"
		log(string.format("searching matchday %d", i))
		t[i] = {}
		while all_found == false and variableStartAddress <= endAddress do
			local addr = memory.safe_search(addrBeginning, variableStartAddress, endAddress)
			if addr then
				if memory.read(addr + #addrBeginning + variableBytesLength, #addrEndning) == addrEndning then
					log("address matches criteria, inserting...")
					table.insert(t[i], addr + returnValueOffset)
				else
					log("address doesn't matches criteria, skipping...")
				end
				variableStartAddress = tonumber(string.match(tostring(addr), hexPat)) + 1
			else
				all_found = true
				log(string.format("found %d address in matchday %d", #t[i], i))
			end
		end
	end
	return t
end

local function getGamesOfCompUsingLoop(currentleagueid, type_byte, yearnow, total_matchdays, total_games_per_matchday)
	local t = {}
	local addr
	for matchday = 1, total_matchdays do
		t[matchday] = {}
		for game = 1, total_games_per_matchday do
			if matchday == 1 and game == 1 then
				addr = memory.safe_search(
					"\x00\x00" .. memory.pack("u16", currentleagueid) .. type_byte .. "\x20" .. yearnow,
					startAddress,
					endAddress
				)
				if isDebugging then
					log(memory.hex("\x00\x00" .. memory.pack("u16", currentleagueid) .. type_byte .. "\x20" .. yearnow))
				end
				if addr ~= nil then
					if isDebugging then
						log(memory.hex(addr))
					end
					fixtureNumberInterval = memory.unpack("u16", memory.read(addr - 2, 2))
					table.insert(t[1], addr - 2)
				else
					log(string.format("matchdays: matchday 1 game 1 wasn't found for %s, skipping...", currentleagueid))
					return {}
				end
			else
				addr = t[1][1] + 596 * (game - 1) + 596 * (matchday - 1) * total_games_per_matchday
				table.insert(t[matchday], addr)
			end
			if isDebugging then
				log(
					string.format(
						"matchdays: MatchDay %d Game %d : %s",
						matchday,
						game,
						memory.hex(memory.read(addr, 28))
					)
				)
			end
		end
	end
	return t
end

local function getSchedule(currentCompId, compType, total_matchdays, total_games_per_matchday)
	local t = {}
	local addr
	local compIdHex = memory.pack("u16", currentCompId)
	for matchday = 1, total_matchdays do
		t[matchday] = {}
		for game = 1, total_games_per_matchday do
			if matchday == 1 and game == 1 then
				if compType == "cup" then
					addr = getAddressWithVariableBytes(
						compIdHex .. "\x00\x00",
						10,
						"\xff\xff" .. compIdHex .. "\x6E\x00" .. compIdHex .. "\x2f\x00\xff\xff",
						startAddress
					)
				else
					addr = getAddressWithVariableBytes(
						compIdHex .. "\x00\x00",
						10,
						"\xff\xff" .. compIdHex .. "\x00\x00\xff\xff\xf7\x07",
						startAddress
					)
				end
				if addr then
					table.insert(t[1], addr - 6)
				else
					log(
						string.format(
							"gamesSchedule: matchday 1 game 1 wasn't found for %s, skipping...",
							currentCompId
						)
					)
					return {}
				end
			else
				addr = t[1][1] + 32 * (game - 1) + 520 * (matchday - 1)
				table.insert(t[matchday], addr)
			end
			if isDebugging then
				log(
					string.format(
						"gamesSchedule: MatchDay %d Game %d : %s",
						matchday,
						game,
						memory.hex(memory.read(addr, 28))
					)
				)
			end
		end
	end
	return t
end

-- local function getAllAddressesWithVariableBytes(addrBeginning, variableByteLength, addrEndning, variableStartAddress,
--                                                 returnValueOffset)
--     local t = {}
--     local all_found = false
--     while all_found == false and variableStartAddress <= endAddress do
--         local addr = memory.safe_search(addrBeginning, variableStartAddress, endAddress)
--         if addr == nil then
--             all_found = true
--             log(string.format("found %d address", #t))
--         else
--             local ad = tonumber(string.match(tostring(addr), hexPat))
--             if type(ad) == 'number' then
--                 log("found address")
--                 if memory.read(addr + #addrBeginning + variableByteLength, #addrEndning) == addrEndning then
--                     log("address matches criteria, inserting...")
--                     log(memory.hex(memory.read(ad + returnValueOffset, #addrBeginning)))
--                     table.insert(t, ad + returnValueOffset)
--                     -- else
--                     --     log(memory.hex(addr))
--                 end
--                 variableStartAddress = ad + #addrBeginning
--             end
--         end
--     end
--     return t
-- end

local function tableIsEmpty(self)
	for _, _ in pairs(self) do
		return false
	end
	return true
end

local function writeGame(
	config,
	startingYear,
	fixtureNumber,
	gameweekNumber,
	from_total_days,
	to_total_days,
	to_month,
	to_day,
	isNight,
	matchStartTime,
	homeTeam,
	awayTeam,
	isGeneric,
	isCurrentTeamInLeague
)
	local fixNoHex = memory.pack(
		"u16",
		fixtureNumber - 1 + (config["TOTAL_TEAMS"] / 2) * (gameweekNumber - 1) + fixtureNumberInterval
	)

	-- Matchday Writing

	-- E6 00 (Fixture id)
	-- 00 00 11 00 (Liga id)
	-- 17 (Matchday)
	-- 20 (League type)
	-- E5 07 01 1A (Date 2021/01/26)
	-- 00 00 00 00 (Night Boolean)
	-- 10 00 00 00 (Match time)
	-- 10 C0 2C 00 (Home team)
	-- 04 80 19 00 (Away team)

	local gameAddress = matchdays[gameweekNumber][fixtureNumber]
	local matchdaySchedule = gamesSchedule[gameweekNumber][fixtureNumber]
	if isDebugging then
		log(
			string.format(
				"matchdays: Game %d of MatchDay %d Before: %s",
				fixtureNumber,
				gameweekNumber,
				memory.hex(memory.read(gameAddress, 28))
			)
		)
		log(
			string.format(
				"gamesSchedule: Game %d of MatchDay %d Before: %s",
				fixtureNumber,
				gameweekNumber,
				memory.hex(memory.read(matchdaySchedule, 18))
			)
		)
	end
	if isNight then
		memory.write(gameAddress + 12, memory.pack("u16", isNight))
	end
	if matchStartTime then
		memory.write(gameAddress + 16, memory.pack("u16", matchStartTime))
	end
	if homeTeam then
		memory.write(gameAddress + 20, teamNamestoHex[homeTeam])
		memory.write(matchdaySchedule + 10, teamNamestoHex[homeTeam])
	end
	if awayTeam then
		memory.write(gameAddress + 24, teamNamestoHex[awayTeam])
		memory.write(matchdaySchedule + 14, teamNamestoHex[awayTeam])
	end

	if to_total_days and to_month and to_day then
		local sum = memory.unpack("u8", memory.read(Schedule[to_total_days], 1)) + 1
		memory.write(
			gameAddress + 8,
			memory.pack("u16", startingYear) .. memory.pack("u8", to_month) .. memory.pack("u8", to_day)
		)
		-- Schedule Writing
		memory.write(Schedule[to_total_days], memory.pack("u8", sum))
		-- Write new fixture after previous ones (if there any)
		memory.write(Schedule[to_total_days] - (sum * -2 + 562), fixNoHex)
		-- Remove "from_date" games
		-- TODO: Decode that section for proper writing
		if not isGeneric then
			memory.write(Schedule[from_total_days] - 560, string.rep("\xff", 560))
		end
		-- Stop or Skip
		if isCurrentTeamInLeague then
			if mlteamnow.hex == teamNamestoHex[homeTeam] or mlteamnow.hex == teamNamestoHex[awayTeam] then
				log("currunt match has current team")
				-- Stop
				memory.write(Schedule[to_total_days] + 7, "\x00")
				-- Calendar Writing
				-- TODO: Define that for UCL,... (01), domestic league/cup (02), or nothing (03)
				local game_type_hex = "\x02\x00"

				memory.write(CalendarAddresses[to_total_days], fixNoHex) -- C8 00 Matchday ID
				memory.write(CalendarAddresses[to_total_days] + 2, config["ID"].hex) -- 11 00 League ID
				memory.write(CalendarAddresses[to_total_days] + 4, memory.pack("u16", gameweekNumber - 1)) -- 14 00 Matchday № this 21 day
				memory.write(CalendarAddresses[to_total_days] + 6, "\x00\x00") -- 00 00 Blank
				memory.write(CalendarAddresses[to_total_days] + 8, game_type_hex) -- 02 00 Playable day (01 UCL) (03 not Playableday)
				memory.write(CalendarAddresses[to_total_days] + 10, "\x00\x00") -- 00 00 Blank
				memory.write(CalendarAddresses[to_total_days] + 12, mlteamnow.hex)
				if not isGeneric then
					memory.write(CalendarAddresses[from_total_days], BlankDate) -- (from,Blank)
				end -- Team ID
			else
				-- Skip
				-- That might be causing an error that's we didn't experience yet
				-- Some sort of double writing
				memory.write(Schedule[to_total_days] + 7, "\xff")
				-- Calendar Writing
			end
		end
	end
	if isDebugging then
		log(
			string.format(
				"matchdays: Game %d of MatchDay %d After: %s",
				fixtureNumber,
				gameweekNumber,
				memory.hex(memory.read(gameAddress, 28))
			)
		)
		log(
			string.format(
				"gamesSchedule: Game %d of MatchDay %d After: %s",
				fixtureNumber,
				gameweekNumber,
				memory.hex(memory.read(matchdaySchedule, 18))
			)
		)
	end
end

function m.data_ready(ctx, filename)
	--Main
	local newml = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_meeting_reply_0%d%_pl.fdc")
	local newbl = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_firstday_BL01_1_pl.fdc")
	local midseason =
		string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_meeting_report_01_stand_cam_B.fdc")
	--local newml = string.match(filename, "common\\demo\\fixdemo\\mode\\cut_data\\mode_meeting_mission_07a_manager.fdc")
	local loadml = string.match(filename, "common\\script\\flow\\ML\\MLCoachCapturePostLoad.json") --common\\script\\flow\\ML\\MLMainManu.json
	local updateday = string.match(filename, "common\\script\\flow\\ML\\MLMainManu.json") -- common\\script\\flow\\Common\\CmnScheduleProcess.json
	local rlmLib = get_rlm_lib(ctx)
	local year

	if updateday then
		year = rlmLib.hook_year()
		currentMonth = memory.unpack("u8", memory.read(year + 7, 1))
		currentDay = memory.unpack("u8", memory.read(year + 8, 1))
		midjan = (currentMonth == 7 and currentDay == 1)
		midjune = (currentMonth == 1 and currentDay == 1)
		log(string.format("currentMonth: %d", currentMonth))
		log(string.format("currentDay: %d", currentDay))
	end

	if newml or newbl then --or (midjune and updateday) or (midjan and updateday)
		year = rlmLib.hook_year()
		log("**Writing Started**")
		local pandas = ctx.external_files
		local position = memory.read(year - 3, 1)
		local yearnow = rlmLib.current_season()
		-- startingYear = yearnow.dec
		-- endingYear = yearnow.dec + 1
		local datenow = memory.read(year + 5, 4)
		local currentMonth = memory.unpack("u8", memory.read(year + 7, 1))
		-- local currentleagueid = memory.read(year + 51, 1)

		mlteamnow = rlmLib.current_team_id()
		local currentleagueid = {}
		currentleagueid.dec =
			ctx.common_lib.compID_to_tournamentID_map[ctx.common_lib.leagues_of_teams[mlteamnow.dec][1]]
		currentleagueid.hex = memory.pack("u16", currentleagueid.dec)
		log(string.format("ML Team: %d", mlteamnow.dec))
		log(string.format("League ID: %d", currentleagueid.dec))
		log(string.format("Season: %d", yearnow.dec))

		if not tableIsEmpty(compsMap) then
			local leagues_configs = {}
			for i, compName in pairs(compsMap) do -- Load all league configs to return current league config easily
				leagues_configs[i] = pandas.read_ini(contentPath .. string.format("\\%s\\", compName) .. "config.ini")
				if leagues_configs[i] ~= nil then
					leagues_configs[i]["NAME"] = compName
					leagues_configs[i]["ID"] = {}
					leagues_configs[i]["ID"].dec = i
					leagues_configs[i]["ID"].hex = memory.pack("u16", i)
				else
					table.remove(leagues_configs)
				end
			end
			-- local compName = compsMap[currentleagueid.dec]
			for i, config in pairs(leagues_configs) do
				local configPath = contentPath .. string.format("\\%s\\", config["NAME"])
				local existingYears = pandas.read_text(configPath .. "\\years.txt")
				if tableIsEmpty(CalendarAddresses) then
					for counter = 1, 365 do
						if isDebugging then
							log(
								string.format(
									"Calendar: Day %d : %s",
									counter,
									memory.hex(memory.read(year + counter * 16 + 1, 16))
								)
							)
						end
						table.insert(CalendarAddresses, counter, year + counter * 16 + 1)
					end
				end
				-- Schedule -- Found in ML Main Menu Bottom Left and Center -- Needs optimization
				if tableIsEmpty(Schedule) then
					local addr
					if leagues_configs[currentleagueid.dec]["STARTS_IN_JAN"] == "true" then
						addr = getAddressWithVariableBytes(
							"\x00\x00\x03\x00\x00\x00",
							2,
							"\x01\x01\x01\x00\x01",
							startAddress
						)
					elseif leagues_configs[currentleagueid.dec]["STARTS_IN_JAN"] == "false" then
						addr = getAddressWithVariableBytes(
							"\x00\x00\x06\x00\x00\x00",
							2,
							"\x01\x01\x09\x00\xF5",
							startAddress
						)
					else
						error("STARTS_IN_JAN field in config.ini is mandatory")
					end
					if addr then
						table.insert(Schedule, 1, addr - 2)
						for day = 1, 364 do -- day 0 is already there
							table.insert(Schedule, day + 1, Schedule[1] + 708 * day)
							if isDebugging then
								log(
									string.format(
										"Schedule: Day %d : %s",
										day + 1,
										memory.hex(memory.read(Schedule[1] + 708 * day, 15))
									)
								)
							end
						end
					else
						error("schecule was not found, aborting...")
					end
				end
				if
					(currentMonth == 1 and config["STARTS_IN_JAN"] == "true")
					or ((currentMonth == 6 or currentMonth == 8) and config["STARTS_IN_JAN"] == "false")
				then
					local total_matchdays = config["TOTAL_TEAMS"] * 2 - 2
					local total_games_per_matchday = config["TOTAL_TEAMS"] / 2
					local typeByte
					if config["TYPE"] == "cup" then
						typeByte = "\x2e"
					elseif config["TYPE"] == "supercup" then
						typeByte = "\x35"
					else
						typeByte = "\x00"
					end
					if config["TOTAL_MATCHDAYS"] ~= nil then
						total_matchdays = config["TOTAL_MATCHDAYS"]
					end
					if config["TOTAL_GAMES_PER_MATCHDAY"] ~= nil then
						total_games_per_matchday = config["TOTAL_GAMES_PER_MATCHDAY"]
					end
					local hasCustom = existingYears[tostring(yearnow.dec)] or config["DEFAULT_MAP"]
					local isGeneric = config["IS_GENERIC"] == "true"
					gamesSchedule = getSchedule(i, config["TYPE"], total_matchdays, total_games_per_matchday) -- Found in ML Main Menu> Team Info> Schedule> MatchDay ##
					if isGeneric then
						matchdays =
							getGamesOfCompUsingLoop(i, typeByte, "\xff\xff", total_matchdays, total_games_per_matchday)
					else
						matchdays =
							getGamesOfCompUsingLoop(i, typeByte, yearnow.hex, total_matchdays, total_games_per_matchday) -- Found in ML Main Menu> Team Info> Schedule
					end
					if not tableIsEmpty(matchdays) or not tableIsEmpty(gamesSchedule) then
						if hasCustom then -- custom edit based on year
							local mapsPath = configPath .. hasCustom
							customMatchdaysData = pandas.read_csv(mapsPath .. "\\map_matchdays.csv")

							teamNamestoHex = mapTeamIDs(
								gamedayToTeamIDs(matchdays[1]),
								-- tableToTeamIDs(rlmLib.comp_table(config["ID"], config["TOTAL_TEAMS"], "current")),
								pandas.read_num_text_map(mapsPath .. "\\map_team.csv")
							)
							for n = 1, #customMatchdaysData do
								local from_total_days
								if not isGeneric then
									from_total_days = date_to_totaldays(customMatchdaysData[n]["FromDate"])
								end
								local to_month, to_day
								local to_total_days
								if customMatchdaysData[n]["ToDate"] then
									local mon, day = customMatchdaysData[n]["ToDate"]:match("(%d+)/(%d+)")
									to_month, to_day = tonumber(mon), tonumber(day)
									to_total_days = date_to_totaldays(customMatchdaysData[n]["ToDate"])
								end
								-- fixture and gameweek number is a must
								local fixtureNumber = tonumber(customMatchdaysData[n]["FixtureNumber"])
								local gameweekNumber = tonumber(customMatchdaysData[n]["CompetitionGameweek"])
								local isNight
								if customMatchdaysData[n]["isNight"] then
									isNight = tonumber(customMatchdaysData[n]["isNight"])
								end
								local matchStartTime
								if customMatchdaysData[n]["Time"] then
									matchStartTime = tonumber(customMatchdaysData[n]["Time"])
								end
								local homeTeam
								if customMatchdaysData[n]["HomeT"] then
									homeTeam = customMatchdaysData[n]["HomeT"]
								end
								local awayTeam
								if customMatchdaysData[n]["AwayT"] then
									awayTeam = customMatchdaysData[n]["AwayT"]
								end
								local startingYear = yearnow.dec
								if config["STARTS_IN_JAN"] == "false" then
									if to_month <= 6 then
										startingYear = yearnow.dec + 1
									end
								end
								writeGame(
									config,
									startingYear,
									fixtureNumber,
									gameweekNumber,
									from_total_days,
									to_total_days,
									to_month,
									to_day,
									isNight,
									matchStartTime,
									homeTeam,
									awayTeam,
									isGeneric,
									i == currentleagueid.dec
								)
							end
						else
							log("current year config is not found, aborting...")
						end
					else
						log("matchdays or games schedule was not found, skipping current league")
						log("review logs")
					end
				else
					log(string.format("skipping %s, league starts in jan? %s", config["NAME"], config["STARTS_IN_JAN"]))
				end
				-- else
				--     log("league is not in content folder, nothing has changed")
				--     log("if that should not happen, make sure the league name matches the map")
				--     log("and it has config.ini in it with required parameters")
			end
			m.dispose()
		else
			log("that module is useless")
			log(string.format("since %s is empty or problem in map", contentPath))
			log("disable it for better experience")
		end
	end
end

function m.init(ctx)
	if contentPath:sub(1, 1) == "." then
		contentPath = ctx.sider_dir .. contentPath
	end
	m.dispose()
	compsMap = ctx.external_files.read_text_num_map(contentPath .. "\\map_competitions.txt")
	ctx.register("livecpk_data_ready", m.data_ready)
end

return m

-- PES 2021 Real Life Modes Library Module
-- Based on CommonLib.lua by zlac
-- author: Mohamed2746, Grand
-- version: 0.0
-- originally posted on evo-web
-- helper methods/members
-- #########################################################
local startAddress = 0x00007FF4D0000000
local endAddress = 0x00007FF4DFFFFFF0
local tablestartAddress = 0x00007FF4F0000000
local tableendAddress = 0x00007FF4FFFFFFF0

local function hex_to_number(addr)
	return tonumber(string.match(tostring(addr), "0x%x+"))
end

local function team_hex_to_dec(teamHex)
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
local m = {}

-- exposed members/methods
-- ###########################################################
m.version = "0.0"
m.year_addr = nil
m.season_addr = nil
m.champion_addr = nil
m.leagues_champions = {}

function m.hook_year()
	if not m.year_addr then
		m.year_addr = memory.safe_search("\x07\x6d\x01\x00\x00", startAddress, endAddress)
	end
	return m.year_addr
end

function m.hook_season()
	if not m.season_addr then
		m.season_addr = hex_to_number(
			memory.safe_search(
				"\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04\x00\x00\x00\x11\x00\x00",
				startAddress,
				endAddress
			)
		)
	end
	return m.season_addr
end

function m.hook_champion(tid)
	if not m.champion_addr then
		m.champion_addr = memory.safe_search(
			memory.pack("u8", tid)
				.. "\x00"
				.. memory.pack("u16", m.current_year().dec - 1)
				.. memory.pack("u8", tid)
				.. "\x00\x00\x00",
			tablestartAddress,
			tableendAddress
		)
	end
	return m.champion_addr
end

function m.league_champion(tid)
	if not m.leagues_champions[tid] then
		local v1 = memory.pack("u8", tid)
		log(memory.hex(v1))
		local v2 = memory.pack("u16", m.current_year().dec)
		log(memory.hex(v2))
		local search = memory.safe_search(
			v1 .. "\x00" .. m.current_year().hex .. v1 .. "\x00\x00\x00",
			tablestartAddress,
			tableendAddress
		)
		local search2 = memory.safe_search(
			memory.pack("u8", tid)
				.. "\x00"
				.. memory.pack("u16", m.current_year().dec - 1)
				.. memory.pack("u8", tid)
				.. "\x00\x00\x00",
			startAddress,
			endAddress
		)
		log(tostring(search))
		m.leagues_champions[tid].hex = memory.read(search + 792, 4) or 0
		m.leagues_champions[tid].dec = team_hex_to_dec(m.leagues_champions[tid].hex)
	end
	return m.leagues_champions[tid]
end

function m.current_team_id()
	local t = {}
	t.hex = memory.read(m.hook_year() + 13, 4) or 0
	t.dec = team_hex_to_dec(t.hex) or 0
	return t
end

function m.current_year()
	local t = {}
	t.hex = memory.read(m.hook_year() - 1, 2) or 0
	t.dec = memory.unpack("u16", t.hex) or 0
	return t
end

function m.current_season()
	local t = {}
	t.hex = memory.read(m.hook_season() + 24, 2) or 0
	t.dec = memory.unpack("u16", t.hex) or 0
	return t
end

-- function m.current_EPL_champion()
-- local t = {}
-- t.hex = memory.read(m.hook_champion(17) + 792, 4) or 0
-- t.dec = team_hex_to_dec(t.hex) or 0
-- return t
-- end

-- function m.current_Serie_A_champion()
-- local t = {}
-- t.hex = memory.read(m.hook_champion(18) + 792, 4) or 0
-- t.dec = team_hex_to_dec(t.hex) or 0
-- return t
-- end

-- function m.current_LaLiga_champion()
-- local t = {}
-- t.hex = memory.read(m.hook_champion(19) + 792, 4) or 0
-- t.dec = team_hex_to_dec(t.hex) or 0
-- return t
-- end

function m.init(ctx)
	ctx.real_life_mode = m
end

return m

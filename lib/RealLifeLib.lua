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

local function getAddressWithVariableBytesUsingStart(
	addrBeginning,
	variableByteLength,
	addrEndning,
	variableStartAddress
)
	local addr = memory.safe_search(addrBeginning, variableStartAddress, endAddress)
	if addr then
		if memory.read(addr + #addrBeginning + variableByteLength, #addrEndning) == addrEndning then
			return addr
		else
			return getAddressWithVariableBytesUsingStart(
				addrBeginning,
				variableByteLength,
				addrEndning,
				addr + #addrBeginning
			)
		end
	else
		return nil
	end
end

local function tableIsEmpty(self)
	if self then
		for _, _ in pairs(self) do
			return false
		end
	end
	return true
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
m.champion_addrs = {}
m.leagues_champions = {}
m.tables_addrs = {}
m.old_tables_addrs = {}
m.comps_tables = {}

function m.hook_year()
	if not m.year_addr then
		m.year_addr = memory.safe_search("\x07\x6d\x01\x00\x00", startAddress, endAddress)
	end
	return m.year_addr
end

function m.hook_season()
	if not m.season_addr then
		m.season_addr = memory.safe_search(
			"\x01\x00\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01",
			startAddress,
			endAddress
		)
	end
	return m.season_addr
end

function m.hook_table(tid, year)
	if year == "current" then
		if m.tables_addrs[tid.dec] == nil then
			m.tables_addrs[tid.dec] =
				getAddressWithVariableBytesUsingStart("\x64\xC8\x00" .. tid.hex, 771, "\xC9", startAddress)
		end
		return m.tables_addrs[tid.dec]
	else
		if not m.old_tables_addrs[tid.dec] then
			m.old_tables_addrs[tid.dec] =
				memory.safe_search(tid.hex .. memory.pack("u16", year) .. tid.hex, tablestartAddress, tableendAddress)
		end
		return m.old_tables_addrs[tid.dec]
	end
end

function m.comp_table(tid, no_of_teams, year)
	if tableIsEmpty(m.comps_tables[tid.dec]) then
		m.comps_tables[tid.dec] = {}
	end
	if tableIsEmpty(m.comps_tables[tid.dec][year]) then
		local addr = m.hook_table(tid, year)
		if addr then
			log("yes it is")
			m.comps_tables[tid.dec][year] = {}
			for i = 1, no_of_teams do
				m.comps_tables[tid.dec][year][i] = {}
				m.comps_tables[tid.dec][year][i].hex = memory.read(addr + i * 4 + 367, 4)
				m.comps_tables[tid.dec][year][i].dec = team_hex_to_dec(m.comps_tables[tid.dec][year][i].hex)
			end
		else
			return nil
		end
	end
	return m.comps_tables[tid.dec][year]
end

function m.hook_champion(tid)
	if not m.champion_addrs[tid.dec] then
		m.champion_addrs[tid.dec] = memory.safe_search(
			tid.hex .. "\x00" .. memory.pack("u16", m.current_year().dec - 1) .. tid.hex .. "\x00\x00\x00",
			tablestartAddress,
			tableendAddress
		)
	end
	return m.champion_addrs[tid.dec]
end

function m.league_champion(tid)
	if not m.leagues_champions[tid.dec] then
		m.leagues_champions[tid.dec].hex = memory.read(m.hook_champion(tid) + 792, 4) or 0
		m.leagues_champions[tid.dec].dec = team_hex_to_dec(m.leagues_champions[tid.dec].hex)
	end
	return m.leagues_champions[tid.dec]
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
	t.hex = memory.read(m.hook_season() - 3, 2) or 0
	t.dec = memory.unpack("u16", t.hex) or 0
	return t
end

function m.pack_id(encode, decimal)
	if type(decimal) == "table" then
		return decimal
	elseif type(decimal) == "string" or type(decimal) == "number" then
		return {
			["dec"] = tonumber(decimal),
			["hex"] = memory.pack(encode, decimal),
		}
	else
		log("unknown type of 'decimal'")
	end
end

function m.dispose()
	m.year_addr = nil
	m.season_addr = nil
	m.champion_addrs = {}
	m.leagues_champions = {}
	m.tables_addrs = {}
	m.old_tables_addrs = {}
	m.comps_tables = {}
	collectgarbage()
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
	m.dispose()
	ctx.real_life_mode = m
end

return m

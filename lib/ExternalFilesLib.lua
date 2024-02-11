-- PES 2021 External Files Library Module
-- author: Mohamed2746
-- version: 0.0
-- originally posted on evo-web & github
-- helper methods/members
-- #########################################################
local m = {}

-- exposed members/methods
-- ###########################################################
m.version = "0.0"

function m.read_csv(dir)
	-- Head1,Head2,...
	-- Data1,Data2,...

	local f = io.open(dir)
	local firstLine = true
	local t = {}
	local headers = {}
	log(dir)
	if f then
		for line in f:lines() do
			if not string.match(line, ";") then
				if firstLine then
					for word in string.gmatch(line, "([^,]+)") do
						table.insert(headers, word)
					end
					firstLine = false
				else
					local wordCounter = 1
					for word in string.gmatch(line, "([^,]+)") do
						local header = headers[wordCounter]
						table.insert(t[header], word)
						wordCounter = wordCounter + 1
					end
				end
			end
		end
		return t
	else
		return nil
	end
end

function m.read_num_text_map(dir)
	-- 00,Name
	local t = {}
	local f = io.open(dir)
	log(dir)
	if f then
		for line in f:lines() do
			if not string.match(line, ";") then
				local id, name = line:match("^(%d+),(.+)$")
				if id and name then
					t[name] = tonumber(id) or id
				end
			end
		end
		return t
	else
		return nil
	end
end

function m.read_text_num_map(dir)
	-- NAME=00
	local t = {}
	local f = io.open(dir)
	log(dir)
	if f then
		for line in f:lines() do
			if not string.match(line, ";") then
				local name, id = line:match("^(.+)=(%d+)$")
				if id and name then
					if not t[id] then
						t[tonumber(id)] = name
					end
				end
			end
		end
		return t
	else
		return nil
	end
end

function m.read_ini(dir)
	-- HEAD=DATA
	local t = {}
	local f = io.open(dir)
	log(dir)
	if f then
		for line in f:lines() do
			if not string.match(line, ";") then
				local name, value = line:match("^(.+)=(.+)$")
				if value and name then
					t[name] = tonumber(value) or value
				end
			end
		end
		return t
	else
		return nil
	end
end

function m.init(ctx)
	ctx.external_files = m
end

return m

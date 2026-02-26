-- Minimal JSON encoder/decoder for LSP communication
json = {}

json.null = setmetatable({}, {
	__tostring = function()
		return "null"
	end,
})

local ARRAY_MT = { __jsontype = "array" }

function json.array(t)
	return setmetatable(t or {}, ARRAY_MT)
end

----------------------------------------------------------------
-- Encode
----------------------------------------------------------------
local escape_map = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
	["\b"] = "\\b",
	["\f"] = "\\f",
}

local function encode_string(s)
	return '"'
		.. s:gsub('[%z\1-\31"\\]', function(c)
			return escape_map[c] or string.format("\\u%04x", c:byte())
		end)
		.. '"'
end

local encode_value

local function encode_table(t)
	local is_arr = getmetatable(t) == ARRAY_MT
	if not is_arr then
		local n = #t
		if n > 0 then
			local all_int = true
			for k in pairs(t) do
				if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
					all_int = false
					break
				end
			end
			is_arr = all_int
		end
	end
	if is_arr then
		local parts = {}
		for i = 1, #t do
			parts[i] = encode_value(t[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	else
		local parts = {}
		for k, v in pairs(t) do
			if type(k) == "string" then
				parts[#parts + 1] = encode_string(k) .. ":" .. encode_value(v)
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
end

function encode_value(val)
	if val == nil then
		return "null"
	end
	if val == json.null then
		return "null"
	end
	local t = type(val)
	if t == "boolean" then
		return tostring(val)
	end
	if t == "number" then
		if val ~= val then
			return "null"
		end
		return string.format("%.14g", val)
	end
	if t == "string" then
		return encode_string(val)
	end
	if t == "table" then
		return encode_table(val)
	end
	error("json: cannot encode " .. t)
end

function json.encode(val)
	return encode_value(val)
end

----------------------------------------------------------------
-- Decode
----------------------------------------------------------------
function json.decode(str)
	local pos = 1

	local function skip_ws()
		pos = str:match("^%s*()", pos)
	end

	local parse_value

	local function parse_string()
		pos = pos + 1
		local parts = {}
		while pos <= #str do
			local c = str:sub(pos, pos)
			if c == '"' then
				pos = pos + 1
				return table.concat(parts)
			elseif c == "\\" then
				pos = pos + 1
				c = str:sub(pos, pos)
				if c == '"' or c == "\\" or c == "/" then
					parts[#parts + 1] = c
				elseif c == "n" then
					parts[#parts + 1] = "\n"
				elseif c == "r" then
					parts[#parts + 1] = "\r"
				elseif c == "t" then
					parts[#parts + 1] = "\t"
				elseif c == "b" then
					parts[#parts + 1] = "\b"
				elseif c == "f" then
					parts[#parts + 1] = "\f"
				elseif c == "u" then
					local hex = str:sub(pos + 1, pos + 4)
					pos = pos + 4
					local code = tonumber(hex, 16)
					if code and code < 128 then
						parts[#parts + 1] = string.char(code)
					elseif code then
						if code < 0x800 then
							parts[#parts + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + (code % 64))
						else
							parts[#parts + 1] = string.char(
								0xE0 + math.floor(code / 4096),
								0x80 + math.floor((code % 4096) / 64),
								0x80 + (code % 64)
							)
						end
					end
				end
				pos = pos + 1
			else
				parts[#parts + 1] = c
				pos = pos + 1
			end
		end
		error("json: unterminated string")
	end

	local function parse_number()
		local s = pos
		if str:sub(pos, pos) == "-" then
			pos = pos + 1
		end
		while str:sub(pos, pos):match("%d") do
			pos = pos + 1
		end
		if str:sub(pos, pos) == "." then
			pos = pos + 1
			while str:sub(pos, pos):match("%d") do
				pos = pos + 1
			end
		end
		if str:sub(pos, pos):match("[eE]") then
			pos = pos + 1
			if str:sub(pos, pos):match("[+-]") then
				pos = pos + 1
			end
			while str:sub(pos, pos):match("%d") do
				pos = pos + 1
			end
		end
		return tonumber(str:sub(s, pos - 1))
	end

	local function parse_array()
		pos = pos + 1
		local arr = json.array({})
		skip_ws()
		if str:sub(pos, pos) == "]" then
			pos = pos + 1
			return arr
		end
		while true do
			arr[#arr + 1] = parse_value()
			skip_ws()
			local c = str:sub(pos, pos)
			if c == "]" then
				pos = pos + 1
				return arr
			end
			if c == "," then
				pos = pos + 1
			else
				error("json: expected ',' or ']'")
			end
		end
	end

	local function parse_object()
		pos = pos + 1
		local obj = {}
		skip_ws()
		if str:sub(pos, pos) == "}" then
			pos = pos + 1
			return obj
		end
		while true do
			skip_ws()
			local key = parse_string()
			skip_ws()
			if str:sub(pos, pos) ~= ":" then
				error("json: expected ':'")
			end
			pos = pos + 1
			obj[key] = parse_value()
			skip_ws()
			local c = str:sub(pos, pos)
			if c == "}" then
				pos = pos + 1
				return obj
			end
			if c == "," then
				pos = pos + 1
			else
				error("json: expected ',' or '}'")
			end
		end
	end

	function parse_value()
		skip_ws()
		local c = str:sub(pos, pos)
		if c == '"' then
			return parse_string()
		elseif c == "{" then
			return parse_object()
		elseif c == "[" then
			return parse_array()
		elseif c == "t" then
			pos = pos + 4
			return true
		elseif c == "f" then
			pos = pos + 5
			return false
		elseif c == "n" then
			pos = pos + 4
			return json.null
		elseif c == "-" or c:match("%d") then
			return parse_number()
		elseif c == "" then
			error("json: unexpected end of input")
		else
			error("json: unexpected char '" .. c .. "' at " .. pos)
		end
	end

	local result = parse_value()
	return result
end

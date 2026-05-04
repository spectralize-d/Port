-- made by MadeModeZen; spectralize-d on github; oh my god just give me the luau role already
-- a native luau implementation of HttpService:JSONEncode and HttpService:JSONDecode.
-- runs slower obviously since its not in c++ but still fast
-- also supports prettifying

local Json = {}


---- buffer aliases (they save a tiny tiny bit of performance since you dont index each time) ----
local bufCreate   = buffer.create
local bufWriteu8  = buffer.writeu8
local bufReadu8   = buffer.readu8
local bufWritestring = buffer.writestring
local bufReadstring  = buffer.readstring
local bufCopy     = buffer.copy
local bufLen      = buffer.len

local function newWriter(): ((needed: number) -> (), (b: number) -> (), (s: string) -> ())
	local buf  = bufCreate(256)
	local cap  = 256
	local pos  = 0

	local function grow(needed: number)
		local newCap = cap
		while newCap < pos + needed do newCap *= 2 end
		if newCap == cap then return end
		local nb = bufCreate(newCap)
		bufCopy(nb, 0, buf, 0, pos)
		buf = nb
		cap = newCap
	end

	local function writeByte(b: number)
		if pos >= cap then grow(1) end
		bufWriteu8(buf, pos, b)
		pos += 1
	end

	local function writeStr(s: string)
		local slen = string.len(s)
		if slen == 0 then return end
		grow(slen)
		bufWritestring(buf, pos, s)
		pos += slen
	end

	local function finish()
		return bufReadstring(buf, 0, pos)
	end

	return writeByte, writeStr, finish
end


local ESCAPE = {}
for i = 0, 31 do
	ESCAPE[i] = string.format("\\u%04x", i)
end
ESCAPE[34]  = '\\"'   -- "
ESCAPE[92]  = '\\\\'  -- \
ESCAPE[10]  = '\\n'   -- \n
ESCAPE[13]  = '\\r'   -- \r
ESCAPE[9]   = '\\t'   -- \t
ESCAPE[8]   = '\\b'   -- \b
ESCAPE[12]  = '\\f'   -- \f

local byte = string.byte
local sub  = string.sub
local format  = string.format

local encodeValue -- forward

local function writeJsonString(writeByte, writeStr, s)
	writeByte(34) -- opening "

	local start = 1
	local len   = string.len(s)
	local i     = 1
	while i <= len do
		local b = byte(s, i)
		local esc = ESCAPE[b]
		if esc then
			if i > start then writeStr(sub(s, start, i - 1)) end
			writeStr(esc)
			start = i + 1
		end
		i += 1
	end
	if start <= len then writeStr(sub(s, start, len)) end

	writeByte(34) -- closing "
end

local function writeTable(writeByte, writeStr, tbl, indent, options)
	local pretty     = options.pretty
	local tab        = options.tab
	local nextIndent = indent .. tab

	-- array vs dictionary
	local isArray = true
	local maxN    = 0
	for key in tbl do
		if type(key) ~= "number" or key ~= math.floor(key :: number) or key < 1 then
			isArray = false; break
		end
		if key > maxN then maxN = key end
	end
	if isArray and maxN ~= #tbl then isArray = false end

	-- Empty shorthand
	if next(tbl) == nil then
		writeStr(isArray and "[]" or "{}")
		return
	end

	if isArray then
		local allScalar = true
		for _, v in ipairs(tbl) do
			if type(v) == "table" then allScalar = false; break end
		end

		-- Inline short scalar arrays
		if pretty and allScalar and #tbl <= options.inlineArrayLimit then
			writeByte(91) -- [
			for i = 1, #tbl do
				if i > 1 then writeStr(", ") end
				encodeValue(writeByte, writeStr, tbl[i], nextIndent, options)
			end
			writeByte(93) -- ]
			return
		end

		writeByte(91) -- [
		for i = 1, #tbl do
			if pretty then
				writeByte(10) -- \n
				writeStr(nextIndent)
			end
			encodeValue(writeByte, writeStr, tbl[i], nextIndent, options)
			if i < #tbl then writeByte(44) end -- ,
		end
		if pretty then
			writeByte(10) -- \n
			writeStr(indent)
		end
		writeByte(93) -- ]

	else
		local keys = {}
		for key in tbl do keys[#keys+1] = key end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local klen = #keys

		writeByte(123) -- {
		for i, k in ipairs(keys) do
			if pretty then
				writeByte(10) -- \n
				writeStr(nextIndent)
			end
			writeJsonString(writeByte, writeStr, tostring(k))
			writeStr(pretty and ": " or ":")
			encodeValue(writeByte, writeStr, tbl[k], nextIndent, options)
			if i < klen then writeByte(44) end -- ,
		end
		if pretty then
			writeByte(10) -- \n
			writeStr(indent)
		end
		writeByte(125) -- }
	end
end

encodeValue = function(writeByte, writeStr, val:any|unknown, indent, options)
	local t = type(val)
	if val == nil then
		writeStr("null")
	elseif t == "boolean" then
		writeStr(val and "true" or "false")
	elseif t == "number" then
		if val ~= val or val == math.huge or val == -math.huge then
			writeStr("null")
		elseif val == math.floor(val) and math.abs(val) < 1e15 then
			writeStr(format("%d", val))
		else
			writeStr(format("%14g", val))
		end
	elseif t == "string" then
		writeJsonString(writeByte, writeStr, val)
	elseif t == "table" then
		writeTable(writeByte, writeStr, val, indent, options)
	else
		error("Cannot encode type: " .. t)
	end
end

function Json.encode(value, options)
	options = options or {}
	local pretty = options.pretty ~= false
	local resolved = {
		pretty           = pretty,
		tab              = pretty and (options.tab or "  ") or "",
		inlineArrayLimit = options.inlineArrayLimit or 8,
	}
	local writeByte, writeStr, finish = newWriter()
	encodeValue(writeByte, writeStr, value, "", resolved)
	return finish()
end

-- decoder --

local function makeParser(src: string)
	-- Load src into buffer
	local srcLen = string.len(src)
	local srcBuf = bufCreate(srcLen)
	bufWritestring(srcBuf, 0, src)

	local pos = 0  -- buffers use 0 index

	local QUOTE  = 34
	local LBRACE = 123
	local RBRACE = 125
	local LBRACK = 91
	local RBRACK = 93
	local COMMA  = 44
	local COLON  = 58
	local BSLASH = 92
	local SPACE  = 32
	local TAB    = 9
	local CR     = 13
	local LF     = 10

	local function skipWhitespace()
		while pos < srcLen do
			local b = bufReadu8(srcBuf, pos)
			if b == SPACE or b == TAB or b == CR or b == LF then
				pos += 1
			else
				break
			end
		end
	end

	local parseValue

	local function parseString()
		pos += 1 -- skip "
		local parts   = {}
		local start   = pos
		while pos < srcLen do
			local b = bufReadu8(srcBuf, pos)
			if b == QUOTE then
				if pos > start then
					parts[#parts+1] = bufReadstring(srcBuf, start, pos - start)
				end
				pos += 1
				return table.concat(parts)
			elseif b == BSLASH then
				if pos > start then
					parts[#parts+1] = bufReadstring(srcBuf, start, pos - start)
				end
				pos += 1
				local e = bufReadu8(srcBuf, pos)
				pos += 1
				if     e == QUOTE  then parts[#parts+1] = '"'
				elseif e == BSLASH then parts[#parts+1] = '\\'
				elseif e == 47     then parts[#parts+1] = '/'   -- /
				elseif e == 110    then parts[#parts+1] = '\n'  -- n
				elseif e == 114    then parts[#parts+1] = '\r'  -- r
				elseif e == 116    then parts[#parts+1] = '\t'  -- t
				elseif e == 98     then parts[#parts+1] = '\b'  -- b
				elseif e == 102    then parts[#parts+1] = '\f'  -- f
				elseif e == 117    then                          -- u
					local cp = tonumber(bufReadstring(srcBuf, pos, 4), 16)
					pos += 4
					if cp then parts[#parts+1] = utf8.char(cp) end
				else
					error("Unknown escape at pos " .. pos)
				end
				start = pos
			else
				pos += 1
			end
		end
		error("Unterminated string")
	end

	local function parseNumber()
		local startPos = pos
		-- optional leading minus
		if bufReadu8(srcBuf, pos) == 45 then pos += 1 end
		-- integer digits
		while pos < srcLen do
			local b = bufReadu8(srcBuf, pos)
			if b < 48 or b > 57 then break end
			pos += 1
		end
		-- optional fractional
		if pos < srcLen and bufReadu8(srcBuf, pos) == 46 then
			pos += 1
			while pos < srcLen do
				local b = bufReadu8(srcBuf, pos)
				if b < 48 or b > 57 then break end
				pos += 1
			end
		end
		-- scientific notation?
		if pos < srcLen then
			local b = bufReadu8(srcBuf, pos)
			if b == 101 or b == 69 then -- e/E
				pos += 1
				if pos < srcLen then
					local s = bufReadu8(srcBuf, pos)
					if s == 43 or s == 45 then pos += 1 end -- + -
				end
				while pos < srcLen do
					local b2 = bufReadu8(srcBuf, pos)
					if b2 < 48 or b2 > 57 then break end
					pos += 1
				end
			end
		end
		return tonumber(bufReadstring(srcBuf, startPos, pos - startPos))
	end

	local function parseArray()
		pos += 1 -- skip [
		skipWhitespace()
		local arr = {}
		if bufReadu8(srcBuf, pos) == RBRACK then pos += 1; return arr end
		while true do
			skipWhitespace()
			arr[#arr+1] = parseValue()
			skipWhitespace()
			local b = bufReadu8(srcBuf, pos)
			if b == RBRACK then pos += 1; break end
			if b ~= COMMA then error("Expected ',' or ']' at pos " .. pos) end
			pos += 1
		end
		return arr
	end

	local function parseObject()
		pos += 1 -- skip {
		skipWhitespace()
		local obj = {}
		if bufReadu8(srcBuf, pos) == RBRACE then pos += 1; return obj end
		while true do
			skipWhitespace()
			local key = parseString()
			skipWhitespace()
			if bufReadu8(srcBuf, pos) ~= COLON then
				error("Expected ':' at pos " .. pos)
			end
			pos += 1
			skipWhitespace()
			obj[key] = parseValue()
			skipWhitespace()
			local b = bufReadu8(srcBuf, pos)
			if b == RBRACE then pos += 1; break end
			if b ~= COMMA then error("Expected ',' or '}' at pos " .. pos) end
			pos += 1
		end
		return obj
	end

	parseValue = function()
		skipWhitespace()
		local b = bufReadu8(srcBuf, pos)
		if     b == QUOTE  then return parseString()
		elseif b == LBRACE then return parseObject()
		elseif b == LBRACK then return parseArray()
		elseif b == 116 then pos += 4; return true   -- truthy
		elseif b == 102 then pos += 5; return false  -- falsy
		elseif b == 110 then pos += 4; return nil    -- null/nil
		elseif b == 45 or (b >= 48 and b <= 57) then -- - or 0-9
			return parseNumber()
		else
			error(format("Unexpected character (byte: %d) at pos %d", b, pos))
		end
	end

	return parseValue
end

function Json.decode(src)
	if typeof(src) ~= "string" then
		warn(format("Json.decode must be passed a 'string', got a '%s'", typeof(src)))
		return nil
	end
	return makeParser(src)()
end

return Json

local module = {}
-- metamethod container
local mt = {}; mt.__index = mt;

type bnum_internal = {number}
-- bnum table containing all functions such as add, pow, lbencode, etc
export type bnum = typeof(setmetatable({} :: bnum_internal, mt))
-- {1, 2}, "100", 100, etc
export type input = bnum | bnum_internal | string | number

-- suffixes for bnum:ToSuffix()
local suffixes = table.freeze({
	-- 1e3 * index
	[0] = {"k","M","B"};
	{"", "U","D","T","Qd","Qn","Sx","Sp","Oc","No"};
	-- 1e3 * (1e30 * index)
	{"", "De","Vt","Tg","qg","Qg","sg","Sg","Og","Ng"};
	-- 1e3 * (1e300 * index)
	{"", "Ce", "Du","Tr","Qa","Qi","Se","Si","Ot","Ni"};
	-- 1e3 + (1e3000 * (1e3 ^ index))
	{"", "Mi","Mc","Na", "Pi", "Fm", "At", "Zp", "Yc", "Xo", "Ve", "Me",
		"Due", "Tre", "Te", "Pt", "He", "Hp", "Oct", "En", "Ic", "Mei", "Dui", "Tri", "Teti",
		"Pti", "Hei", "Hp", "Oci", "Eni", "Tra", "TeC", "MTc", "DTc", "TrTc", "TeTc", "PeTc",
		"HTc", "HpT", "OcT", "EnT", "TetC", "MTetc", "DTetc", "TrTetc", "TeTetc", "PeTetc",
		"HTetc", "HpTetc", "OcTetc", "EnTetc", "PcT", "MPcT", "DPcT", "TPCt", "TePCt", "PePCt",
		"HePCt", "HpPct", "OcPct", "EnPct", "HCt", "MHcT", "DHcT", "THCt", "TeHCt", "PeHCt",
		"HeHCt", "HpHct", "OcHct", "EnHct", "HpCt", "MHpcT", "DHpcT", "THpCt", "TeHpCt", "PeHpCt",
		"HeHpCt", "HpHpct", "OcHpct", "EnHpct", "OCt", "MOcT", "DOcT", "TOCt", "TeOCt", "PeOCt",
		"HeOCt", "HpOct", "OcOct", "EnOct", "Ent", "MEnT", "DEnT", "TEnt", "TeEnt", "PeEnt",
		"HeEnt", "HpEnt", "OcEnt", "EnEnt", "Hect", "MeHect"};
})

-- 
local function FromComponents_noNormalize(mantissa: number, exponent: number): bnum
	return setmetatable({mantissa, exponent}, mt)
end
-- Pi and E, used for factorialization
local MathPi = FromComponents_noNormalize(3.141592653589793238462643383279502884197169399375105820974, 0)
local MathE = FromComponents_noNormalize(2.718281828459045235360287471352662497757247093699959574966, 0)

local function fround(num: number, digits: number): number
	return math.round(num * 10 ^ digits) / 10 ^ digits
end
module.fround = fround
-- used for OrderedDataStore(s) to encode large numbers
local function lbencode(bnum: input): number
	if not module.valid(bnum) then
		bnum = module.convert(bnum)
	end
	bnum = bnum:add(1) -- offset precision once
	bnum = bnum:log10() -- raises the limit from 9.223e18 to 1.79767e308
	bnum = bnum:add(1) -- offset again
	bnum = bnum:log10() -- raises the limit from 1.79767e308 to 10^10^1.79767e308
	bnum = bnum:add(1) -- offset one last time
	return bnum:ToNumber() * 29000000000000000 -- perfect offset to avoid most rounding errors
end

local function lbdecode(int: number): bnum
	if type(int) ~= "number" then return FromComponents_noNormalize(0, 0) end
	int /= 29000000000000000 -- initial offset
	local initial = module.convert(fround(int, 14) --[[remove unnecessary precision; tested and past this does not affect the result]])
	local bnum = initial:sub(1)--[[offset precision once to get closer]]:pow10()--[[supports up to 1.79767e308]]
	:sub(1)--[[offset even further, two more steps until the end result]]:pow10()--[[up to 10^10^308]]:sub(1)--[[number is fully decoded]]
	return bnum
end

local function normalize(bnum: bnum): bnum
	local signal = "+"
	if bnum[1] == 0 then -- a mantissa of 0 means the exponent should be zero, but we correct it just incase.
		bnum[2] = 0
		return bnum
	end
	if bnum[1] < 0 then -- mantissa is negative
		signal = "-"
	end
	if signal == "-" then -- multiply the mantissa by -1, used after this to correct to a negative exponent
		bnum[1] = bnum[1] * -1
	end
	local signal2 = "+"
	if bnum[2] < 0 then -- exponent is negative, change signal2 and fix the exponent
		signal2 = "-"
		bnum[2] = bnum[2] * -1
	end
	if math.fmod(bnum[2], 1) > 0 and signal2 == "-" then -- i really cant describe this, its a bunch of math
		bnum[1] = bnum[1] * (10^ (1 - math.fmod(bnum[2], 1)))
		bnum[2] = math.floor(bnum[2]) + 1
	elseif math.fmod(bnum[2], 1) > 0 and signal2 == "+"  then
		bnum[1] = bnum[1] * (10^  math.fmod(bnum[2], 1))
		bnum[2] = math.floor(bnum[2])
	end
	if signal2 == "-" then
		bnum[2] = bnum[2] * -1		
	end
	local DgAmo = math.log10(bnum[1])
	DgAmo = math.floor(DgAmo)
	bnum[1] = bnum[1] / 10^DgAmo
	bnum[2] = bnum[2] + DgAmo	
	bnum[2] = math.floor(bnum[2])
	if signal == "-" then
		bnum[1] = bnum[1] * -1		
	end
	return bnum
end


local function FromComponents(mantissa: number, exponent: number)
	return normalize(FromComponents_noNormalize(mantissa, exponent))
end


module.valid = function(input: input): boolean
	if type(input) ~= "table" then return false end -- cant be a bnum if it isnt a table
	-- 1. must have metatable equal to mt and 2. index 1 & 2 must exist and both be numbers
	return getmetatable(input) == mt and type(input[1]) == "number" and type(input[2]) == "number"
end

mt.IsInf = function(self: bnum): boolean -- exponent is equal to math.huge
	return self[2] == 1/0
end
mt.IsZero = function(self: bnum): boolean -- any number with a mantissa of zero is zero
	return self[1] == 0
end
mt.IsNaN = function(self: bnum): boolean -- if a number is not equal to itself, then it means its NaN (Not a Number)
	return self[1] ~= self[1]
end

mt.pow10 = function(self: bnum): bnum -- macro for 10 ^ x
	return module.pow(10, self)
end

module.pow10 = function(input: input): bnum
	return module.pow(10, input)
end

mt.ToSuffix = function(self: bnum, digits: number?): string
	digits = digits or 2
	local bnum: bnum = normalize(self)
	local Exponent: number = bnum[2]
	local Mantissa: number = bnum[1]
	local leftover = math.fmod(Exponent, 3)
	Exponent = math.floor(Exponent / 3) - 1
	if bnum:IsInf() then
		return (bnum[1] < 0 and "-" or "" --[[negative or positive infinity]]).."Infinity"
	end
	if Exponent < 3 then -- number is below 1e12 (1T), skip other steps and use default
		return fround(Mantissa * 10 ^ leftover, digits) .. (suffixes[0][Exponent + 1] or "")
	end
	local suffix = ""
	local function suffixpart(n: number)
		local Hundreds = math.floor(n / 100)
		n = math.fmod(n, 100) -- ; n %= 100
		local Tens = math.floor(n / 10)
		n = math.fmod(n, 10) -- ; n %= 10
		local Ones = math.floor(n/1)
		suffix ..= suffixes[1][Ones + 1]
		suffix ..= suffixes[2][Tens + 1]
		suffix ..= suffixes[3][Hundreds + 1]
	end
	local function suffixpart2(n: number)
		if n > 0 then n += 1 end
		if n > 1000 then n = math.fmod(n, 1000) end
		local Hundreds = math.floor(n / 100)
		n = math.fmod(n, 100) -- ; n %= 100
		local Tens = math.floor(n / 10)
		n = math.fmod(n, 10) -- ; n %= 10
		local Ones = math.floor(n/1)
		suffix ..= suffixes[1][Ones + 1]
		suffix ..= suffixes[2][Tens + 1]
		suffix ..= suffixes[3][Hundreds + 1]
	end
	if Exponent < 1000 then -- < 1e3003
		suffixpart(Exponent) -- set the suffix string to e.g 'SpDe'
		return fround(Mantissa * 10 ^ leftover, digits --[[fixed precision, does not include zeros]]) .. suffix
	end

	-- only for 1e3003+
	for i = #suffixes[4], 0, -1 do
		if Exponent >= 10 ^ (i * 3) then
			suffixpart2(math.floor(Exponent / 10 ^ (i * 3) - 1))
			suffix ..= suffixes[4][i + 1]
			Exponent = math.fmod(Exponent, 10 ^ (i * 3))
		end
	end
	return fround(Mantissa * 10 ^ leftover, digits) .. suffix
end
module.ToSuffix = function(input: input, digits: number?): string
	return module.convert(input):ToSuffix(digits)
end

local function fromScientific(str: string): bnum?
	if type(str) ~= "string" then return nil end
	if not string.find(string.lower(str), "e") then return nil end
	local splits: {string} = string.split(str, "e") -- ; MantissaeExponent
	local mantissa: number = tonumber(splits[1]) or 1
	local exponent: number = tonumber(splits[2])
	if splits[3] then
		exponent = (tonumber(splits[2]) or 1 ) * 10 ^ tonumber(splits[3])
	end
	return FromComponents(mantissa, exponent)	
end

local function fromDefaultString(str: string): bnum?
	if type(str) ~= "string" then return nil end
	if not string.find(string.lower(str), ";") then return nil end
	local splits: {string} = string.split(str, ";") -- ; Mantissa;Exponent
	local mantissa: number = tonumber(splits[1])
	local exponent: number = tonumber(splits[2])
	return FromComponents(mantissa, exponent)
end



local function fromString(str: string): bnum?
	local fromSci, fromDS = fromScientific(str), fromDefaultString(str)
	if fromSci then
		return fromSci
	elseif fromDS then
		return fromDS
	end
	local tonum = tonumber(str)
	if tonum then
		return FromComponents(tonum, 0)
	end
	return nil
end
module.convert = function(input: input): bnum
	local fromStr = fromString(input)
	if fromStr then
		return fromStr
	end
	if type(input) == "number" then
		return FromComponents(input, 0)
	end
	if type(input) == "table" then
		if input.Mantissa then
			return fromScientific(input.Mantissa.."e"..input.Exponent) or FromComponents_noNormalize(0, 0)
		elseif #input == 2 then
			return fromScientific(input[1].."e"..input[2]) or FromComponents_noNormalize(0, 0)
		elseif #input == 3 then -- EternityNum mode #1; external module support
			if input[2] > 1 then -- a layer over 1 (this index) is greater than or equal to an infinite bnum
				return FromComponents_noNormalize(1, 1e309)
			end
			local exponent = input[3] * (10 ^ input[2])
			return FromComponents(input[1], exponent)
		elseif input.Sign then -- EternityNum mode #2; external module support
			if input.Layer > 1 then -- a layer over 1 is greater than or equal to an infinite bnum
				return FromComponents_noNormalize(1, 1e309)
			end
			local exponent = input.Layer * (10 ^ input.Exp) -- 1 * 10 ^ 15; layer = 1, exp = 15
			return FromComponents(input.Sign, exponent)
		end
	end
	return FromComponents_noNormalize(0, 0)
end

mt.ToString = function(self: bnum, digits: number?): string
	digits = digits or 21
	local bnum = normalize(self)
	return fround(bnum[1], digits) .. "e" .. bnum[2]
end
mt.__tostring = mt.ToString
module.ToString = function(input: input, digits: number?): string
	return module.convert(input):ToString(digits)
end

mt.ToNumber = function(self: bnum): number
	-- simply tonumber("1e3") for example; ToString returns a scientific notation represantation of the bnum
	return tonumber(self:ToString())
end
module.ToNumber = function(input: input): number
	return module.convert(input):ToNumber()
end

mt.div = function(self: bnum, other: input): bnum
	local bnum1:bnum,bnum2:bnum = normalize(self), module.convert(other)
	local bnum3: bnum = FromComponents_noNormalize(0, 0)
	bnum3[1] = bnum1[1] / bnum2[1] -- dividing the mantissa
	bnum3[2] = bnum1[2] - bnum2[2] -- exponent1 - exponent2
	return normalize(bnum3)
end
mt.__div = mt.div
module.div = function(input: input, value: input): bnum
	return module.convert(input):div(value)
end

mt.mul = function(self: bnum, other: input): bnum
	local bnum1:bnum,bnum2:bnum = normalize(self), module.convert(other)
	local bnum3: bnum = FromComponents_noNormalize(0, 0)
	bnum3[1] = bnum1[1] * bnum2[1] -- multiplying the mantissa
	bnum3[2] = bnum1[2] + bnum2[2] -- exponent1 + exponent2
	return normalize(bnum3)
end
mt.__mul = mt.mul
module.mul = function(input: input, value: input): bnum
	return module.convert(input):mul(value)
end

mt.log10 = function(self: bnum): bnum
	local bnum: bnum = normalize(self)
	-- exponent + log10(mantissa)
	return FromComponents(bnum[2] + math.log10(bnum[1]), 0)
end
module.log10 = function(input: input): bnum
	return module.convert(input):log10()
end

mt.compare = function(self: bnum, input: input): number
	local bnum1: bnum, bnum2: bnum = normalize(self), module.convert(input)
	if bnum1[2] > bnum2[2] then -- exponent2 > exponent1, return GT signal
		return 1
	elseif bnum1[2] == bnum2[2] then
		if bnum1[1] > bnum2[1] then
			return 1 -- exponent2 == exponent 1 and mantissa1 > mantissa2, return GT signal
		elseif bnum1[1] == bnum2[1] then
			return 0 -- both components equal, return EQ signal
		end
	end
	return -1 -- exponent2 > exponent1, return LT signal
end
module.compare = function(input: input, value: input): number
	return module.convert(input):compare(value)
end
-- comparison macro start
mt.eq = function(self: bnum, input: input): boolean
	return self:compare(input) == 0
end
mt.__eq = mt.eq
module.eq = function(input: input, value: input): boolean
	return module.convert(input):eq(value)
end

mt.lt = function(self: bnum, input: input): boolean
	return self:compare(input) == -1
end
mt.__lt = mt.lt
module.lt = function(input: input, value: input): boolean
	return module.convert(input):lt(value)
end

mt.lte = function(self: bnum, input: input): boolean
	return self:compare(input) <= 0
end
mt.__le = mt.lte
module.lte = function(input: input, value: input): boolean
	return module.convert(input):lte(value)
end

mt.gt = function(self: bnum, input: input): boolean
	return self:compare(input) == 1
end
module.gt = function(input: input, value: input): boolean
	return module.convert(input):gt(value)
end

mt.gte = function(self: bnum, input: input): boolean
	return self:compare(input) >= 0
end
module.gte = function(input: input, value: input): boolean
	return module.convert(input):gte(value)
end
-- comparison macro end

mt.add = function(self: bnum, input: input): bnum
	local bnum1: bnum, bnum2: bnum = normalize(self), module.convert(input)
	local bnum3 = FromComponents_noNormalize(0, 0)
	local diff = bnum2[2] - bnum1[2]
	if diff > 20 then -- 1e20+ difference, return the bigger number
		return bnum2
	elseif diff < -20 then
		return bnum1
	end
	bnum3[2] = bnum1[2]
	bnum3[1] = bnum1[1] + (bnum2[1] * 10^diff) --[[
		bnum1 = {1, 3}; bnum2 = {1, 4}; 1 * 10 ^ 1 = 10; bnum3 = {11, 3} or {1.1, 4} (11000)
	]]
	return normalize(bnum3)
end
mt.__add = mt.add
module.add = function(input: input, value: input): bnum
	return module.convert(input):add(value)
end

mt.sub = function(self: bnum, input: input): bnum
	local bnum1: bnum, bnum2: bnum = normalize(self), module.convert(input)
	local bnum3 = FromComponents_noNormalize(0, 0)
	local diff = bnum2[2] - bnum1[2]
	if diff > 20 then
		return FromComponents(bnum1[1] * -1, bnum2[2])
	elseif diff < - 20 then
		return bnum1
	end
	bnum3[2] = bnum1[2]
	bnum3[1] = bnum1[1] - (bnum2[1] * 10^diff) --[[
	bnum1 = {1, 4}; bnum2 = {1, 3}; 1 * 10 ^ -1 = 0.1; bnum3 = {0.9, 4} or {9, 3} (9000)
	]]
	return normalize(bnum3)
end
mt.__sub = mt.sub
module.sub = function(input: input, value: input): bnum
	return module.convert(input):sub(value)
end

mt.pow = function(self: bnum, input: input): bnum
	local bnum1: bnum, bnum2: bnum = normalize(self), module.convert(input)
	local bnum3 = FromComponents_noNormalize(0, 0)
	if bnum1[1] == 0 and bnum2[1] ~= 0 then -- 0 ^ x = 0
		return FromComponents_noNormalize(0, 0)
	elseif bnum1[1] == 0 and bnum2[1] == 0 then
		return FromComponents_noNormalize(1, 0) -- 0 ^ 0 is mathematically 0
	elseif bnum1[1] == 1 and bnum1[2] == 0 then -- 1 ^ 0 is zero
		return FromComponents_noNormalize(1, 0)
	elseif bnum2[1] == 1 and bnum2[2] == 0 then -- x ^ 1 is x
		return bnum1
	end
	
	local N = bnum1:log10() -- log10
	N = N:ToNumber()
	N *= bnum2:ToNumber() -- log10 * x
	bnum3[2] = N --[[
		bnum1 = {1, 2}; bnum2 = {1, 1};
		N = 2 [ log10(100) ]
		N * 10 (bnum2 = 1 [mantissa] * 10 ^ 1 [exponent]) = 20;
		bnum3.exponent = 20; 1e20 == 100 ^ 10
	]]
	bnum3[1] = 1
	if bnum1[1] < 0 then -- to support negative exponents, if first is negative then negate the result
		bnum3[1] *= -1
	end
	if bnum2[1] < 0 then -- negate the result again if the second is negative
		bnum3[1] *= -1
	end
	return normalize(bnum3)
end
mt.__pow = mt.pow
module.pow = function(input: input, value: input): bnum
	return module.convert(input):pow(value)
end
-- macro, powers x to 0.5
mt.sqrt = function(self: bnum)
	return self:pow(0.5)
end
module.sqrt = function(input: input): bnum
	return module.convert(input):sqrt()
end
-- natural logarithm of x
mt.ln = function(self: bnum)
	local bnum = normalize(self)
	local LogTen = bnum[2] + math.log10(bnum[1])
	LogTen /= math.log10(2.718281828045905)
	return FromComponents(LogTen, 0)
end
module.ln = function(input: input): bnum
	return module.convert(input):ln()
end

mt.rand = function(self: bnum, max: input): bnum -- returns a random number between min (self) and max
	local rand = module.convert(math.random())
	local x = rand * self:sub(max)
	x += max
	return x
end
module.rand = function(min: input, max: input): bnum
	return module.convert(min):rand(max)
end

mt.abs = function(self: bnum) -- the negative exponent will correct itself because the mantissa is positive
	return FromComponents(math.abs(self[1]), self[2])
end
module.abs = function(input: input): bnum
	return module.convert(input):abs()
end

mt.floor = function(self: bnum): bnum -- macro; doesnt work if number is >=1e16
	if self[2] > 15 then
		return self
	end
	return FromComponents(math.floor(self:ToNumber()), 0)
end

module.floor = function(input: input): bnum
	return module.convert(input):floor()
end

mt.log = function(self: bnum, base: input?)
	--[[
		logX(Y) = log10(X) / log10(Y)
	]]
	if base then
		local b = module.ToNumber(base)
		local LogTen = self[2] + math.log10(self[1])
		LogTen /= math.log10(b)
		return FromComponents(LogTen, 0)
	else
		return self:ln()
	end
end
module.log = function(input: input, base: input?): bnum
	return module.convert(input):log(base)
end

mt.fact = function(self: bnum): bnum
	--[[
	factorial
	approximate error:  [n+1] ^ 5
	]]
	-- computing log2
	local bnum: bnum = normalize(self)
	local TwoPin = module.mul(MathPi, 2)
	local res2 = module.convert(1/12) / bnum
	local res3 = module.convert(1/360) / (bnum ^ 3)
	TwoPin = TwoPin * bnum
	TwoPin = TwoPin:sqrt()
	-- compute resource
	res2 -= res3
	res2 = MathE ^ res2
	res3 = bnum / 3
	res3 ^= bnum
	res3 *= TwoPin
	local Final = res2 * res3
	if Final[2] <= -1 and Final[1] > 9.99 then
		Final[2] = -1
	elseif Final[2] <= -1 then
		Final[2] = 0
	end
	return Final
end
module.fact = function(input: input): bnum
	return module.convert(input):fact()
end

mt.gamma = function(self: bnum): bnum -- (n-1)!, approx error is [n+1] ^ 5
	return self:sub(1):fact()
end
module.gamma = function(input: input): bnum
	return module.convert(input):gamma()
end

mt.fmod = function(self: bnum, val: input): bnum
	local bnum1, bnum2 = normalize(self), module.convert(val)
	local MultiplyBy = bnum2
	local origexp = bnum2[1]
	local origtet = bnum2[2]
	bnum2[2] = bnum1[2]
	if bnum1[2] > bnum2[2] then
		bnum2[2] = bnum1[2] - 1
	end
	local M = 0
	-- you must get 64 things for an accurate fmod
	repeat
		local VT = module.div(bnum1, bnum2)
		VT = module.floor(VT)
		VT = module.mul(VT, bnum2)
		bnum1 = module.sub(bnum1, VT)



		bnum2[2] = bnum2[2] - 1
	until module.lt(bnum1, {origexp, origtet})
	if not module.eq(bnum1, module.abs(bnum1)) then
		return module.fmod(module.abs(bnum1), {origexp, origtet})
	end

	return bnum1
end

module.fmod = function(input: input, value: input): bnum
	return module.convert(input):fmod(value)
end

mt.lbencode = function(self: bnum): number
	return lbencode(self)
end

module.lbencode = function(input: input): number
	return module.convert(input):lbencode()
end
-- this function mutates the decimal it is called on
mt.lbdecode = function(self: bnum, int: number): bnum
	local bnum = lbdecode(int)
	-- set components to that of the decoded bnum
	self[1] = bnum[1]
	self[2] = bnum[2]
	return self
end

module.lbdecode = function(int: number): bnum
	return lbdecode(int)
end

return module

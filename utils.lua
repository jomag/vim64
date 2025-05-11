UNINITIALIZED = "uninitialized"

if not bit then
	require "compat54"
end

-- Returns true if bit n in value is set. Zero-based.
function bit_set(value, n)
	return bit.band(value, bit.lshift(1, n)) ~= 0
end

function bit7(value)
	return bit.band(value, 128) ~= 0
end

function bit6(value)
	return bit.band(value, 64) ~= 0
end

function bit5(value)
	return bit.band(value, 32) ~= 0
end

function bit4(value)
	return bit.band(value, 16) ~= 0
end

function bit3(value)
	return bit.band(value, 8) ~= 0
end

function bit0(value)
	return bit.band(value, 1) ~= 0
end

-- Replace upper 8 bits in 16-bit word
function set_hi_byte(v, hi)
	return bit.bor(bit.band(v, 0x00FF), bit.lshift(hi, 8))
end

-- Replace lower 8 bits in 16-bit word
function set_lo_byte(v, lo)
	return bit.bor(bit.band(v, 0xFF00), lo)
end

function mask_byte(value)
	return bit.band(value, 0xFF)
end

-- Construct a 16 bit word from two bytes
function word(lo, hi)
	return bit.bor(lo, bit.lshift(hi, 8))
end

function inc_byte(b)
	return bit.band(b + 1, 0xFF)
end

function dec_byte(b)
	return bit.band(b - 1, 0xFF)
end

function byte_as_i8(b)
	validate_u8(b)
	if bit7(b) then
		return -(0x100 - b)
	else
		return b
	end
end

-- Return the upper byte of 16-bit word
function upper_byte(w)
	return bit.band(bit.rshift(w, 8), 0xFF)
end

function printf(s, ...)
	return io.write(s:format(...))
end

function fatal(s, ...)
	print(debug.traceback())
	error(io.write(s:format(...) .. "\n"))
end

function format_bits(byte, sep)
	if sep == nil then
		sep = ""
	end
	local s = ""
	for i = 0, 7 do
		s = s .. (i > 0 and sep or "") .. (bit_set(byte, (7 - i)) and 1 or 0)
	end
	return s
end

function base64_decode(enc)
	local res = {}
	local i = 1
	local enc = enc:gsub('=', '')

	local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" .. "abcdefghijklmnopqrstuvwxyz" .. "0123456789+/"
	local inv_alpha = {}
	for i = 1, #alpha do
		inv_alpha[alpha:sub(i, i)] = i - 1
	end

	while i <= #enc do
		local a = inv_alpha[enc:sub(i, i)]
		local b = inv_alpha[enc:sub(i + 1, i + 1)]
		local c = inv_alpha[enc:sub(i + 2, i + 2)]
		local d = inv_alpha[enc:sub(i + 3, i + 3)]

		local x = bit.bor(a, bit.lshift(bit.band(b, 3), 6))
		local y = bit.bor(bit.rshift(b, 2), bit.lshift(bit.band(c, 0xF), 4))
		local z = bit.bor(bit.rshift(c, 4), bit.lshift(d, 6))

		print("x:" .. x)
		print("y:" .. y)
		print("z:" .. z)

		i = i + 4
	end
end

function load_bin(path)
	local f = io.open(path, "rb")
	if f == nil then
		return nil
	end

	local data = f:read("*all")
	f:close()


	local bin = {}
	for i = 1, #data do
		bin[i - 1] = string.byte(data, i)
	end

	return bin
end

function validate_u16(v)
	if type(v) ~= "number" then
		fatal("invalid u16 value: expected number, got %s", type(v))
	end

	if v < 0 or v > 0xFFFF then
		fatal("invalid u16 value: valid range 0 to 0xFFFF, got " .. v)
	end
end

function validate_u8(v)
	if type(v) ~= "number" then
		fatal("invalid u8 value: expected number, got %s", type(v))
	end

	if v < 0 or v > 255 then
		fatal("invalid u8 value: valid range 0 to 255, got " .. v)
	end
end

function get_key_count(tbl)
	local count = 0
	for _ in pairs(tbl) do count = count + 1 end
	return count
end

function is_digit(s)
	return s:match("^[0-9]$") ~= nil
end

function zero_based(v)
	return v
end

function merge(a, b)
	m = {}
	for k, v in pairs(a) do
		m[k] = v
	end
	for k, v in pairs(b) do
		m[k] = v
	end
	return m
end

-- Calls fun(i) n times, and return result in a zero-based list
function map_range(n, fun_or_val)
	local res = {}
	for i = 0, n - 1 do
		if type(fun_or_val) == "function" then
			res[i] = fun_or_val(i)
		else
			res[i] = fun_or_val
		end
	end
	return res
end

function table_length(tbl)
	local c = 0
	for v in pairs(tbl) do
		c = c + 1
	end
	return c
end

-- Convert a one-based list to zero-based
function zb(tbl)
	ztbl = {}

	for k, v in pairs(tbl) do
		if type(k) ~= "number" then
			print("non-numeric key in table")
			os.exit(1)
		end

		if k == 0 then
			print("zero-key found in list")
			os.exit(1)
		end

		ztbl[k - 1] = v
	end

	return ztbl
end

function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function parse_number(str)
	str = trim(str)

	if str:sub(1, 1) == "$" then
		return tonumber(str:sub(2), 16)
	elseif str:sub(1, 2) == "0x" or str:sub(1, 2) == "0X" then
		return tonumber(str:sub(3), 16)
	else
		return tonumber(str)
	end
end

function find(lst, predicate)
	for i, v in ipairs(lst) do
		if predicate(v) then
			return v
		end
	end
	return nil
end

function split(str, sep)
	local result = {}
	sep = sep or "%s+"
	for part in str:gmatch("[^" .. sep .. "]+") do
		table.insert(result, part)
	end
	return result
end

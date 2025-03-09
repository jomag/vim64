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

function bit3(value)
	return bit.band(value, 8) ~= 0
end

function bit0(value)
	return bit.band(value, 1) ~= 0
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

	io.input(f)
	local data = io.read("*all")
	f:close()

	local bin = {}
	for i = 1, #data do
		bin[i] = string.byte(data, i)
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

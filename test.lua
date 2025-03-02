require "cpu"
require "mem"

local TestMachineMemoryMapper = {}
setmetatable(TestMachineMemoryMapper, { __index = MemoryMapper })

function TestMachineMemoryMapper:new(o)
	o = MemoryMapper:new(o or {})
	setmetatable(o, self)
	self.__index = self
	return o
end

function TestMachineMemoryMapper:load(path, adr)
	local bin = load_bin(path)
	if bin == nil then
		printf("Failed to load %s\n", path)
		return
	end

	for i, v in ipairs(bin) do
		self:set(adr + i - 1, v)
	end
end

local function run_test(cycles)
	local cpu = Cpu6502:new()
	local mem = TestMachineMemoryMapper:new()
	mem:load("6502_functional_test.bin", 0)

	cpu:reset_sequence(mem, 0x400)
	while cycles == nil or cpu.cycle < cycles do
		print(cpu:format_state() .. " " .. cpu:format_internals())
		cpu:step(mem)
	end
end

local function run_test_with_validation(rom_path, expect_path)
	local cmp_list = { "pc", "ir", "a", "x", "y", "adr", "rnw", "d", "p" }
	local expect_file = io.open(expect_path, "r")
	if not expect_file then
		fatal("Failed to open " .. expect_path)
		return
	end

	local function next_expected_state()
		local line = expect_file:read("*l")
		if line == nil then
			return nil, nil
		end
		local state = {}
		for k, v in string.gmatch(line, "(%w+):(%x+)") do
			k = string.lower(k)
			if k == "ab" then
				k = "adr"
			elseif k == "d" then
				k = "data"
			end
			state[k] = tonumber(v, 16)
		end

		-- Hack: skip every second half cycle
		if state.halfcyc ~= nil and state.halfcyc % 2 == 1 then
			return next_expected_state()
		end

		return state, line
	end

	local function format_bits(byte, sep)
		if sep == nil then
			sep = ""
		end
		local s = ""
		for i = 0, 7 do
			s = s .. (i > 0 and sep or "") .. ((byte & (1 << (7 - i)) == 0) and 0 or 1)
		end
		return s
	end

	local function compare_states(cpu, exp, exp_line)
		local res = true
		for _, cmp in ipairs(cmp_list) do
			local a = exp[cmp]
			local b
			if cmp == "rnw" then
				b = (cpu.read and 1) or 0
			elseif cmp == "p" then
				b = cpu:get_p()
			else
				b = cpu[cmp]
			end
			if a ~= b then
				printf("Found a difference in register '%s':\n", cmp)
				if cmp == "p" then
					print("                            N V 1 B D I Z C")
				end
				printf("  Expected: % 5d (0x%04x)  %s\n", a, a, format_bits(a, " "))
				printf("  Got:      % 5d (0x%04x)  %s\n", b, b, format_bits(b, " "))
				printf("  Raw expectation line:\n  %s\n", exp_line)
				res = false
			end
		end
		return res
	end

	local cpu = Cpu6502:new()
	local mem = TestMachineMemoryMapper:new()
	mem:load(rom_path, 0)

	cpu:reset_sequence(mem, 0x400)
	while cycles == nil or cpu.cycle < cycles do
		print(cpu:format_state() .. " " .. cpu:format_internals())
		local exp, exp_line = next_expected_state()
		if exp == nil then
			print("End of expected cycles. Success!")
			break
		end
		if not compare_states(cpu, exp, exp_line) then
			print("Test failed.")
			break
		end

		print("")
		cpu:step(mem)
	end
end


-- run_test(10)
run_test_with_validation(
	"6502_functional_test.bin",
	"6502_functional_test.perfect6502"
)

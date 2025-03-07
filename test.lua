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

local function run_test_until_address_reached(rom_path, target_adr)
	local cpu = Cpu6502:new()
	local mem = TestMachineMemoryMapper:new()
	mem:load(rom_path, 0)

	local prev_adr = -1
	local trap_count = 0
	local function detect_trap(cpu)
		if cpu.tcu == 0 then
			if cpu.pc == prev_adr then
				trap_count = trap_count + 1
				return trap_count > 1000
			else
				trap_count = 0
				prev_adr = cpu.pc
				return false
			end
		else
			return false
		end
	end

	cpu:reset_sequence(mem, 0x400)
	while cpu.pc ~= target_adr do
		if detect_trap(cpu) then
			printf("Trapped at 0x%04X\n", cpu.pc)
			break
		end

		cpu:step(mem)
		if cpu.cycle % 1000000 == 0 then
			printf("Cycle %d, PC: %04x\n", cpu.cycle, cpu.pc)
		end
	end
end

local function run_test_with_validation(rom_path, expect_path, cycles)
	local cmp_list = { "pc", "ir", "a", "x", "y", "adr", "rnw", "p", "sp", "data" }
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
		if state.halfcyc ~= nil and state.halfcyc % 2 == 0 then
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

	local function compare_states(cpu, mem, exp, exp_line)
		local res = true
		for _, cmp in ipairs(cmp_list) do
			local a = exp[cmp]
			local b
			if cmp == "rnw" then
				b = (cpu.read and 1) or 0
			elseif cmp == "p" then
				b = cpu:get_p()
			elseif cmp == "data" then
				if cpu.read then
					b = mem:get_wo_sideffects(cpu.adr)
				else
					b = cpu.data
				end
			else
				b = cpu[cmp]
			end
			if a ~= b then
				printf("Found a difference in register '%s':\n", cmp)
				if cmp == "p" then
					print("                            N V 1 B D I Z C")
				end
				printf("  Expected: % 5d (0x%04x)%s\n", a, a, cmp == "p" and "  " .. format_bits(a, " ") or "")
				printf("  Got:      % 5d (0x%04x)%s\n", b, b, cmp == "p" and "  " .. format_bits(b, " ") or "")
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
		if not compare_states(cpu, mem, exp, exp_line) then
			print("Test failed.")
			printf("%d/151 instructions implemented\n", get_key_count(Cpu6502.instructions))
			break
		end

		print("")
		cpu:step(mem)
	end
end

run_test_until_address_reached("6502_functional_test.bin", 0x3469)

if false then
	-- run_test(10)
	run_test_with_validation(
		"6502_functional_test.bin",
		"6502_functional_test.perfect6502"
	)
end

require "cpu"
require "bus"

local TestBus = {}
setmetatable(TestBus, { __index = Bus })

function TestBus:new(o)
	o = Bus:new(o or {})
	setmetatable(o, self)
	self.__index = self
	return o
end

function TestBus:load(path, adr)
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
	local bus = TestBus:new()
	bus:load("6502_functional_test.bin", 0)

	cpu:reset_sequence(bus, 0x400)
	while cycles == nil or cpu.cycle < cycles do
		-- print(cpu:format_state() .. " " .. cpu:format_internals())
		cpu:step(bus)
	end
end

local function run_test_until_address_reached(rom_path, target_adr)
	local cpu = Cpu6502:new()
	local bus = TestBus:new()
	bus:load(rom_path, 0)

	local prev_adr = -1
	local trap_count = 0
	local function detect_trap(cpu)
		if cpu.tcu == 1 then
			local adr = cpu.pc - 1
			if adr == prev_adr then
				trap_count = trap_count + 1
				if trap_count > 1000 then
					return adr
				end
			else
				trap_count = 0
				prev_adr = adr
				return false
			end
		end
		return false
	end

	cpu:reset_sequence(bus, 0x400)

	while cpu.pc ~= target_adr do
		local trapped = detect_trap(cpu)
		if trapped ~= false then
			printf("Trapped at 0x%04X\n", trapped)
			break
		end

		local data
		if cpu.read then
			data = bus:get(cpu.adr)
		else
			data = cpu.data
			bus:set(cpu.adr, data)
		end

		cpu:step(data)
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
			if k == "halfcyc" then
				state[k] = tonumber(v, 10)
			else
				state[k] = tonumber(v, 16)
			end
		end

		-- Hack: skip every second half cycle
		if state.halfcyc ~= nil and state.halfcyc % 2 == 0 then
			return next_expected_state()
		end

		return state, line
	end

	local function compare_states(cpu, bus, exp, exp_line)
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
					b = bus:get_wo_sideffects(cpu.adr)
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
	local bus = TestBus:new()
	bus:load(rom_path, 0)

	cpu:reset_sequence(bus, 0x400)
	while cycles == nil or cpu.cycle < cycles do
		local exp, exp_line = next_expected_state()
		if exp == nil then
			print("End of expected cycles. Success!")
			break
		end

		if exp.halfcyc > cpu.cycle * 2 + 1 then
			printf("Fast forwarding to cycle %d...\n", exp.halfcyc / 2)
			while exp.halfcyc > cpu.cycle * 2 + 1 do
				cpu:step(bus)
			end
		end

		print(tostring(cpu.cycle) .. ": " .. cpu:format_state() .. " " .. cpu:format_internals())

		if not compare_states(cpu, bus, exp, exp_line) then
			print("wtf?", cpu:get_p(), cpu.p.c, bit.bor(0, cpu.p.c and 1 or 0))
			print("Test failed.")
			printf("%d/151 instructions implemented\n", get_key_count(Cpu6502.instructions))
			break
		end

		print("")
		cpu:step(bus)
	end
end

if true then
	run_test_until_address_reached("simulations/6502_functional_test.bin", 0x1113477)
else
	run_test_with_validation(
		"simulations/6502_functional_test.bin",
		"simulations/decimal_tests.txt"
	-- "simulations/100M.txt"
	-- "simulations/6502_functional_test.perfect6502"
	)
end

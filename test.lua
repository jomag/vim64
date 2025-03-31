require "cpu"
require "dbg"

TestMachine = {}

function TestMachine:new(rom_path, rom_offset)
	local ram = {}
	for i = 0, 65536 do
		ram[i] = 0
	end

	local bin = load_bin(rom_path)
	if bin == nil then
		printf("Failed to load %s\n", path)
		os.exit(1)
	end

	rom_offset = rom_offset or 0
	for i, v in ipairs(bin) do
		ram[i + rom_offset] = v
	end

	local machine = {
		cpu = Cpu6502:new(),
		ram = ram,
	}

	setmetatable(machine, { __index = self })
	return machine
end

function TestMachine:inspect(adr)
	validate_u16(adr)
	return self.ram[adr]
end

function TestMachine:step()
	self.cpu:step()
	if self.cpu.read then
		self.cpu.data = self.ram[self.cpu.adr]
	else
		if self.cpu.adr == 0xBFFC then
			if bit_set(self.cpu.data, 0) then
				printf("Interrupt Request (0x%04X = %02X)\n", self.cpu.adr, self.cpu.data)
				self.cpu.int = true
			end
		end
		self.ram[self.cpu.adr] = self.cpu.data
	end
end

local function run_test(cycles)
	local m = TestMachine:new("6502_functional_test.bin")
	m.cpu:reset_sequence(0x400, 0xD8)
	while cycles == nil or m.cpu.cycle < cycles do
		-- print(m.cpu:format_state() .. " " .. m.cpu:format_internals())
		m:step()
	end
end

local function run_klaus_dormann_interrupt_test()
	local dbg = Debugger:new()
	local m = TestMachine:new("as64/6502_interrupt_test.bin", 10)
	m.cpu:reset_sequence(0x400, m:inspect(0x400))

	-- Start address of current instruction
	local instr_adr = 0

	-- How many times we've looped back to same instruction
	local trap_counter = 0

	dbg:break_at(0x465)

	while m.cpu.pc ~= target_adr do
		if m.cpu.tcu == 1 then
			-- Detect traps
			if m.cpu.adr == instr_adr then
				trap_counter = trap_counter + 1
				if trap_counter > 10 then
					printf("Trapped at 0x%04x\n", instr_adr)
					return
				end
			else
				instr_adr = m.cpu.adr
				trap_counter = 0
			end

			dbg:update(m.cpu)
			if dbg.stopped then
				dbg:prompt(m.cpu, m)
			end
		end

		m:step()

		if m.cpu.cycle % 10000 == 0 then
			printf("Cycle %d, PC: %04x, IR: %02x, INTH: %s\n",
				m.cpu.cycle, m.cpu.pc, m.cpu.ir,
				tostring(m.cpu.TMP_HACK_INT_TCU))
		end
	end
end

local function run_test_until_address_reached(rom_path, target_adr)
	local m = TestMachine:new(rom_path)

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

	m.cpu:reset_sequence(0x400, 0xD8)

	while m.cpu.pc ~= target_adr do
		local trapped = detect_trap(m.cpu)
		if trapped ~= false then
			printf("Trapped at 0x%04X\n", trapped)
			break
		end

		m:step()
		if m.cpu.cycle % 1000000 == 0 then
			printf("Cycle %d, PC: %04x\n", m.cpu.cycle, m.cpu.pc)
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

	local function compare_states(machine, exp, exp_line)
		local res = true
		for _, cmp in ipairs(cmp_list) do
			local a = exp[cmp]
			local b
			if cmp == "rnw" then
				b = (machine.cpu.read and 1) or 0
			elseif cmp == "p" then
				b = machine.cpu:get_p()
			elseif cmp == "data" then
				b = machine.cpu.data
			else
				b = machine.cpu[cmp]
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

	local machine = TestMachine:new(rom_path)
	if machine == nil then
		return
	end

	machine.cpu:reset_sequence(0x400, 0xD8)

	while cycles == nil or machine.cpu.cycle < cycles do
		local exp, exp_line = next_expected_state()
		if exp == nil then
			print("End of expected cycles. Success!")
			break
		end

		if exp.halfcyc > machine.cpu.cycle * 2 + 1 then
			printf("Fast forwarding to cycle %d...\n", exp.halfcyc / 2)
			while exp.halfcyc > machine.cpu.cycle * 2 + 1 do
				machine.cpu:step()
			end
		end

		-- print(tostring(machine.cpu.cycle) .. ": " .. machine.cpu:format_state() .. " " .. machine.cpu:format_internals())

		if not compare_states(machine, exp, exp_line) then
			print("Test failed.")
			break
		end

		-- print("")
		machine:step()
	end
end

run_klaus_dormann_interrupt_test()

if false then
	run_test_until_address_reached("6502_functional_test.bin", 0x1113477)
end

if false then
	run_test_with_validation(
		"6502_functional_test.bin",
		-- "simulations/decimal_tests.txt"
		"simulations/100M.txt"
	-- "simulations/6502_functional_test.perfect6502"
	)
end

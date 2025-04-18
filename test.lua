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
		ref_file = nil,
		ref_line = nil,
		target_adr = nil,
	}

	setmetatable(machine, { __index = self })
	return machine
end

function TestMachine:set_target_address(adr)
	self.target_adr = adr
end

function TestMachine:setup_reference(path)
	self.ref_file = io.open(path, "r")
	if not self.ref_file then
		fatal("Failed to open reference file: " .. path)
		return false
	end
	self.ref_line = 0
	return true
end

function TestMachine:get_next_reference_state()
	local line = self.ref_file:read("*l")
	self.ref_line = self.ref_line + 1

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
		return self:get_next_reference_state()
	end

	return state, line
end

function TestMachine:compare_reference_state(exp, exp_line)
	local cmp_list = { "pc", "ir", "a", "x", "y", "adr", "rnw", "p", "sp", "data" }
	local res = true
	for _, cmp in ipairs(cmp_list) do
		local a = exp[cmp]
		local b
		if cmp == "rnw" then
			b = (self.cpu.read and 1) or 0
		elseif cmp == "p" then
			b = self.cpu:get_p()
			-- b = bit.bor(b, 0x10)
		elseif cmp == "data" then
			b = self.cpu.data
		else
			b = self.cpu[cmp]
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

function TestMachine:inspect(adr)
	validate_u16(adr)
	return self.ram[adr]
end

function TestMachine:step()
	self.cpu:step()

	if self.next_irq ~= nil then
		self.cpu.irq = self.next_irq
		self.next_irq = nil
	end

	if self.next_nmi ~= nil then
		self.cpu.nmi = self.next_nmi
		self.next_nmi = nil
	end

	if self.cpu.read then
		self.cpu.data = self.ram[self.cpu.adr]
	else
		if self.cpu.adr == 0xBFFC then
			if bit_set(self.cpu.data, 0) then
				self.next_irq = true
			else
				self.next_irq = false
			end

			if bit_set(self.cpu.data, 1) then
				self.next_nmi = true
				-- self.cpu.nmi = true
			else
				self.next_nmi = false
				-- self.cpu.nmi = false
			end
		end
		self.ram[self.cpu.adr] = self.cpu.data
	end
end

function TestMachine:run(dbg)
	-- Remember address of previous operation to detect when trapped
	local prev_adr = 0

	-- How many times we've looped back to same instruction
	local trap_counter = 0

	while true do
		-- Check if we've reached the target address
		if self.target_adr ~= nil and self.cpu.pc == self.target_adr then
			print(dbg:format_rich(self.cpu, self))
			return true, "Target address reached"
		end

		-- Detect traps
		if prev_adr == self.cpu.op_adr then
			trap_counter = trap_counter + 1
			if trap_counter > 100 then
				printf("Trapped at 0x%04x\n", prev_adr)
				dbg:stop()
			end
		else
			prev_adr = self.cpu.op_adr
			trap_counter = 0
		end

		if self.ref_file then
			local exp = self:get_next_reference_state()
			if exp == nil then
				self.ref_file:close()
				self.ref_file = nil

				if self.target_adr == nil then
					return true, "End of reference input"
				end
			else
				if exp.halfcyc > self.cpu.cycle * 2 + 1 then
					printf("Fast forwarding to cycle %d...\n", exp.halfcyc / 2)
					while exp.halfcyc > self.cpu.cycle * 2 + 1 do
						self:step()
					end
				end

				if not self:compare_reference_state(exp, 0) then
					print("Breaking execution to investigte divergence")
					dbg:stop()
				end
			end
		end

		if dbg ~= nil then
			dbg:update(self.cpu, self)
			if dbg.stopped then
				dbg:prompt(self.cpu, self)
			end
		end

		self:step()

		-- if m.cpu.cycle % 10000 == 0 and false then
		-- 	printf("Cycle %d, PC: %04x, IR: %02x, INTH: %s\n",
		-- 		m.cpu.cycle, m.cpu.pc, m.cpu.ir,
		-- 		tostring(m.cpu.TMP_HACK_INT_TCU))
		-- end
	end
end

local function run_klaus_dormann_interrupt_test()
	local dbg = Debugger:new()
	local m = TestMachine:new("as64/6502_interrupt_test.bin", 10)
	m.cpu:reset_sequence(0x400, m:inspect(0x400))

	if not m:setup_reference("simulations/6502_interrupt_test.perfect6502") then
		return
	end

	m:set_target_address(0x6F5)

	dbg:break_at(0x400)
	dbg:break_at(0x6e1)
	-- dbg:break_at(0x42B)
	-- dbg:break_at(0x444)
	-- dbg:break_at(0x465)
	-- dbg:break_at(0x544)
	-- dbg:break_at(0x52C)
	-- dbg:break_at(0x5C7)
	-- dbg:break_at(0x07C2)
	-- dbg:break_at(0x077c)
	-- dbg:break_at(0x077d)
	-- dbg:break_at(0x07c3)
	-- dbg:break_at(0x07c4)
	return m:run(dbg)
end

local function run_test(rom_path, target_adr, ref_path)
	local dbg = Debugger:new()
	local m = TestMachine:new(rom_path)

	if ref_path then
		m:setup_reference(ref_path)
	end

	m.cpu:reset_sequence(0x400, m:inspect(0x400))

	if target_adr ~= nil then
		m:set_target_address(target_adr)
	end

	return m:run(dbg)
end

if true then
	local res, msg = run_klaus_dormann_interrupt_test()
	printf(" * Test result for Klaus Dormann interrupt test: %s %s\n", (res and 'Success!') or "Fail!", msg)
end

if false then
	local path = "6502_functional_test.bin"
	local res, msg = run_test(path, 0x3469)
	printf(" * Test result for %s: %s %s\n", path, (res and 'Success!') or "Fail!", msg)
end

if false then
	local path = "6502_functional_test.bin"
	local res, msg = run_test(
		path,
		nil,
		"simulations/6502_functional_test.perfect6502"
	-- "simulations/100M.txt"
	)
	printf(" * Test result for %s: %s %s\n", path, (res and 'Success!') or "Fail!", msg)
end

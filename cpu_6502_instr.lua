local function update_flags(cpu, val)
	if val == 0 then
		cpu.p.z = true
	else
		cpu.p.z = false
	end

	if val & 128 == 0 then
		cpu.p.n = false
	else
		cpu.p.n = true
	end
end

local function store_data_in_a(cpu)
	print("store_data_in_a")
	cpu.a = cpu.data
	update_flags(cpu, cpu.a)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function store_data_in_x(cpu)
	cpu.x = cpu.data
	update_flags(cpu, cpu.x)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function store_data_in_y(cpu)
	cpu.y = cpu.data
	update_flags(cpu, cpu.y)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function read_at_pc(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function store_at_pc_to_pd(cpu)
	cpu.pd = cpu.data
	cpu.adr = cpu.pc
	cpu.pc = cpu.pc + 1
end

local function read_at_pc_and_jump(cpu)
	print("JUMPING!")
	read_at_pc(cpu)
	cpu.pc = (cpu.data << 8) | cpu.pd
end

local function inc_pc(cpu)
	printf("Incrementing PC: %x -> %x\n", cpu.pc, cpu.pc + 1)
	cpu.pc = cpu.pc + 1
end

local function nop(cpu)
end

local function store_register_a_at_a16_x(cpu)
	cpu.adr = (cpu.data << 8) | cpu.pd
	cpu.adr = cpu.adr + cpu.x
	cpu.data = cpu.a
	cpu.wr = true
end

local function abort(_cpu)
	error("Will not continue!")
end

local function store_a_at_abs(cpu)
	-- FIXME: not sure what register to store low byte
	-- from previous cycle in... Hence 0x42...
	cpu.adr = (cpu.data << 8) | 0x42
	cpu.adr = 0x242
	cpu.data = cpu.a
	cpu.read = false
end

local function cycle1_absolute(cpu)
	print("CYCLE1_ABSOLUTE()")
	-- Cycle 1 for absolute addressing operations

	-- FIXME: consider what register/field to store in!
	cpu.LOW_BYTE = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function cycle2_absolute_sta(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = cpu.pc + 1
	cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.read = false
	cpu.data = cpu.a
end

local function cycle2_absolute_jmp(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.adr = cpu.pc
end

local function cycle2_absolute_load(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
end

local function cycle3_absolute_load(cpu)
	cpu.TEMPORARY_STORAGE_ABSOLUTE_LOAD = cpu.data
	-- cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
end

local function cycle0_absolute_load(cpu)
	cpu.a = cpu.TEMPORARY_STORAGE_ABSOLUTE_LOAD
	update_flags(cpu, cpu.a)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function cycle1_relative_branch(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.BRANCH_OPERAND = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function cycle2_relative_branch(cpu)
	-- FIXME: don't always branch!
	local branch = false

	if cpu.ir == 0xD0 then -- BNE
		if not cpu.p.z then
			branch = true
		end
	elseif cpu.ir == 0xF0 then -- BEQ
		if cpu.p.z then
			branch = true
		end
	else
		fatal("Unexpected IR in branch handler: 0x%02x", cpu.ir)
	end

	if branch then
		print("I WILL BRANCH")
	else
		print("I will NOT branch!!")
	end

	if branch then
		local pcl = cpu.pc
		pcl = (pcl + cpu.BRANCH_OPERAND) & 0xFF
		cpu.pc = (cpu.pc & 0xFF00) | pcl
	else
		cpu.pc = cpu.pc + 1
		print("WILL BE" .. tostring(cpu.data))
	end

	cpu.adr = cpu.pc
end

local function dec_x(cpu)
	cpu.x = (cpu.x - 1) & 255
	update_flags(cpu, cpu.x)
	inc_pc(cpu)
end

local function dec_y(cpu)
	cpu.y = (cpu.y - 1) & 255
	update_flags(cpu, cpu.y)
	inc_pc(cpu)
end

local function cycle1_cmp_immediate(cpu)
	cpu.TEMPORARY_FOR_CMP = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function cycle0_cmp_immediate(cpu)
	update_flags(cpu, (cpu.TEMPORARY_FOR_CMP - cpu.a) & 0xFF)
	cpu.p.c = cpu.a <= cpu.TEMPORARY_FOR_CMP
	inc_pc(cpu)
end


Cpu6502.instructions = {
	-- 0x00: BRK
	[0x00] = {
		op = "BRK",
		[1] = inc_pc,
		[0] = inc_pc,
	},

	-- 0x4C: JMP a16 (absolute)
	[0x4C] = {
		op = "JMP",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_jmp,
		[0] = inc_pc,
	},

	-- 0x78: SEI
	-- Set Interrupt Disable Status
	[0x78] = {
		op = "SEI",
		[0] = function(self)
			self.p.i = true
		end,
		[1] = nop,
	},

	-- 0x88: DEY (implied)
	-- Decrement Y
	[0x88] = {
		op = "DEY",
		[1] = nop,
		[0] = dec_y,
	},

	-- 0x8D: STA a16 (absolute)
	[0x8D] = {
		op = "STA",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_sta,
		[0] = nop,
	},

	-- 0x9A: TXS
	-- TODO: Missing implementation
	[0x9A] = {
		op = "TXS",
		[1] = nop,
		[0] = inc_pc,
	},

	-- 0xA0: LDY (immediate)
	[0xA0] = {
		op = "LDY",
		[1] = store_data_in_y,
		[0] = inc_pc,
	},

	-- 0xA2: LDX #d8
	-- Load byte at PC+1 into X
	[0xA2] = {
		op = "LDX",
		[1] = store_data_in_x,
		[0] = inc_pc,
	},

	-- 0xA9: LDA d8
	[0xA9] = {
		op = "LDA",
		[1] = store_data_in_a,
		[0] = inc_pc,
	},

	-- 0xAD: LDA (absolute)
	[0xAD] = {
		op = "LDA",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_load,
		[3] = cycle3_absolute_load,
		[0] = cycle0_absolute_load,
	},

	-- 0xC9: CMP (immediate)
	-- Compare memory with A
	[0xC9] = {
		op = "CMP",
		[1] = cycle1_cmp_immediate,
		[0] = cycle0_cmp_immediate,
	},

	-- 0xCA: DEX
	-- Decrement X
	[0xCA] = {
		op = "DEX",
		[1] = nop,
		[0] = dec_x,
	},


	-- 0xD0: BNE (relative)
	-- Branch if not equal (Z != 0)
	[0xD0] = {
		op = "BNE",
		[1] = cycle1_relative_branch,
		[2] = cycle2_relative_branch,
		[0] = inc_pc
	},


	-- 0xD8: CLD
	-- TODO: Missing implementation
	[0xD8] = {
		op = "CLD",
		[1] = nop,
		[0] = inc_pc,
	},

	-- 0xF0: BEQ
	-- Branch if equal (Z == 0)
	[0xF0] = {
		op = "BEQ",
		[1] = cycle1_relative_branch,
		[2] = cycle2_relative_branch,
		[0] = inc_pc
	},
}

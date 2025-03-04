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

local function prepare_next_op(cpu)
	cpu.ir = cpu.data
	cpu.tcu = 1
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end


-- BNE, BEQ, BVS, BVC,
local function branchop(name, condition_cb)
	return {
		op = name,

		[1] = function(cpu)
			cpu.BRANCH_OPERAND = byte_as_i8(cpu.data) -- FIXME
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 2
		end,

		[2] = function(cpu)
			if condition_cb(cpu) then
				cpu.FINAL_PC = cpu.pc + cpu.BRANCH_OPERAND

				cpu.pc = (cpu.pc & 0xFF00) | (cpu.FINAL_PC & 0xff)
				cpu.adr = cpu.pc

				if cpu.pc ~= cpu.FINAL_PC then
					cpu.tcu = 3
				else
					cpu.tcu = 4
				end
			else
				cpu.pc = cpu.pc + 1
				cpu.adr = cpu.pc
				cpu.ir = cpu.data
				cpu.tcu = 1
			end
		end,

		[3] = function(cpu)
			cpu.pc = cpu.FINAL_PC
			cpu.adr = cpu.pc
			cpu.tcu = 4
		end,

		[4] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.ir = cpu.data
			cpu.tcu = 1
		end,
		[5] = prepare_next_op,
	}
end

-- PHA, PHP
local function pushop(name, value_cb)
	return {
		op = name,
		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.data = value_cb(cpu)
			cpu.read = false
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.sp = cpu.sp - 1
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

-- PLA, PLP
local function pull_op(name, setter_cb)
	return {
		op = name,
		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			-- cpu.TEMPORARY_STACK_REG = cpu.data
			cpu.sp = inc_byte(cpu.sp)
			-- cpu.pc = cpu.pc + 1
			cpu.adr = 0x100 + cpu.sp
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			setter_cb(cpu, cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

local function nop_tcu0(cpu)
	cpu.tcu = 0
end

local function store_data_in_a(cpu)
	print("store_data_in_a")
	cpu.a = cpu.data
	update_flags(cpu, cpu.a)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 0
end

local function store_data_in_x(cpu)
	cpu.x = cpu.data
	update_flags(cpu, cpu.x)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 0
end

local function store_data_in_y(cpu)
	cpu.y = cpu.data
	update_flags(cpu, cpu.y)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 0
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
	cpu.tcu = 2
end

local function cycle2_absolute_sta(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = cpu.pc + 1
	cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.read = false
	cpu.data = cpu.a
	cpu.tcu = 3
end

local function cycle2_absolute_jmp(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.adr = cpu.pc
	cpu.tcu = 0
end

local function cycle2_absolute_load(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.tcu = 3
end

local function cycle3_absolute_load(cpu)
	cpu.TEMPORARY_STORAGE_ABSOLUTE_LOAD = cpu.data
	cpu.a = cpu.TEMPORARY_STORAGE_ABSOLUTE_LOAD
	update_flags(cpu, cpu.TEMPORARY_STORAGE_ABSOLUTE_LOAD)
	cpu.adr = cpu.pc
	cpu.tcu = 0
end

local function cycle0_absolute_load(cpu)
	prepare_next_op(cpu)
end

local function cycle1_relative_branch(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.BRANCH_OPERAND = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
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
		cpu.tcu = 0
	else
		cpu.pc = cpu.pc + 1
		print("WILL BE" .. tostring(cpu.data))
		cpu.tcu = 0
	end

	cpu.adr = cpu.pc
end

local function dec_x(cpu)
	cpu.x = (cpu.x - 1) & 255
	update_flags(cpu, cpu.x)
end

local function dec_y(cpu)
	cpu.y = (cpu.y - 1) & 255
	update_flags(cpu, cpu.y)
end

local function branch_relative_cycle1(cpu)
	cpu.BRANCH_OPERAND = byte_as_i8(cpu.data) -- FIXME
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function branch_relative_cycle2(cpu, do_branch)
	if do_branch then
		cpu.FINAL_PC = cpu.pc + cpu.BRANCH_OPERAND

		cpu.pc = (cpu.pc & 0xFF00) | (cpu.FINAL_PC & 0xff)
		cpu.adr = cpu.pc

		if cpu.pc ~= cpu.FINAL_PC then
			cpu.tcu = 3
		else
			cpu.tcu = 4
		end
	else
		cpu.pc = cpu.pc + 1
		cpu.adr = cpu.pc
		cpu.ir = cpu.data
		cpu.tcu = 1
	end
end

local function branch_relative_cycle3(cpu)
	cpu.pc = cpu.FINAL_PC
	cpu.adr = cpu.pc
	cpu.tcu = 4
end

local function branch_relative_cycle4(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.ir = cpu.data
	cpu.tcu = 1
end

Cpu6502.instructions = {
	-- 0x00: BRK
	[0x00] = {
		op = "BRK",
		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.pc = cpu.pc + 1
			cpu.read = false
			cpu.data = (cpu.pc >> 8) & 0xFF
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr - 1
			cpu.data = cpu.pc & 0xFF
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.adr - 1
			cpu.data = cpu:get_p() | 32
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.adr = 0xFFFE
			cpu.read = true
			cpu.p.i = true
			cpu.sp = cpu.sp - 3
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.BRK_PCL = cpu.data
			cpu.adr = 0xFFFF
			cpu.tcu = 6
		end,
		[6] = function(cpu)
			cpu.pc = (cpu.data << 8) | cpu.BRK_PCL
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x08: PHP
	-- Push status register onto stack
	[0x08] = pushop("PHP", function(cpu) return cpu:get_p() | 32 end),

	-- 0x10: BPL (relative)
	-- Branch on plus
	-- FIIXME: BEQ is the most accurate! Join implementation!
	[0x10] = branchop("BPL", function(cpu) return not cpu.p.n end),

	-- 0x18: CLC (implied)
	-- Clear carry flag
	[0x18] = {
		op = "CLC",
		[1] = function(cpu)
			cpu.p.c = false
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x20: JSR (absolute)
	-- Jump to subroutine
	[0x20] = {
		op = "JSR",
		[1] = function(cpu)
			cpu.JSR_SP_COPY = cpu.sp
			cpu.JSR_PCL = cpu.data
			cpu.adr = 0x100 + cpu.sp
			cpu.sp = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.read = false
			cpu.data = (cpu.pc >> 8) & 0xFF
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.read = false
			cpu.data = cpu.pc & 0xFF
			cpu.adr = 0x100 + cpu.JSR_SP_COPY - 1
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			-- cpu.pc = cpu.pc + 1
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.adr = cpu.JSR_PCL | (cpu.data << 8)
			cpu.pc = cpu.JSR_PCL | (cpu.data << 8)
			cpu.sp = cpu.JSR_SP_COPY - 2
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x28: PLP (implied)
	-- Pull status register from stack
	[0x28] = pull_op("PLP", function(cpu, val)
		cpu:set_p(val | 16)
	end),

	-- 0x30: BMI (relative)
	-- Branch on minus
	[0x30] = branchop("BMI", function(cpu) return cpu.p.n end),

	-- 0x48: PHA (implied)
	-- Push A to stack
	[0x48] = pushop("PHA", function(cpu) return cpu.a end),

	-- 0x49: EOR (immediate)
	-- Exclusive or (xor) memory and A
	[0x49] = {
		op = "EOR",
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.TEMPORARY_EOR_REG = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.a = cpu.a ~ cpu.TEMPORARY_EOR_REG
			update_flags(cpu, cpu.a)
			cpu.ir = cpu.data
			cpu.tcu = 1
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
		end
	},

	-- 0x4C: JMP a16 (absolute)
	[0x4C] = {
		op = "JMP",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_jmp,
		[0] = prepare_next_op,
	},

	-- 0x50: BVC
	[0x50] = branchop("BVC", function(cpu) return not cpu.p.o end),

	-- 0x60: RTS (implied)
	-- Return from subroutine
	[0x60] = {
		op = "RTS",
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = 0x100 | cpu.sp
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = 0x100 | cpu.sp + 1
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.RTS_PCL = cpu.data
			cpu.sp = cpu.sp + 2
			cpu.adr = 0x100 | cpu.sp
			cpu.p.ignored_bit = true
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.pc = (cpu.data << 8) | cpu.RTS_PCL
			cpu.adr = cpu.pc
			cpu.p.ignored_bit = false
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	},

	-- 0x68: PLA (implied)
	-- Pull A from stack
	[0x68] = pull_op("PLA", function(cpu, val)
		cpu.a = val
		update_flags(cpu, val)
		print("THE VAL", val)
		-- if val & 16 then
		-- cpu.p.b = true
		-- end
	end),

	-- 0x69: ADC (immediate)
	-- Add with carry
	[0x69] = {
		op = "ADC",
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.TEMPORARY_ADC_REG = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.a = (cpu.a + cpu.TEMPORARY_ADC_REG) & 255
			cpu.ir = cpu.data
			cpu.tcu = 1
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
		end
	},

	-- 0x6C: JMP (indirect)
	[0x6C] = {
		op = "JMP",
		[1] = function(cpu)
			cpu.JMP_INDIRECT_LOW_BYTE = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.JMP_INDIRECT_LOW_BYTE | (cpu.data << 8)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.JMP_INDIRECT_PCL = cpu.data
			cpu.adr = cpu.adr + 1
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.pc = cpu.JMP_INDIRECT_PCL | (cpu.data << 8)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x70: BVS
	[0x70] = branchop("BVS", function(cpu) return cpu.p.o end),

	-- 0x78: SEI
	-- Set Interrupt Disable Status
	[0x78] = {
		op = "SEI",
		[1] = nop_tcu0,
		[0] = function(self)
			self.p.i = true
		end,
	},

	-- 0x88: DEY (implied)
	-- Decrement Y
	[0x88] = {
		op = "DEY",
		[1] = nop_tcu0,
		[0] = function(cpu)
			dec_y(cpu)
			prepare_next_op(cpu)
		end
	},

	-- 0x8A: TXA (implied)
	-- Copy (transfer) X to A
	[0x8A] = {
		op = "TXA",
		[1] = function(cpu)
			cpu.a = cpu.x
			update_flags(cpu, cpu.a)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x8D: STA a16 (absolute)
	[0x8D] = {
		op = "STA",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_sta,
		[3] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x90: BCC (relative)
	-- Branch on Carry Clear
	[0x90] = branchop("BCC", function(cpu) return not cpu.p.c end),

	-- 0x98: TYA (implied)
	-- Copy A to Y
	[0x98] = {
		op = "TYA",
		[1] = function(cpu)
			cpu.a = cpu.y
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x9A: TXS
	-- TODO: Missing implementation
	[0x9A] = {
		op = "TXS",
		[1] = function(cpu)
			cpu.sp = cpu.x
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xA0: LDY (immediate)
	[0xA0] = {
		op = "LDY",
		[1] = store_data_in_y,
		[0] = prepare_next_op,
	},

	-- 0xA2: LDX #d8
	-- Load byte at PC+1 into X
	[0xA2] = {
		op = "LDX",
		[1] = store_data_in_x,
		[0] = prepare_next_op,
	},

	-- 0xA9: LDA d8
	[0xA9] = {
		op = "LDA",
		[1] = store_data_in_a,
		[0] = prepare_next_op,
	},

	-- 0xAA: TAX (implied)
	-- Copy (transfer) A to X
	[0xAA] = {
		op = "TAX",
		[1] = function(cpu)
			cpu.x = cpu.a
			update_flags(cpu, cpu.x)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xA8: TAY (implied)
	-- Copy (transfer) A to X
	[0xA8] = {
		op = "TAY",
		[1] = function(cpu)
			cpu.x = cpu.a
			update_flags(cpu, cpu.y)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xAD: LDA (absolute)
	[0xAD] = {
		op = "LDA",
		[1] = cycle1_absolute,
		[2] = cycle2_absolute_load,
		[3] = cycle3_absolute_load,
		[0] = cycle0_absolute_load,
	},

	-- 0xB0: BCS (relative)
	-- Branch on Carry Set
	[0xB0] = branchop("BCS", function(cpu) return cpu.p.c end),

	-- 0xBA: TSX (implied)
	-- Copy (transfer) stack pointer to X
	[0xBA] = {
		op = "TSX",
		[1] = function(cpu)
			cpu.x = cpu.sp
			update_flags(cpu, cpu.x)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xC0: CPY (immediate)
	[0xC0] = {
		op = "CPY",
		[1] = function(cpu)
			cpu.TEMPORARY_FOR_CMP = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			printf("COMPARING MEM AND Y: %x and %x\n", cpu.TEMPORARY_FOR_CMP, cpu.y)
			update_flags(cpu, (cpu.y - cpu.TEMPORARY_FOR_CMP) & 0xFF)
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.y
			prepare_next_op(cpu)
		end
	},

	-- 0xCD: CMP (absolute)
	-- Compare memory with A
	[0xCD] = {
		op = "CMP",
		[1] = cycle1_absolute,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.TEMPORARY_FOR_CMP = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			update_flags(cpu, (cpu.a - cpu.TEMPORARY_FOR_CMP) & 0xFF)
			prepare_next_op(cpu)
		end
	},

	-- 0xE0: CPX (immediate)
	-- Compare with X
	[0xE0] = {
		op = "CPX",
		[1] = function(cpu)
			cpu.TEMPORARY_FOR_CMP = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			printf("COMPARING MEM AND X: %x and %x\n", cpu.TEMPORARY_FOR_CMP, cpu.x)
			update_flags(cpu, (cpu.x - cpu.TEMPORARY_FOR_CMP) & 0xFF)
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.x
			prepare_next_op(cpu)
		end
	},



	-- 0xC9: CMP (immediate)
	-- Compare memory with A
	[0xC9] = {
		op = "CMP",
		[1] = function(cpu)
			cpu.TEMPORARY_FOR_CMP = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			update_flags(cpu, (cpu.a - cpu.TEMPORARY_FOR_CMP) & 0xFF)
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.a
			prepare_next_op(cpu)
		end
	},

	-- 0xC8: INX (implied)
	[0xC8] = {
		op = "INY",
		[1] = function(cpu)
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.y = inc_byte(cpu.y)
			update_flags(cpu, cpu.y)
			prepare_next_op(cpu)
		end
	},

	-- 0xCA: DEX
	-- Decrement X
	[0xCA] = {
		op = "DEX",
		[1] = nop_tcu0,
		[0] = function(cpu)
			dec_x(cpu)
			prepare_next_op(cpu)
		end
	},

	-- 0xD0: BNE (relative)
	-- Branch if not equal (Z != 0)
	[0xD0] = branchop("BNE", function(cpu) return not cpu.p.z end),

	-- 0xD8: CLD
	-- TODO: Missing implementation
	[0xD8] = {
		op = "CLD",
		[1] = function(cpu)
			cpu.p.d = false
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xE8: INX (implied)
	[0xE8] = {
		op = "INX",
		[1] = function(cpu)
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.x = inc_byte(cpu.x)
			update_flags(cpu, cpu.x)
			prepare_next_op(cpu)
		end
	},

	-- 0xEA: NOP (implied)
	-- No operation
	[0xEA] = {
		op = "NOP",
		[1] = function(cpu)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	},

	-- 0xF0: BEQ (relative)
	-- Branch if equal (Z == 0)
	[0xF0] = branchop("BEQ", function(cpu) return cpu.p.z end),
}

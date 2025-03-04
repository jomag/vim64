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

local function generic_abs_cycle1(cpu)
	cpu.LOW_BYTE = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function generic_abs_y_cycle1(cpu)
	cpu.ABS_Y_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function generic_abs_y_cycle2(cpu)
	cpu.pc = cpu.pc + 1
	cpu.ABS_X_PCH = cpu.data << 8
	cpu.adr = cpu.ABS_X_PCH + cpu.ABS_Y_PCL + cpu.y
	cpu.tcu = 3
end

local function generic_abs_x_cycle1(cpu)
	cpu.ABS_X_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function generic_abs_x_cycle2(cpu)
	cpu.pc = cpu.pc + 1
	cpu.ABS_X_PCH = cpu.data << 8
	cpu.adr = cpu.ABS_X_PCH + ((cpu.ABS_X_PCL + cpu.x) & 0xFF)
	cpu.tcu = 3
end

local function generic_zp_indexed_cycle1(cpu)
	cpu.adr = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.tcu = 2
end

local function read_zp_x_cycle2(cpu)
	cpu.adr = (cpu.adr + cpu.x) & 0xFF
	cpu.tcu = 3
end

local function generic_ind_y_cycle1(cpu)
	cpu.adr = cpu.data
	cpu.tcu = 2
	cpu.pc = cpu.pc + 1
end

local function generic_ind_y_cycle2(cpu)
	cpu.LOW = cpu.data
	cpu.adr = cpu.adr + 1
	cpu.tcu = 3
end

local function generic_ind_y_cycle3(cpu)
	cpu.FINAL_ADR = (cpu.data << 8) + cpu.LOW + cpu.y
	cpu.adr = (cpu.data << 8) + ((cpu.LOW + cpu.y) & 0xFF)
	if cpu.adr ~= cpu.FINAL_ADR then
		cpu.tcu = 4
	else
		cpu.tcu = 5
	end
end

local function generic_ind_y_cycle4(cpu)
	cpu.adr = cpu.FINAL_ADR
	cpu.tcu = 5
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
			cpu.sp = (cpu.sp - 1) & 0xFF
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


-- STA, STX, STY: zero-page
local function store_zp_op(name, value_cb)
	return {
		op = name,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.data
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

-- STA, STX, STY: zero-page, X-indexed
local function store_zp_x_op(name, value_cb)
	return {
		op = name,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.data
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = (cpu.adr + cpu.x) & 0xFF
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

-- STA, STX, STY: absolute
local function store_abs_op(name, value_cb)
	return {
		op = name,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

local function read_zp_cycle1(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.data
	cpu.tcu = 2
end

-- LDA, LDX, LDY: zero-page
local function load_zp_op(name, setter_cb)
	return {
		op = name,
		[1] = read_zp_cycle1,
		[2] = function(cpu)
			setter_cb(cpu, cpu:exec_load(cpu.data))
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,

	}
end

-- LDA, LDX, LDY: absolute
local function load_abs_op(name, setter_cb)
	return {
		op = name,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = (cpu.data << 8) | cpu.LOW_BYTE
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			setter_cb(cpu, cpu:exec_load(cpu.data))
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

local function cmp_zp_op(name, value_cb)
	return {
		op = "CMP",
		[1] = read_zp_cycle1,
		[2] = function(cpu)
			cpu.CMP_ZP_TMP = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu:exec_sub(value_cb(cpu), cpu.CMP_ZP_TMP)
			prepare_next_op(cpu)
		end,
	}
end

local function cmp_abs_op(name, value_cb)
	return {
		op = "CMP",
		[1] = generic_abs_cycle1,
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
			cpu:exec_sub(value_cb(cpu), cpu.TEMPORARY_FOR_CMP)
			prepare_next_op(cpu)
		end
	}
end


local function set_a(cpu, val) cpu.a = val end
local function set_x(cpu, val) cpu.x = val end
local function set_y(cpu, val) cpu.y = val end
local function get_a(cpu) return cpu.a end
local function get_x(cpu) return cpu.x end
local function get_y(cpu) return cpu.y end

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

local function cycle2_absolute_jmp(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = (cpu.data << 8) | cpu.LOW_BYTE
	cpu.adr = cpu.pc
	cpu.tcu = 0
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

	-- 0x09: ORA (immediate)
	-- Or A with memory
	[0x09] = {
		op = "ORA",
		[1] = function(cpu)
			-- FIXME: this is obviously not complete! But it passes first tests..
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

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

	-- 0x38: SEC (implied)
	-- Set Carry
	[0x38] = {
		op = "SEC",
		[1] = function(cpu)
			cpu.p.c = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x40: RTI (implied)
	-- Return from interrupt
	[0x40] = {
		op = "RTI",
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = 0x100 + cpu.sp
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr + 1
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.adr + 1
			cpu:set_p(cpu.data)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.RTI_PCL = cpu.data
			cpu.sp = cpu.sp + 3
			cpu.adr = cpu.adr + 1
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.pc = (cpu.data << 8) | cpu.RTI_PCL
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

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
		[1] = generic_abs_cycle1,
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

	-- 0x58: CLI (implied)
	-- Clear Interrupt Disable
	[0x58] = {
		op = "CLI",
		[1] = function(cpu)
			cpu.p.i = false
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
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
		[1] = function(cpu)
			cpu.p.i = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x84: STA (zero-page)
	[0x84] = store_zp_op("STY", get_y),

	-- 0x85: STA (zero-page)
	[0x85] = store_zp_op("STA", get_a),

	-- 0x86: STX (zero-page)
	[0x86] = store_zp_op("STX", get_x),

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

	-- 0x8C: STY (absolute)
	[0x8C] = store_abs_op("STY", get_y),

	-- 0x8D: STA (absolute)
	[0x8D] = store_abs_op("STA", get_a),

	-- 0x8E: STX (absolute)
	[0x8E] = store_abs_op("STX", get_x),

	-- 0x90: BCC (relative)
	-- Branch on Carry Clear
	[0x90] = branchop("BCC", function(cpu) return not cpu.p.c end),

	-- 0x91: STA (indirect, Y-indexed)
	[0x91] = {
		op = "STA",
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = generic_ind_y_cycle3,
		[4] = generic_ind_y_cycle4,
		[5] = function(cpu)
			cpu.read = false
			cpu.data = cpu.a
			cpu.tcu = 6
		end,
		[6] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x94: STY (zero-page)
	-- Store Y in zero-page
	[0x94] = store_zp_x_op("STY", get_y),

	-- 0x95: STA (zero-page, X-indexed)
	[0x95] = store_zp_x_op("STA", get_a),

	-- 0x96: STX (absolute, Y-indexed)
	-- Store X in memory
	[0x96] = {
		op = "STX",
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.read = false
			cpu.adr = (cpu.adr + cpu.y) & 0xFF
			cpu.data = cpu.x
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},


	-- 0x98: TYA (implied)
	-- Copy A to Y
	[0x98] = {
		op = "TYA",
		[1] = function(cpu)
			cpu.a = cpu.y
			update_flags(cpu, cpu.a)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0x99: STA (absolute, Y-indexed)
	-- Store A to memory
	[0x99] = {
		op = "STA",
		[1] = generic_abs_y_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_Y_PCH = cpu.data << 8
			cpu.adr = cpu.ABS_Y_PCH + ((cpu.ABS_Y_PCL + cpu.y) & 0xff)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.ABS_Y_PCH + cpu.ABS_Y_PCL + cpu.y
			cpu.read = false
			cpu.data = cpu.a
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
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

	-- 0x9D: STA (absolute, X-indexed)
	[0x9D] = {
		op = "STA",
		[1] = generic_abs_x_cycle1,
		[2] = generic_abs_x_cycle2,
		[3] = function(cpu)
			cpu.read = false
			cpu.adr = cpu.ABS_X_PCH + cpu.ABS_X_PCL + cpu.x
			cpu.data = cpu.a
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
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



	-- 0xA2: LDX (immediate)
	[0xA2] = {
		op = "LDX",
		[1] = store_data_in_x,
		[0] = prepare_next_op,
	},

	-- 0xA4: LDY (zero-page)
	[0xA4] = load_zp_op("LDY", set_y),

	-- 0xA5: LDA (zero-page)
	-- Load A from memory
	[0xA5] = load_zp_op("LDA", function(cpu, val) cpu.a = val end),

	-- 0xA6: LDX (zero-page)
	-- Load X from memory
	[0xA6] = load_zp_op("LDX", function(cpu, val) cpu.x = val end),

	-- 0xA8: TAY (implied)
	-- Copy (transfer) A to X
	[0xA8] = {
		op = "TAY",
		[1] = function(cpu)
			cpu.y = cpu.a
			update_flags(cpu, cpu.y)
			cpu.tcu = 0
		end,
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

	-- 0xAC: LDY (absolute)
	[0xAC] = load_abs_op("LDY", set_y),

	-- 0xAD: LDA (absolute)
	[0xAD] = load_abs_op("LDA", set_a),

	-- 0xAE: LDX (absolute)
	[0xAE] = load_abs_op("LDX", set_x),

	-- 0xB0: BCS (relative)
	-- Branch on Carry Set
	[0xB0] = branchop("BCS", function(cpu) return cpu.p.c end),

	-- 0xB1: LDA (indirect, Y-indexed)
	[0xB1] = {
		op = "LDA",
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = generic_ind_y_cycle3,
		[4] = generic_ind_y_cycle4,
		[5] = function(cpu)
			cpu.a = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xB4: LDY (zero-page, X-indexed)
	[0xB4] = {
		op = "LDY",
		[1] = generic_zp_indexed_cycle1,
		[2] = read_zp_x_cycle2,
		[3] = function(cpu)
			cpu.y = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xB5: LDA (zero-page, X-indexed)
	[0xB5] = {
		op = "LDA",
		[1] = generic_zp_indexed_cycle1,
		[2] = read_zp_x_cycle2,
		[3] = function(cpu)
			cpu.a = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xB6: LDX (zero-page, Y-indexed)
	[0xB6] = {
		op = "LDX",
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.adr = (cpu.adr + cpu.y) & 0xFF
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.x = cpu.data
			update_flags(cpu, cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xB8: CLV (implied)
	-- Clear overflow flag
	[0xB8] = {
		op = "CLV",
		[1] = function(cpu)
			cpu.p.o = false
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xB9: LDA (absolute, Y-indexed)
	-- Load A from memory
	[0xB9] = {
		op = "LDA",
		[1] = generic_abs_y_cycle1,
		[2] = generic_abs_y_cycle2,
		[3] = function(cpu)
			cpu.a = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

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

	-- 0xBC: LDY (absolute, X-indexed)
	[0xBC] = {
		op = "LDY",
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data << 8
			cpu.adr = cpu.ABS_X_PCH + ((cpu.ABS_X_PCL + cpu.x) & 0xff)
			if cpu.ABS_X_PCL + cpu.x > 0xFF then
				cpu.tcu = 3
			else
				cpu.tcu = 4
			end
		end,
		[3] = function(cpu)
			cpu.adr = cpu.ABS_X_PCH + cpu.ABS_X_PCL + cpu.x
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.y = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	-- 0xBD: LDA (absolute, X-indexed)
	-- Load A from memory
	[0xBD] = {
		op = "LDA",
		[1] = generic_abs_x_cycle1,
		[2] = generic_abs_x_cycle2,
		[3] = function(cpu)
			cpu.a = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	},

	-- 0xBE: LDX (absolute, Y-indexed)
	-- Load X from memory
	[0xBE] = {
		op = "LDX",
		[1] = generic_abs_y_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_Y_PCH = cpu.data << 8
			cpu.adr = cpu.ABS_Y_PCH + ((cpu.ABS_Y_PCL + cpu.y) & 0xff)
			if cpu.ABS_Y_PCL + cpu.y > 0xFF then
				cpu.tcu = 3
			else
				cpu.tcu = 4
			end
		end,
		[3] = function(cpu)
			cpu.adr = cpu.ABS_Y_PCH + cpu.ABS_Y_PCL + cpu.y
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.x = cpu:exec_load(cpu.data)
			cpu.adr = cpu.pc
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

	-- 0xC4: CMP (zero-page)
	[0xC4] = cmp_zp_op("CPY", get_y),

	-- 0xC5: CMP (zero-page)
	[0xC5] = cmp_zp_op("CMP", get_a),

	-- 0xCD: CMP (absolute)
	[0xCC] = cmp_abs_op("CPY", get_y),

	-- 0xCD: CMP (absolute)
	[0xCD] = cmp_abs_op("CMP", get_a),

	-- 0xD5: CMP (zero-page, X-indexed)
	[0xD5] = {
		op = "CMP",
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.adr = (cpu.adr + cpu.x) & 0xFF
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.CMP_TEMPORARY = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu:exec_sub(cpu.a, cpu.CMP_TEMPORARY)
			prepare_next_op(cpu)
		end
	},

	-- 0xD9: CMP (absolute, Y-indexed)
	-- Compare A with memory
	[0xD9] = {
		op = "CMP",
		[1] = generic_abs_y_cycle1,
		[2] = generic_abs_y_cycle2,
		[3] = function(cpu)
			cpu.CMP_DATA = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu:exec_sub(cpu.a, cpu.CMP_DATA)
			prepare_next_op(cpu)
		end
	},

	-- 0xDD: CMP (absolute, X-indexed)
	[0xDD] = {
		op = "CMP",
		[1] = generic_abs_x_cycle1,
		[2] = generic_abs_x_cycle2,
		[3] = function(cpu)
			cpu.CMP_DATA = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu:exec_sub(cpu.a, cpu.CMP_DATA)
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

	-- 0xD1: CMP (indirect, Y-indexed)
	[0xD1] = {
		op = "CMP",
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = generic_ind_y_cycle3,
		[4] = generic_ind_y_cycle4,
		[5] = function(cpu)
			cpu.TMPBUF = cpu.data
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu:exec_sub(cpu.a, cpu.TMPBUF)
			prepare_next_op(cpu)
		end
	},

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

	-- 0xE4: CPX (zero-page)
	[0xE4] = cmp_zp_op("CPX", get_x),

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

	-- 0xEC: CPX (absolute)
	[0xEC] = cmp_abs_op("CPX", get_x),

	-- 0xF0: BEQ (relative)
	-- Branch if equal (Z == 0)
	[0xF0] = branchop("BEQ", function(cpu) return cpu.p.z end),

	-- 0xF8: SED (implied)
	-- Set decimal
	[0xF8] = {
		op = "SED",
		[1] = function(cpu)
			cpu.p.d = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},
}

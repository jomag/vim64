local function update_flags(cpu, val)
	if val == 0 then
		cpu.p.z = true
	else
		cpu.p.z = false
	end

	if bit7(val) then
		cpu.p.n = true
	else
		cpu.p.n = false
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

local function load_abs_cycle2(cpu)
	cpu.adr = word(cpu.LOW_BYTE, cpu.data)
	cpu.pc = cpu.pc + 1
	cpu.tcu = 3
end

local function generic_abs_y_cycle1(cpu)
	cpu.ABS_Y_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function generic_abs_x_cycle1(cpu)
	cpu.ABS_X_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.tcu = 2
end

local function load_abs_y_cycle2(cpu)
	cpu.pc = cpu.pc + 1
	cpu.ABS_Y_PCH = cpu.data
	cpu.adr = word(mask_byte(cpu.ABS_Y_PCL + cpu.y), cpu.ABS_Y_PCH)
	if cpu.ABS_Y_PCL + cpu.y > 0xFF then
		cpu.tcu = 3
	else
		cpu.tcu = 4
	end
end

local function generic_zp_indexed_cycle1(cpu)
	cpu.adr = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.tcu = 2
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

local function generic_x_ind_cycle1(cpu)
	cpu.pc = cpu.pc + 1
	cpu.PCL = cpu.data
	cpu.adr = cpu.data
	cpu.tcu = 2
end

local function generic_x_ind_cycle2(cpu)
	cpu.adr = mask_byte(cpu.PCL + cpu.x)
	cpu.tcu = 3
end

local function generic_x_ind_cycle3(cpu)
	cpu.LOW = cpu.data
	cpu.adr = cpu.adr + 1
	cpu.tcu = 4
end

local function read_zp_cycle1(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.data
	cpu.tcu = 2
end

local function bitop_cyclen(cpu)
	cpu.TMP = cpu.data
	cpu.p.n = bit7(cpu.TMP)
	cpu.p.o = bit6(cpu.TMP)

	-- On the second cycle, zero flag is temporarily set if the
	-- operand is zero. This is only relevant for cycle accurate
	-- emulators that want to exactly copy the internal state
	-- of the 6502. On the third cycle, the zero flag get the
	-- expected value.
	cpu.p.z = cpu.TMP == 0

	cpu.adr = cpu.pc
	cpu.tcu = 0
end

local function bitop_cycle0(cpu)
	cpu.p.z = bit.band(cpu.TMP, cpu.a) == 0
	prepare_next_op(cpu)
end

---
--- Addressing modes
---

local function rd_immediate_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

local function rd_zp_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

-- Read-Modify-Write operation on zero-page
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 2.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_zp_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.RMW_ZP_TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.data = process_cb(cpu, cpu.RMW_ZP_TMP)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

local function rd_zp_x_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.x)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end

local function rd_zp_y_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.y)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end


-- Read-Modify-Write operation on zero-page, X-indexed
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 2.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_zp_x_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr + cpu.x
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.RMW_ZP_TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.data = process_cb(cpu, cpu.RMW_ZP_TMP)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

local function rd_abs_op(prep_cb, process_cb)
	return {
		len = 3,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.a = process_cb(cpu, cpu.TMP)
			prepare_next_op(cpu)
		end,
	}
end

local function wr_abs_op(value_cb)
	return {
		len = 3,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
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

-- X-indexed, indirect
local function rd_x_ind_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = generic_x_ind_cycle1,
		[2] = generic_x_ind_cycle2,
		[3] = generic_x_ind_cycle3,
		[4] = function(cpu)
			cpu.adr = word(cpu.LOW, cpu.data)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

local function wr_zp_ind_op(value_cb)
	return {
		len = 2,
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.read = false
			cpu.adr = mask_byte(cpu.adr + cpu.y)
			cpu.data = value_cb(cpu)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

local function wr_x_ind_op(value_cb)
	return {
		len = 2,
		[1] = generic_x_ind_cycle1,
		[2] = generic_x_ind_cycle2,
		[3] = generic_x_ind_cycle3,
		[4] = function(cpu)
			cpu.read = false
			cpu.adr = word(cpu.LOW, cpu.data)
			cpu.data = value_cb(cpu)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

-- inderect, Y-indexed
local function rd_ind_y_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = function(cpu)
			cpu.FINAL_ADR = bit.lshift(cpu.data, 8) + cpu.LOW + cpu.y
			cpu.adr = word(mask_byte(cpu.LOW + cpu.y), cpu.data)
			if cpu.adr ~= cpu.FINAL_ADR then
				cpu.tcu = 4
			else
				cpu.tcu = 5
			end
		end,
		[4] = function(cpu)
			cpu.adr = cpu.FINAL_ADR
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

local function wr_ind_y_op(value_cb)
	return {
		len = 2,
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = function(cpu)
			cpu.FINAL_ADR = bit.lshift(cpu.data, 8) + cpu.LOW + cpu.y
			cpu.adr = word(mask_byte(cpu.LOW + cpu.y), cpu.data)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.adr = cpu.FINAL_ADR
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

local function rd_abs_x_op(prep_cb, process_cb)
	return {
		len = 3,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.x), cpu.ABS_X_PCH)
			if cpu.ABS_X_PCL + cpu.x > 0xFF then
				cpu.tcu = 3
			else
				cpu.tcu = 4
			end
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.x
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end

local function wr_abs_x_op(value_cb)
	return {
		len = 3,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.x), cpu.ABS_X_PCH)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.x
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

local function wr_abs_y_op(value_cb)
	return {
		len = 3,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.y), cpu.ABS_X_PCH)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.y
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

local function rd_abs_y_op(prep_cb, process_cb)
	return {
		len = 3,
		[1] = generic_abs_y_cycle1,
		[2] = load_abs_y_cycle2,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_Y_PCH, 8) + cpu.ABS_Y_PCL + cpu.y
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end

-- Read-Modify-Write operation with absolute addressing
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_abs_op(prep_cb, process_cb)
	return {
		len = 3,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.data = process_cb(cpu, cpu.data)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end

-- Read-Modify-Write operation with absolute, X-indexed addresing
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_abs_x_op(prep_cb, process_cb)
	return {
		len = 3,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.HIGH_BYTE = cpu.data
			cpu.adr = word(mask_byte(cpu.LOW_BYTE + cpu.x), cpu.HIGH_BYTE)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.HIGH_BYTE, 8) + cpu.LOW_BYTE + cpu.x
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.data = process_cb(cpu, cpu.data)
			cpu.tcu = 6
		end,
		[6] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	}
end


-- Read-Modify-Write operation performed on accumulator.
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_impl_op(prep_cb, process_cb)
	return {
		len = 1,
		[1] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.a)
			end
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.a = process_cb(cpu, cpu.a)
			prepare_next_op(cpu)
		end
	}
end

-- Read-Modify-Write operation performed on value after op byte.
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_immediate_op(prep_cb, process_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			cpu.a = process_cb(cpu, cpu.TMP)
			prepare_next_op(cpu)
		end
	}
end

local function wr_zp_x_op(value_cb)
	return {
		len = 2,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.data
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.x)
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

local function wr_zp_op(value_cb)
	return {
		len = 2,
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


---
--- Operations
---

-- BNE, BEQ, BVS, BVC,
local function branchop(mnemonic, condition_cb)
	return {
		mnemonic = mnemonic,
		len = 2,

		[1] = function(cpu)
			cpu.BRANCH_OPERAND = byte_as_i8(cpu.data) -- FIXME
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 2
		end,

		[2] = function(cpu)
			if condition_cb(cpu) then
				cpu.FINAL_PC = cpu.pc + cpu.BRANCH_OPERAND

				cpu.pc = bit.bor(bit.band(cpu.pc, 0xFF00), bit.band(cpu.FINAL_PC, 0xff))
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
local function pushop(mnemonic, value_cb)
	return {
		mnemonic = mnemonic,
		len = 1,

		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.data = value_cb(cpu)
			cpu.read = false
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.sp = mask_byte(cpu.sp - 1)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	}
end

-- PLA, PLP
local function pull_op(mnemonic, setter_cb)
	return {
		mnemonic = mnemonic,
		len = 1,

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

-- LDA, LDX, LDY: zero-page
local function load_zp_op(name, setter_cb)
	return {
		adrmode = ADRMODE_ZPG,
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
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
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
		op = name,
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
		op = name,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
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

local function asl_op(addr_fun)
	return addr_fun(
		"ASL",
		nil,
		function(cpu, val)
			val = bit.lshift(val, 1)
			cpu.p.c = val > 0xFF
			return cpu:exec_load(mask_byte(val))
		end
	)
end

local function lsr_op(addr_fun)
	return addr_fun(
		"LSR",
		function(cpu, val)
			cpu.p.c = bit0(val)
		end,
		function(cpu, val)
			return cpu:exec_load(bit.rshift(val, 1))
		end
	)
end

local function rol_op(addr_fun)
	return addr_fun(
		"ROL",
		nil,
		function(cpu, val)
			local c = bit7(val)
			val = mask_byte(bit.lshift(val, 1))
			if cpu.p.c then
				val = bit.bor(val, 1)
			end
			cpu.p.c = c
			cpu:exec_load(val)
			return val
		end
	)
end

local function ror_op(addr_fun)
	return addr_fun(
		"ROR",
		function(cpu, val)
			cpu.TMP_C = cpu.p.c
			cpu.p.c = bit0(val)
		end,
		function(cpu, val)
			val = bit.rshift(val, 1)
			if cpu.TMP_C then
				val = bit.bor(val, 128)
			end
			cpu:exec_load(val)
			return val
		end
	)
end

local function inc_op(addr_fun)
	return addr_fun(
		"INC",
		nil,
		function(cpu, val)
			return cpu:exec_load(mask_byte(val + 1))
		end
	)
end

local function dec_op(addr_fun)
	return addr_fun(
		"DEC",
		nil,
		function(cpu, val)
			return cpu:exec_load(mask_byte(val - 1))
		end
	)
end

local function and_op(addr_fun)
	return addr_fun(
		"AND",
		function(cpu, val)
			cpu.p.n = bit7(val)
			cpu.p.z = val == 0
		end,
		function(cpu, val)
			return cpu:exec_load(bit.band(cpu.a, val))
		end
	)
end

local function ora_op(addr_fun)
	return merge(
		{
			mnemonic = "ORA"
		},
		addr_fun(
			nil,
			function(cpu, val)
				return cpu:exec_load(bit.bor(cpu.a, val))
			end
		)
	)
end

local function eor_op(addr_fun)
	return addr_fun(
		"EOR",
		nil,
		function(cpu, val)
			return cpu:exec_load(bit.bxor(cpu.a, val))
		end
	)
end

local function lda_op(addr_fun)
	return addr_fun("LDA", function(cpu, val)
		cpu.a = cpu:exec_load(val)
	end, nil
	)
end

local function ldy_op(addr_fun)
	return addr_fun("LDY", function(cpu, val)
		cpu.y = cpu:exec_load(val)
	end, nil
	)
end

local function ldx_op(addr_fun)
	return addr_fun("LDX", function(cpu, val)
		cpu.x = cpu:exec_load(val)
	end, nil
	)
end

local function sta_op(addr_fun)
	return addr_fun("STA", function(cpu)
		return cpu.a
	end)
end

local function stx_op(addr_fun)
	return addr_fun("STX", function(cpu)
		return cpu.x
	end)
end

local function sty_op(addr_fun)
	return addr_fun("STY", function(cpu)
		return cpu.y
	end)
end

local function cmp_op(addr_fun)
	return addr_fun("CMP", nil, function(cpu, val)
		cpu:exec_sub(cpu.a, val)
		return cpu.a
	end)
end

local function adc_op(addr_fun)
	return addr_fun(
		"ADC",
		nil,
		function(cpu, val)
			local carry_in = cpu.p.c and 1 or 0

			local sum = cpu.a + val
			if cpu.p.c then
				sum = sum + 1
			end

			if sum > 0xFF then
				cpu.p.c = true
				sum = mask_byte(sum)
			else
				cpu.p.c = false
			end

			-- Z-flag is based on the binary computation
			-- in both decimal and non-decimal mode
			cpu.p.z = sum == 0

			if not cpu.p.d then
				cpu.p.n = bit7(sum)
				cpu.p.o = bit.band(
					bit.band(
						bit.bnot(bit.bxor(cpu.a, val)),
						bit.bxor(cpu.a, sum)),
					0x80) ~= 0
				return sum
			else
				local acc_lo = bit.band(cpu.a, 0xF)
				local acc_hi = bit.band(bit.rshift(cpu.a, 4), 0xF)

				local val_lo = bit.band(val, 0xF)
				local val_hi = bit.band(bit.rshift(val, 4), 0xF)

				local lo = acc_lo + val_lo + carry_in
				if lo > 9 then
					lo = lo + 6
				end

				local nibble_carry = 0
				if lo > 0xF then
					nibble_carry = 1
					lo = bit.band(lo, 0xF)
				end

				local hi = acc_hi + val_hi + nibble_carry

				-- N and V should be computed after lo nible has been adjusted,
				-- and before hi nible is adjusted.
				-- Details:
				-- https://forums.atariage.com/topic/163876-flags-on-decimal-mode-on-the-nmos-6502
				cpu.p.n = bit3(hi)
				local tmp_sum = bit.band(bit.bor(lo, bit.lshift(hi, 4)), 0xFF)
				cpu.p.o = bit.band(
					bit.band(
						bit.bnot(bit.bxor(cpu.a, val)),
						bit.bxor(cpu.a, tmp_sum)),
					0x80) ~= 0

				if hi > 9 then
					hi = hi + 6
				end

				local final_carry = hi > 0xF
				hi = bit.band(hi, 0xF)

				local result = bit.bor(lo, bit.lshift(hi, 4))

				cpu.p.c = final_carry

				return result
			end
		end
	)
end

local function sbc_op(addr_fun)
	return addr_fun(
		"SBC",
		nil,
		function(cpu, val)
			local carry_in = cpu.p.c and 0 or 1
			local nval = mask_byte(bit.bnot(val))

			local sum = cpu.a + nval + (cpu.p.c and 1 or 0)

			if sum > 0xFF then
				cpu.p.c = true
				sum = mask_byte(sum)
			else
				cpu.p.c = false
			end

			cpu.p.z = sum == 0

			if not cpu.p.d then
				cpu.p.n = bit7(sum)
				cpu.p.o = bit.band(
					bit.band(
						bit.bnot(bit.bxor(cpu.a, nval)),
						bit.bxor(cpu.a, sum)),
					0x80) ~= 0
				return sum
			else
				local acc_lo = bit.band(cpu.a, 0xF)
				local acc_hi = bit.band(bit.rshift(cpu.a, 4), 0xF)

				local val_lo = bit.band(val, 0xF)
				local val_hi = bit.band(bit.rshift(val, 4), 0xF)

				local lo = acc_lo - val_lo - carry_in
				local nibble_carry = 0
				if lo < 0 then
					lo = lo + 10
					nibble_carry = 1
				end

				local hi = acc_hi - val_hi - nibble_carry

				cpu.p.n = bit3(hi)
				local tmp_sum = bit.band(bit.bor(lo, bit.lshift(hi, 4)), 0xFF)
				cpu.p.o = bit.band(
					bit.band(
						bit.bnot(bit.bxor(cpu.a, nval)),
						bit.bxor(cpu.a, tmp_sum)),
					0x80) ~= 0

				local final_carry = true
				if hi < 0 then
					hi = hi + 10
					final_carry = false
				end

				hi = bit.band(hi, 0xF)

				local result = bit.bor(lo, bit.lshift(hi, 4))
				cpu.p.c = final_carry

				return result
			end
		end
	)
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

local function cycle2_absolute_jmp(cpu)
	-- FIXME: consider what register/field to store in!
	cpu.pc = word(cpu.LOW_BYTE, cpu.data)
	cpu.adr = cpu.pc
	cpu.tcu = 0
end


local function dec_x(cpu)
	cpu.x = mask_byte(cpu.x - 1)
	update_flags(cpu, cpu.x)
end

local function dec_y(cpu)
	cpu.y = mask_byte(cpu.y - 1)
	update_flags(cpu, cpu.y)
end

local interrupt_sequence = {
	[1] = function(cpu)
		print("INTSEQ 1")
		cpu.adr = 0x100 + cpu.sp
		cpu.sp = bit.band(cpu.sp - 1, 0xFF)
		cpu.data = upper_byte(cpu.pc)
		cpu.read = false
		cpu.tcu = 2
	end,
	[2] = function(cpu)
		print("INTSEQ 2")
		cpu.adr = 0x100 + cpu.sp
		cpu.sp = bit.band(cpu.sp - 1, 0xFF)
		cpu.data = bit.band(cpu.pc, 0xFF)
		cpu.read = false
		cpu.tcu = 3
	end,
	[3] = function(cpu)
		print("INTSEQ 3")
		cpu.adr = 0x100 + cpu.sp
		cpu.sp = bit.band(cpu.sp - 1, 0xFF)
		printf("PUSHING TO STACK: %02x\n", cpu:get_p())
		cpu.data = cpu:get_p()
		cpu.read = false
		cpu.tcu = 4
	end,
	[4] = function(cpu)
		print("INTSEQ 4")
		cpu.adr = 0xFFFE
		cpu.read = true
		cpu.tcu = 5
	end,
	[5] = function(cpu)
		print("INTSEQ 5")

		cpu.LOW_BYTE = cpu.data
		cpu.adr = 0xFFFF
		cpu.tcu = 6
	end,
	[6] = function(cpu)
		print("INTSEQ 6")
		cpu.pc = word(cpu.LOW_BYTE, cpu.data)
		cpu.adr = cpu.pc
		cpu.tcu = 0
	end,
	[0] = function(cpu)
		print("INTSEQ 0")
		cpu.TMP_HACK_INT_TCU = nil
		prepare_next_op(cpu)
	end
}

ADRMODE_ABS_X = "abs,X"
ADRMODE_ABS_Y = "abs,Y"
ADRMODE_IMPL = "impl"
ADRMODE_ZPG_X = "zpg,X"
ADRMODE_ZPG_Y = "zpg,Y"
ADRMODE_IND_Y = "ind,Y"
ADRMODE_REL = "rel"
ADRMODE_IND = "ind"
ADRMODE_IMMEDIATE = "#"
ADRMODE_ACC = "A"
ADRMODE_ZPG = "zpg"
ADRMODE_X_IND = "X,ind"
ADRMODE_ABS = "abs"

local adrmode_meta = {
	[ADRMODE_ABS_X] = { rd = rd_abs_x_op, wr = wr_abs_x_op },
	[ADRMODE_ABS_Y] = { rd = rd_abs_y_op, wr = wr_abs_y_op },
	[ADRMODE_IMPL] = { rd = nil, wr = nil },
	[ADRMODE_ZPG_X] = { rd = rd_zp_x_op, wr = wr_zp_x_op },
	[ADRMODE_ZPG_Y] = { rd = rd_zp_y_op, wr = nil },
	[ADRMODE_IND_Y] = { rd = rd_ind_y_op, wr = wr_ind_y_op },
	[ADRMODE_REL] = { rd = nil, wr = nil },
	[ADRMODE_IND] = { rd = nil, wr = nil },
	[ADRMODE_IMMEDIATE] = { rd = nil, wr = nil },
	[ADRMODE_ACC] = { rd = nil, wr = nil },
	[ADRMODE_ZPG] = { rd = rd_zp_op, wr = nil },
	[ADRMODE_X_IND] = { rd = rd_x_ind_op, wr = wr_x_ind_op },
	[ADRMODE_ABS] = { rd = rd_abs_op, wr = nil }
}

OP_ASL = "ASL"
OP_BRK = "BRK"
OP_ORA = "ORA"
OP_AND = "AND"
OP_EOR = "EOR"
OP_ADC = "ADC"
OP_LDA = "LDA"
OP_CMP = "CMP"
OP_BRK = "BRK"
OP_JMP = "JMP"
OP_JSR = "JSR"
OP_RTI = "RTI"
OP_NOP = "NOP"
OP_STA = "STA"
OP_SBC = "SBC"
OP_RTS = "RTS"
OP_CPY = "CPY"
OP_CPX = "CPX"
OP_LDY = "LDY"
OP_BIT = "BIT"
OP_BMI = "BMI"
OP_SEC = "SEC"
OP_CLI = "CLI"
OP_BVC = "BVC"
OP_PHA = "PHA"
OP_PLP = "PLP"
OP_PHP = "PHP"
OP_CLC = "CLC"
OP_SED = "SED"
OP_BEQ = "BEQ"
OP_BCS = "BCS"
OP_CLD = "CLD"
OP_BNE = "BNE"
OP_STY = "STY"
OP_SEI = "SEI"
OP_TYA = "TYA"
OP_CLV = "CLV"
OP_BVS = "BVS"
OP_BPL = "BPL"
OP_PLA = "PLA"
OP_DEY = "DEY"
OP_TAY = "TAY"
OP_INY = "INY"
OP_INX = "INX"
OP_BCC = "BCC"

-- Illegal opcodes
OPX_JAM = "JAM"
OPX_NOP = "NOP"
OPX_SHY = "SHY"

Cpu6502.instructions = {
	-- 0x00: BRK
	[0x00] = {
		op = "BRK",
		[1] = function(cpu)
			print("BRK instruction reached!")
			cpu.adr = 0x100 + cpu.sp
			cpu.pc = cpu.pc + 1
			cpu.read = false
			cpu.data = upper_byte(cpu.pc)
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr - 1
			cpu.data = mask_byte(cpu.pc)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.adr - 1
			cpu.data = bit.bor(cpu:get_p(), 32)
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.adr = 0xFFFE
			cpu.read = true
			cpu.p.i = true
			cpu.sp = mask_byte(cpu.sp - 3)
			cpu.tcu = 5
		end,
		[5] = function(cpu)
			cpu.BRK_PCL = cpu.data
			cpu.adr = 0xFFFF
			cpu.tcu = 6
		end,
		[6] = function(cpu)
			cpu.pc = word(cpu.BRK_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0x01] = ora_op(rd_x_ind_op),
	[0x05] = ora_op(rd_zp_op),
	[0x06] = asl_op(rmw_zp_op),
	[0x08] = pushop("PHP", function(cpu) return bit.bor(cpu:get_p(), 32) end),
	[0x09] = ora_op(rmw_immediate_op),
	[0x0A] = asl_op(rmw_impl_op),
	[0x0D] = ora_op(rd_abs_op),
	[0x0E] = asl_op(rmw_abs_op),

	[0x10] = branchop("BPL", function(cpu) return not cpu.p.n end),
	[0x11] = ora_op(rd_ind_y_op),
	[0x15] = ora_op(rd_zp_x_op),
	[0x16] = asl_op(rmw_zp_x_op),

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

	[0x19] = ora_op(rd_abs_y_op),
	[0x1D] = ora_op(rd_abs_x_op),
	[0x1E] = asl_op(rmw_abs_x_op),

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
			cpu.data = upper_byte(cpu.pc)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.read = false
			cpu.data = mask_byte(cpu.pc)
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
			cpu.adr = word(cpu.JSR_PCL, cpu.data)
			cpu.pc = cpu.adr
			cpu.sp = mask_byte(cpu.JSR_SP_COPY - 2)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0x21] = and_op(rd_x_ind_op),

	-- 0x24: BIT (zero-page)
	[0x24] = {
		op = "BIT",
		[1] = read_zp_cycle1,
		[2] = bitop_cyclen,
		[0] = bitop_cycle0,
	},

	[0x25] = and_op(rd_zp_op),
	[0x26] = rol_op(rmw_zp_op),

	-- 0x28: PLP (implied)
	-- Pull status register from stack
	[0x28] = pull_op("PLP", function(cpu, val)
		cpu:set_p(bit.bor(val, 16))
	end),

	[0x29] = and_op(rmw_immediate_op),

	-- 0x2A: ROL (implied)
	[0x2A] = rol_op(rmw_impl_op),

	-- 0x2C: BIT (absolute)
	[0x2C] = {
		op = "BIT",
		[1] = generic_abs_cycle1,
		[2] = load_abs_cycle2,
		[3] = bitop_cyclen,
		[0] = bitop_cycle0,
	},

	[0x2D] = and_op(rd_abs_op),
	[0x2E] = rol_op(rmw_abs_op),

	[0x30] = branchop("BMI", function(cpu) return cpu.p.n end),
	[0x31] = and_op(rd_ind_y_op),
	[0x35] = and_op(rd_zp_x_op),
	[0x36] = rol_op(rmw_zp_x_op),

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

	[0x39] = and_op(rd_abs_y_op),
	[0x3D] = and_op(rd_abs_x_op),
	[0x3E] = rol_op(rmw_abs_x_op),

	-- 0x40: RTI (implied)
	-- Return from interrupt
	[0x40] = {
		op = "RTI",
		[1] = function(cpu)
			print("\n\nR T I ! ! !\n\n")
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
			cpu.pc = word(cpu.RTI_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0x41] = eor_op(rd_x_ind_op),
	[0x45] = eor_op(rd_zp_op),
	[0x46] = lsr_op(rmw_zp_op),

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
			cpu.a = bit.bxor(cpu.a, cpu.TEMPORARY_EOR_REG)
			update_flags(cpu, cpu.a)
			cpu.ir = cpu.data
			cpu.tcu = 1
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
		end
	},

	-- 0x4A: LSR (implied)
	[0x4A] = lsr_op(rmw_impl_op),

	-- 0x4C: JMP a16 (absolute)
	[0x4C] = {
		op = "JMP",
		[1] = generic_abs_cycle1,
		[2] = cycle2_absolute_jmp,
		[0] = prepare_next_op,
	},

	[0x4D] = eor_op(rd_abs_op),
	[0x4E] = lsr_op(rmw_abs_op),

	[0x50] = branchop("BVC", function(cpu) return not cpu.p.o end),
	[0x51] = eor_op(rd_ind_y_op),
	[0x55] = eor_op(rd_zp_x_op),
	[0x56] = lsr_op(rmw_zp_x_op),

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

	[0x59] = eor_op(rd_abs_y_op),
	[0x5D] = eor_op(rd_abs_x_op),
	[0x5E] = lsr_op(rmw_abs_x_op),

	-- 0x60: RTS (implied)
	-- Return from subroutine
	[0x60] = {
		op = "RTS",
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = bit.bor(0x100, cpu.sp)
			cpu.tcu = 2
		end,
		[2] = function(cpu)
			cpu.adr = bit.bor(0x100, cpu.sp + 1)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.RTS_PCL = cpu.data
			cpu.sp = cpu.sp + 2
			cpu.adr = bit.bor(0x100, cpu.sp)
			cpu.p.ignored_bit = true
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.pc = word(cpu.RTS_PCL, cpu.data)
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

	[0x61] = adc_op(rd_x_ind_op),
	[0x65] = adc_op(rd_zp_op),
	[0x66] = ror_op(rmw_zp_op),

	-- 0x68: PLA (implied)
	-- Pull A from stack
	[0x68] = pull_op("PLA", function(cpu, val)
		cpu.a = val
		update_flags(cpu, val)
		-- if val & 16 then
		-- cpu.p.b = true
		-- end
	end),

	[0x69] = adc_op(rmw_immediate_op),
	[0x6A] = ror_op(rmw_impl_op),

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
			cpu.adr = word(cpu.JMP_INDIRECT_LOW_BYTE, cpu.data)
			cpu.tcu = 3
		end,
		[3] = function(cpu)
			cpu.JMP_INDIRECT_PCL = cpu.data
			cpu.adr = cpu.adr + 1
			cpu.tcu = 4
		end,
		[4] = function(cpu)
			cpu.pc = word(cpu.JMP_INDIRECT_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0x6D] = adc_op(rd_abs_op),
	[0x6E] = ror_op(rmw_abs_op),

	[0x70] = branchop("BVS", function(cpu) return cpu.p.o end),
	[0x71] = adc_op(rd_ind_y_op),
	[0x75] = adc_op(rd_zp_x_op),
	[0x76] = ror_op(rmw_zp_x_op),

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

	[0x79] = adc_op(rd_abs_y_op),
	[0x7D] = adc_op(rd_abs_x_op),
	[0x7E] = ror_op(rmw_abs_x_op),

	[0x81] = sta_op(wr_x_ind_op),

	[0x84] = sty_op(wr_zp_op),
	[0x85] = sta_op(wr_zp_op),
	[0x86] = stx_op(wr_zp_op),

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

	[0x8C] = sty_op(wr_abs_op),
	[0x8D] = sta_op(wr_abs_op),
	[0x8E] = stx_op(wr_abs_op),

	[0x90] = branchop("BCC", function(cpu) return not cpu.p.c end),

	[0x91] = sta_op(wr_ind_y_op),
	[0x94] = sty_op(wr_zp_x_op),
	[0x95] = sta_op(wr_zp_x_op),
	[0x96] = stx_op(wr_zp_ind_op),

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

	[0x99] = sta_op(wr_abs_y_op),

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

	[0x9D] = sta_op(wr_abs_x_op),

	-- 0xA0: LDY (immediate)
	[0xA0] = {
		op = "LDY",
		[1] = store_data_in_y,
		[0] = prepare_next_op,
	},

	[0xA1] = lda_op(rd_x_ind_op),

	-- 0xA2: LDX (immediate)
	[0xA2] = {
		op = "LDX",
		[1] = store_data_in_x,
		[0] = prepare_next_op,
	},

	[0xA4] = ldy_op(rd_zp_op),
	[0xA5] = lda_op(rd_zp_op),
	[0xA6] = ldx_op(rd_zp_op),

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

	[0xA9] = lda_op(rd_immediate_op),

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

	[0xB1] = lda_op(rd_ind_y_op),
	[0xB4] = ldy_op(rd_zp_x_op),
	[0xB5] = lda_op(rd_zp_x_op),
	[0xB6] = ldx_op(rd_zp_y_op),

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

	[0xB9] = lda_op(rd_abs_y_op),

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

	[0xBC] = ldy_op(rd_abs_x_op),
	[0xBD] = lda_op(rd_abs_x_op),
	[0xBE] = ldx_op(rd_abs_y_op),

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
			update_flags(cpu, mask_byte(cpu.y - cpu.TEMPORARY_FOR_CMP))
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.y
			prepare_next_op(cpu)
		end
	},

	[0xC1] = cmp_op(rd_x_ind_op),
	[0xC4] = cmp_zp_op("CPY", get_y),
	[0xC5] = cmp_zp_op("CMP", get_a),
	[0xC6] = dec_op(rmw_zp_op),

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

	[0xC9] = {
		op = "CMP",
		[1] = function(cpu)
			cpu.TEMPORARY_FOR_CMP = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.tcu = 0
		end,
		[0] = function(cpu)
			update_flags(cpu, mask_byte(cpu.a - cpu.TEMPORARY_FOR_CMP))
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.a
			prepare_next_op(cpu)
		end
	},

	[0xCA] = {
		op = "DEX",
		[1] = nop_tcu0,
		[0] = function(cpu)
			dec_x(cpu)
			prepare_next_op(cpu)
		end
	},

	[0xCC] = cmp_abs_op("CPY", get_y),
	[0xCD] = cmp_abs_op("CMP", get_a),
	[0xCE] = dec_op(rmw_abs_op),

	[0xD5] = {
		op = "CMP",
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.x)
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

	[0xD9] = cmp_op(rd_abs_y_op),
	[0xDD] = cmp_op(rd_abs_x_op),

	-- 0xD0: BNE (relative)
	-- Branch if not equal (Z != 0)
	[0xD0] = branchop("BNE", function(cpu) return not cpu.p.z end),

	[0xD1] = cmp_op(rd_ind_y_op),
	[0xD6] = dec_op(rmw_zp_x_op),

	-- 0xD8: CLD
	[0xD8] = {
		op = "CLD",
		[1] = function(cpu)
			cpu.p.d = false
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0xDE] = dec_op(rmw_abs_x_op),

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
			update_flags(cpu, mask_byte(cpu.x - cpu.TEMPORARY_FOR_CMP))
			cpu.p.c = cpu.TEMPORARY_FOR_CMP <= cpu.x
			prepare_next_op(cpu)
		end
	},

	[0xE1] = sbc_op(rd_x_ind_op),
	[0xE4] = cmp_zp_op("CPX", get_x),
	[0xE5] = sbc_op(rd_zp_op),
	[0xE6] = inc_op(rmw_zp_op),

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

	[0xE9] = sbc_op(rmw_immediate_op),

	[0xEA] = {
		op = "NOP",
		[1] = function(cpu)
			cpu.tcu = 0
		end,
		[0] = prepare_next_op
	},

	[0xEC] = cmp_abs_op("CPX", get_x),
	[0xED] = sbc_op(rd_abs_op),
	[0xEE] = inc_op(rmw_abs_op),
	[0xF0] = branchop("BEQ", function(cpu) return cpu.p.z end),
	[0xF1] = sbc_op(rd_ind_y_op),
	[0xF5] = sbc_op(rd_zp_x_op),
	[0xF6] = inc_op(rmw_zp_x_op),

	[0xF8] = {
		op = "SED",
		[1] = function(cpu)
			cpu.p.d = true
			cpu.tcu = 0
		end,
		[0] = prepare_next_op,
	},

	[0xF9] = sbc_op(rd_abs_y_op),
	[0xFD] = sbc_op(rd_abs_x_op),
	[0xFE] = inc_op(rmw_abs_x_op),
}

local function op_metadata(opcode)
	-- Operations are laid out by a pattern a-b-c, where a is bit 5..7,
	-- b is bit 2..4 and c is 0..1.
	-- Ref: https://www.masswerk.at/6502/6502_instruction_set.html#layout
	local a = bit.band(bit.rshift(opcode, 5), 7)
	local b = bit.band(bit.rshift(opcode, 2), 7)
	local c = bit.band(opcode, 3)

	-- Determine addressing mode
	local y_exception = (c == 2 or c == 3) and (a == 4 or a == 5)
	local adrmode = nil
	if b == 7 then
		adrmode = (y_exception and ADRMODE_ABS_Y) or ADRMODE_ABS_X
	elseif b == 6 then
		adrmode = ((c == 0 or c == 2) and ADRMODE_IMPL) or ADRMODE_ABS_Y
	elseif b == 5 then
		adrmode = (y_exception and ADRMODE_ZPG_Y) or ADRMODE_ZPG_X
	elseif b == 4 then
		adrmode = ((c == 0 or c == 2) and ADRMODE_REL) or ADRMODE_IND_Y
	elseif b == 3 then
		adrmode = (opcode == 0x6C and ADRMODE_IND) or ADRMODE_ABS
	elseif b == 2 then
		if c == 2 and b < 4 then
			adrmode = ADRMODE_ACC
		else
			adrmode = ((c == 0 or c == 2) and ADRMODE_IMPL) or ADRMODE_IMMEDIATE
		end
	elseif b == 1 then
		adrmode = ADRMODE_ZPG
	else
		if c == 1 or c == 3 then
			adrmode = ADRMODE_X_IND
		elseif opcode == 0x00 or opcode == 0x40 or opcode == 0x60 then
			adrmode = ADRMODE_IMPL
		elseif opcode == 0x20 then
			adrmode = ADRMODE_ABS
		else
			adrmode = ADRMODE_IMMEDIATE
		end
	end

	-- Operands based on c, a, b grouping
	local opgrid = zb {
		zb {
			zb { OP_BRK, OPX_NOP, OP_PHP, OPX_NOP, OP_BPL, OPX_NOP, OP_CLC, OPX_NOP },
			zb { OP_JSR, OP_BIT, OP_PLP, OP_BIT, OP_BMI, OPX_NOP, OP_SEC, OPX_NOP },
			zb { OP_RTI, OPX_NOP, OP_PHA, OP_JMP, OP_BVC, OPX_NOP, OP_CLI, OPX_NOP },
			zb { OP_RTS, OPX_NOP, OP_PLA, OP_JMP, OP_BVS, OPX_NOP, OP_SEI, OPX_NOP },
			zb { OPX_NOP, OP_STY, OP_DEY, OP_STY, OP_BCC, OP_STY, OP_TYA, OPX_SHY },
			zb { OP_LDY, OP_LDY, OP_TAY, OP_LDY, OP_BCS, OP_LDY, OP_CLV, OP_LDY },
			zb { OP_CPY, OP_CPY, OP_INY, OP_CPY, OP_BNE, OPX_NOP, OP_CLD, OPX_NOP },
			zb { OP_CPX, OP_CPX, OP_INX, OP_CPX, OP_BEQ, OPX_NOP, OP_SED, OPX_NOP }
		},
		zb {
			map_range(8, OP_ORA),
			map_range(8, OP_AND),
			map_range(8, OP_EOR),
			map_range(8, OP_ADC),
			map_range(8, function(i) return (i == 2 and OP_NOP) or OP_STA end),
			map_range(8, OP_LDA),
			map_range(8, OP_CMP),
			map_range(8, OP_SBC),
		},
		zb {
			zb { OPX_JAM, OP_ASL, OP_ASL, OP_ASL, OPX_JAM, OP_ASL, OP_NOP, OP_ASL },
			zb { OPX_JAM, OP_ROL, OP_ROL, OP_ROL, OPX_JAM, OP_ROL, OP_NOP, OP_ROL },
			zb { OPX_JAM, OP_LSR, OP_LSR, OP_LSR, OPX_JAM, OP_LSR, OP_NOP, OP_LSR },
			zb { OPX_JAM, OP_ROR, OP_ROR, OP_ROR, OPX_JAM, OP_ROR, OP_NOP, OP_ROR },
			zb { OPX_NOP, OP_STX, OP_TXA, OP_STX, OPX_JAM, OP_STX, OP_TXS, OPX_SHX },
			zb { OPX_LDX, OP_LDX, OP_TAX, OP_LDX, OPX_JAM, OP_LDX, OP_TSX, OP_LDX },
			zb { OPX_NOP, OP_DEC, OP_DEC, OP_DEC, OPX_JAM, OP_DEC, OP_NOP, OP_DEC },
			zb { OPX_NOP, OP_INC, OP_NOP, OP_INC, OPX_JAM, OP_INC, OP_NOP, OP_INC },
		},
		zb {
			zb { OPX_SLO, OPX_SLO, OPX_ANC, OPX_SLO, OPX_SLO, OPX_SLO, OPX_SLO, OPX_SLO },
			zb { OPX_RLA, OPX_RLA, OPX_ANC, OPX_RLA, OPX_RLA, OPX_RLA, OPX_RLA, OPX_RLA },
			zb { OP_SRE, OP_SRE, OPX_ALR, OP_SRE, OP_SRE, OP_SRE, OP_SRE, OP_SRE },
			zb { OPX_RRA, OPX_RRA, OPX_ARR, OPX_RRA, OPX_RRA, OPX_RRA, OPX_RRA, OPX_RRA },
			zb { OPX_SAX, OPX_SAX, OPX_ANE, OPX_SAX, OPX_SHA, OPX_SAX, OPX_TAS, OPX_SHA },
			zb { OPX_LAX, OPX_LAX, OPX_LXA, OPX_LAX, OPX_LAX, OPX_LAX, OPX_LAS, OPX_LAX },
			zb { OPX_DCP, OPX_DCP, OPX_SBX, OPX_DCP, OPX_DCP, OPX_DCP, OPX_DCP, OPX_DCP },
			zb { OPX_ISC, OPX_ISC, OPX_USBC, OPX_ISC, OPX_ISC, OPX_ISC, OPX_ISC, OPX_ISC }
		}
	}

	local op = opgrid[c][a][b]
	local meta = nil

	local adr = adrmode_meta[adrmode]

	return {
		adr = adrmode,
		op = opgrid[c][a][b]
	}
end

-- Generate instruction table. Contains all 256 operations (0..255)
-- and each operation is defined as:
--
-- {
--   optype: OP_*
--   adrmode: ADRMODE_*
--   [1..n]: suboperation per cycle
--   [0]: supoperation for final cycle
-- }
local function generate_instructions()
	local all = {}
	local n = 0

	for opcode = 0, 255 do
		local data = op_metadata(opcode)
		data = data or Cpu6502.instructions[opcode]
		if not data then
			printf("Warning: no definition for op 0x%02x\n", opcode)
		elseif data.optype == nil then
			printf("Warning: no op for opcode 0x%02x\n", opcode)
		elseif data.adrmode == nil then
			printf("Warning: no adrmode for opcode 0x%02x\n", opcode)
		else
			n = n + 1
		end
	end

	printf("OK: %d/%d\n", n, 256)

	return all
end

-- generate_instructions()
-- os.exit(0)
--
local defined_count = 0
local complete_count = 0
for opcode = 0, 256 do
	local meta = Cpu6502.instructions[opcode]
	if meta ~= nil then
		defined_count = defined_count + 1
		if meta.mnemonic and meta.len and meta[0] and meta[1] then
			complete_count = complete_count + 1
		end
	end
end

printf("Defined: %d. Complete: %d.\n", defined_count, complete_count)
os.exit(0)

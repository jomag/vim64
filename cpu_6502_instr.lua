-- 6502 instructions
--
-- Each instruction is a table with these fields:
--
-- mnemonic:  assembly mnemonic, "ORA", "JMP", etc
-- adr:       addressing mode (ADR_*)
-- regs:      involved registers (for debugging). optional.
-- [1..n, 0]: subcycle operations

ADR_IMMEDIATE = "immediate"
ADR_ZP = "zp"
ADR_ZP_X = "zp,x"
ADR_ZP_Y = "zp,y"
ADR_ABS = "abs"
ADR_X_IND = "x,ind"
ADR_ZP_IND = "zp,ind"
ADR_IND_Y = "ind,y"
ADR_ABS_X = "abs,x"
ADR_ABS_Y = "abs,y"
ADR_IMPL = "impl"
ADR_REL = "rel"
ADR_IND = "ind"

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
	cpu:prepare_op(cpu.data, cpu.adr)
	cpu.op_cycle = 1
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
end

local function generic_abs_cycle1(cpu)
	cpu.LOW_BYTE = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.op_cycle = 2
end

local function dec_x(cpu)
	cpu.x = mask_byte(cpu.x - 1)
	update_flags(cpu, cpu.x)
end

local function dec_y(cpu)
	cpu.y = mask_byte(cpu.y - 1)
	update_flags(cpu, cpu.y)
end

local function nop_op_cycle0(cpu)
	cpu.op_cycle = 0
end

local function load_abs_cycle2(cpu)
	cpu.adr = word(cpu.LOW_BYTE, cpu.data)
	cpu.pc = cpu.pc + 1
	cpu.op_cycle = 3
end

local function generic_abs_y_cycle1(cpu)
	cpu.ABS_Y_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.op_cycle = 2
end

local function generic_abs_x_cycle1(cpu)
	cpu.ABS_X_PCL = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.pc
	cpu.op_cycle = 2
end

local function load_abs_y_cycle2(cpu)
	cpu.pc = cpu.pc + 1
	cpu.ABS_Y_PCH = cpu.data
	cpu.adr = word(mask_byte(cpu.ABS_Y_PCL + cpu.y), cpu.ABS_Y_PCH)
	if cpu.ABS_Y_PCL + cpu.y > 0xFF then
		cpu.op_cycle = 3
	else
		cpu.op_cycle = 4
	end
end

local function generic_zp_indexed_cycle1(cpu)
	cpu.adr = cpu.data
	cpu.pc = cpu.pc + 1
	cpu.op_cycle = 2
end

local function generic_ind_y_cycle1(cpu)
	cpu.adr = cpu.data
	cpu.op_cycle = 2
	cpu.pc = cpu.pc + 1
end

local function generic_ind_y_cycle2(cpu)
	cpu.LOW = cpu.data
	cpu.adr = cpu.adr + 1
	cpu.op_cycle = 3
end

local function generic_x_ind_cycle1(cpu)
	cpu.pc = cpu.pc + 1
	cpu.PCL = cpu.data
	cpu.adr = cpu.data
	cpu.op_cycle = 2
end

local function generic_x_ind_cycle2(cpu)
	cpu.adr = mask_byte(cpu.PCL + cpu.x)
	cpu.op_cycle = 3
end

local function generic_x_ind_cycle3(cpu)
	cpu.LOW = cpu.data
	cpu.adr = cpu.adr + 1
	cpu.op_cycle = 4
end

local function read_zp_cycle1(cpu)
	cpu.pc = cpu.pc + 1
	cpu.adr = cpu.data
	cpu.op_cycle = 2
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
	cpu.op_cycle = 0
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
		adr = ADR_IMMEDIATE,
		[1] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
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
		adr = ADR_IMMEDIATE,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			process_cb(cpu, cpu.TMP)
			prepare_next_op(cpu)
		end
	}
end

local function rd_zp_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_ZP,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
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
		adr = ADR_ZP,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.RMW_ZP_TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.data = process_cb(cpu, cpu.RMW_ZP_TMP)
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

local function wr_zp_op(value_cb)
	return {
		len = 2,
		adr = ADR_ZP,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.data
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


local function rd_zp_y_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_ZP_Y,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.y)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				cpu.a = process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end


local function rd_abs_op(prep_cb, process_cb)
	return {
		len = 3,
		adr = ADR_ABS,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
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
		adr = ADR_ABS,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.data = process_cb(cpu, cpu.data)
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end


local function wr_abs_op(value_cb)
	return {
		len = 3,
		adr = ADR_ABS,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.LOW_BYTE, cpu.data)
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

-- X-indexed, indirect
local function rd_x_ind_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_X_IND,
		[1] = generic_x_ind_cycle1,
		[2] = generic_x_ind_cycle2,
		[3] = generic_x_ind_cycle3,
		[4] = function(cpu)
			cpu.adr = word(cpu.LOW, cpu.data)
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

local function wr_x_ind_op(value_cb)
	return {
		len = 2,
		adr = ADR_X_IND,
		[1] = generic_x_ind_cycle1,
		[2] = generic_x_ind_cycle2,
		[3] = generic_x_ind_cycle3,
		[4] = function(cpu)
			cpu.read = false
			cpu.adr = word(cpu.LOW, cpu.data)
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

-- inderect, Y-indexed
local function rd_ind_y_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_IND_Y,
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = function(cpu)
			cpu.FINAL_ADR = bit.lshift(cpu.data, 8) + cpu.LOW + cpu.y
			cpu.adr = word(mask_byte(cpu.LOW + cpu.y), cpu.data)
			if cpu.adr ~= cpu.FINAL_ADR then
				cpu.op_cycle = 4
			else
				cpu.op_cycle = 5
			end
		end,
		[4] = function(cpu)
			cpu.adr = cpu.FINAL_ADR
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

local function wr_ind_y_op(value_cb)
	return {
		len = 2,
		adr = ADR_IND_Y,
		[1] = generic_ind_y_cycle1,
		[2] = generic_ind_y_cycle2,
		[3] = function(cpu)
			cpu.FINAL_ADR = bit.lshift(cpu.data, 8) + cpu.LOW + cpu.y
			cpu.adr = word(mask_byte(cpu.LOW + cpu.y), cpu.data)
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.adr = cpu.FINAL_ADR
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function wr_zp_ind_op(value_cb)
	return {
		len = 2,
		adr = ADR_ZP_IND,
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.read = false
			cpu.adr = mask_byte(cpu.adr + cpu.y)
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


local function rd_abs_x_op(prep_cb, process_cb)
	return {
		len = 3,
		adr = ADR_ABS_X,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.x), cpu.ABS_X_PCH)
			if cpu.ABS_X_PCL + cpu.x > 0xFF then
				cpu.op_cycle = 3
			else
				cpu.op_cycle = 4
			end
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.x
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end

-- Read-Modify-Write operation with absolute, X-indexed addresing
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_abs_x_op(prep_cb, process_cb)
	return {
		len = 3,
		adr = ADR_ABS_X,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.HIGH_BYTE = cpu.data
			cpu.adr = word(mask_byte(cpu.LOW_BYTE + cpu.x), cpu.HIGH_BYTE)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.HIGH_BYTE, 8) + cpu.LOW_BYTE + cpu.x
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.data = process_cb(cpu, cpu.data)
			cpu.op_cycle = 6
		end,
		[6] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

local function wr_abs_x_op(value_cb)
	return {
		len = 3,
		adr = ADR_ABS_X,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.x), cpu.ABS_X_PCH)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.x
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

local function wr_abs_y_op(value_cb)
	return {
		len = 3,
		adr = ADR_ABS_Y,
		[1] = generic_abs_x_cycle1,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.ABS_X_PCH = cpu.data
			cpu.adr = word(mask_byte(cpu.ABS_X_PCL + cpu.y), cpu.ABS_X_PCH)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_X_PCH, 8) + cpu.ABS_X_PCL + cpu.y
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

local function rd_abs_y_op(prep_cb, process_cb)
	return {
		len = 3,
		adr = ADR_ABS_Y,
		[1] = generic_abs_y_cycle1,
		[2] = load_abs_y_cycle2,
		[3] = function(cpu)
			cpu.adr = bit.lshift(cpu.ABS_Y_PCH, 8) + cpu.ABS_Y_PCL + cpu.y
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end,
	}
end


-- Read-Modify-Write operation performed on accumulator.
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 3.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_impl_op(prep_cb, process_cb)
	return {
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			if prep_cb then
				prep_cb(cpu, cpu.a)
			end
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			cpu.a = process_cb(cpu, cpu.a)
			prepare_next_op(cpu)
		end
	}
end

-- Zero-page, X indexed
local function rd_zp_x_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_ZP_X,
		[1] = generic_zp_indexed_cycle1,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.x)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			if process_cb then
				process_cb(cpu, cpu.TMP)
			end
			prepare_next_op(cpu)
		end
	}
end

-- Read-Modify-Write operation on zero-page, X-indexed
-- Most (all?) operations do some status flag update,
-- which is done through the prep callback in cycle 2.
-- Operations: ASL, LSR, ROL, ROR
local function rmw_zp_x_op(prep_cb, process_cb)
	return {
		len = 2,
		adr = ADR_ZP_X,
		[1] = function(cpu)
			cpu.adr = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr + cpu.x
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.RMW_ZP_TMP = cpu.data
			if prep_cb then
				prep_cb(cpu, cpu.data)
			end
			cpu.read = false
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.data = process_cb(cpu, cpu.RMW_ZP_TMP)
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.read = true
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end


local function wr_zp_x_op(value_cb)
	return {
		len = 2,
		adr = ADR_ZP_X,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.data
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = mask_byte(cpu.adr + cpu.x)
			cpu.read = false
			cpu.data = value_cb(cpu)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


---
--- Operations
---

local function brk_op()
	return {
		mnemonic = "BRK",
		adr = ADR_IMPL,
		len = 1,
		[1] = function(cpu)
			if cpu.int_state ~= "irq" and cpu.int_state ~= "nmi" then
				-- If int_state is not set to "irq" or "nmi", it means that
				-- the interrupt sequence was not triggered by an external
				-- event, so it must be the BRK operation. In that case,
				-- push PC+2 as return address.
				cpu.int_state = "brk"
			end
			cpu.adr = 0x100 + cpu.sp
			if cpu.int_state == "brk" then
				cpu.pc = cpu.pc + 1
				cpu.data = upper_byte(cpu.op_adr + 2)
			else
				cpu.data = upper_byte(cpu.op_adr)
			end
			cpu.read = false
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			if cpu.int_state ~= "irq" and cpu.int_state ~= "nmi" then
				-- If int_state is not set to "irq" or "nmi", it means that
				-- the interrupt sequence was not triggered by an external
				-- event, so it must be the BRK operation. In that case,
				-- push PC+2 as return address.
				cpu.int_state = "brk"
			end
			cpu.adr = 0x100 + mask_byte(cpu.sp - 1)
			if cpu.int_state == "brk" then
				cpu.data = bit.band(cpu.op_adr + 2, 0xFF)
			else
				cpu.data = bit.band(cpu.op_adr, 0xFF)
			end
			cpu.read = false
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = 0x100 + mask_byte(cpu.sp - 2)
			-- FIXME: Probably depending on int_state?
			cpu.data = bit.bor(cpu:get_p(), 0x20)
			cpu.read = false
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.sp = mask_byte(cpu.sp - 3)
			cpu.p.i = true
			cpu.adr = cpu.int_vector
			cpu.read = true
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.BRK_PCL = cpu.data
			cpu.adr = cpu.int_vector + 1
			cpu.op_cycle = 6
		end,
		[6] = function(cpu)
			cpu.pc = word(cpu.BRK_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
			cpu.int_state = nil
			cpu.int_pending = false

			-- In case of concurrent BRK and NMI, we need to set
			-- this to false in case it's handled as a BRK
			cpu.nmi_edge_detected = false
		end,
		[0] = prepare_next_op,
	}
end

local function rti_op()
	return {
		mnemonic = "RTI",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = 0x100 + cpu.sp
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.adr + 1
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.adr = cpu.adr + 1
			cpu:set_p(cpu.data)
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.RTI_PCL = cpu.data
			cpu.sp = cpu.sp + 3
			cpu.adr = cpu.adr + 1
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.pc = word(cpu.RTI_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


local function rts_op()
	return {
		mnemonic = "RTS",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = bit.bor(0x100, cpu.sp)
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = bit.bor(0x100, cpu.sp + 1)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.RTS_PCL = cpu.data
			cpu.sp = cpu.sp + 2
			cpu.adr = bit.bor(0x100, cpu.sp)
			cpu.p.ignored_bit = true
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.pc = word(cpu.RTS_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.p.ignored_bit = false
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op
	}
end

local function jsr_op()
	return {
		mnemonic = "JSR",
		len = 1,
		adr = ADR_ABS,
		[1] = function(cpu)
			cpu.JSR_SP_COPY = cpu.sp
			cpu.JSR_PCL = cpu.data
			cpu.adr = 0x100 + cpu.sp
			cpu.sp = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.read = false
			cpu.data = upper_byte(cpu.pc)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.read = false
			cpu.data = mask_byte(cpu.pc)
			cpu.adr = 0x100 + cpu.JSR_SP_COPY - 1
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			-- cpu.pc = cpu.pc + 1
			cpu.op_cycle = 5
		end,
		[5] = function(cpu)
			cpu.adr = word(cpu.JSR_PCL, cpu.data)
			cpu.pc = cpu.adr
			cpu.sp = mask_byte(cpu.JSR_SP_COPY - 2)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function jmp_abs_op()
	return {
		mnemonic = "JMP",
		len = 3,
		adr = ADR_ABS,
		[1] = generic_abs_cycle1,
		[2] = function(cpu)
			cpu.pc = word(cpu.LOW_BYTE, cpu.data)
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function jmp_indirect_op()
	return {
		mnemonic = "JMP",
		len = 3,
		adr = ADR_IND,

		[1] = function(cpu)
			cpu.JMP_INDIRECT_LOW_BYTE = cpu.data
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.pc = cpu.pc + 1
			cpu.adr = word(cpu.JMP_INDIRECT_LOW_BYTE, cpu.data)
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			cpu.JMP_INDIRECT_PCL = cpu.data
			cpu.adr = cpu.adr + 1
			cpu.op_cycle = 4
		end,
		[4] = function(cpu)
			cpu.pc = word(cpu.JMP_INDIRECT_PCL, cpu.data)
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function sei_op()
	return {
		mnemonic = "SEI",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.p.i = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function cli_op()
	return {
		mnemonic = "CLI",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.p.i = false
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function sec_op()
	return {
		mnemonic = "SEC",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.p.c = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function clc_op()
	return {
		mnemonic = "CLC",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.p.c = false
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function tsx_op()
	return {
		mnemonic = "TSX",
		len = 1,
		adr = ADR_IMPL,
		regs = { "sp" },

		[1] = function(cpu)
			cpu.x = cpu.sp
			update_flags(cpu, cpu.x)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function txs_op()
	return {
		mnemonic = "TXS",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.sp = cpu.x
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


local function tax_op()
	return {
		mnemonic = "TAX",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.x = cpu.a
			update_flags(cpu, cpu.x)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function txa_op()
	return {
		mnemonic = "TXA",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.a = cpu.x
			update_flags(cpu, cpu.a)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function tay_op()
	return {
		mnemonic = "TAY",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.y = cpu.a
			update_flags(cpu, cpu.y)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function tya_op()
	return {
		mnemonic = "TYA",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.a = cpu.y
			update_flags(cpu, cpu.a)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end


local function clv_op()
	return {
		mnemonic = "CLV",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.p.o = false
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function sed_op()
	return {
		mnemonic = "SED",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.p.d = true
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function cld_op()
	return {
		mnemonic = "CLD",
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.p.d = false
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

-- BNE, BEQ, BVS, BVC,
local function branch_op(mnemonic, condition_cb)
	return {
		mnemonic = mnemonic,
		len = 2,
		adr = ADR_REL,

		[1] = function(cpu)
			cpu.BRANCH_OPERAND = byte_as_i8(cpu.data) -- FIXME
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.op_cycle = 2
		end,

		[2] = function(cpu)
			if condition_cb(cpu) then
				cpu.FINAL_PC = cpu.pc + cpu.BRANCH_OPERAND

				cpu.pc = bit.bor(bit.band(cpu.pc, 0xFF00), bit.band(cpu.FINAL_PC, 0xff))
				cpu.adr = cpu.pc

				if cpu.pc ~= cpu.FINAL_PC then
					cpu.op_cycle = 3
				else
					cpu.op_cycle = 4
				end
			else
				cpu:prepare_op(cpu.data, cpu.adr)
				cpu.pc = cpu.pc + 1
				cpu.adr = cpu.pc
				cpu.op_cycle = 1
			end
		end,

		[3] = function(cpu)
			cpu.pc = cpu.FINAL_PC
			cpu.adr = cpu.pc
			cpu.op_cycle = 4
		end,

		[4] = function(cpu)
			cpu:prepare_op(cpu.data, cpu.adr)
			cpu.pc = cpu.pc + 1
			cpu.adr = cpu.pc
			cpu.op_cycle = 1
		end,

		-- TODO: Document why not cycle 0
		[5] = prepare_next_op,
	}
end

-- PHA, PHP
local function pushop(mnemonic, value_cb)
	local regs = nil
	if mnemonic == "PHA" then
		regs = { "a" }
	elseif mnemonic == "PHP" then
		regs = { "p" }
	end

	return {
		mnemonic = mnemonic,
		len = 1,
		adr = ADR_IMPL,
		regs = regs,
		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.data = value_cb(cpu)
			cpu.read = false
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			cpu.adr = cpu.pc
			cpu.read = true
			cpu.sp = mask_byte(cpu.sp - 1)
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

-- PLA, PLP
local function pull_op(mnemonic, setter_cb)
	return {
		mnemonic = mnemonic,
		len = 1,
		adr = ADR_IMPL,

		[1] = function(cpu)
			cpu.adr = 0x100 + cpu.sp
			cpu.op_cycle = 2
		end,
		[2] = function(cpu)
			-- cpu.TEMPORARY_STACK_REG = cpu.data
			cpu.sp = inc_byte(cpu.sp)
			-- cpu.pc = cpu.pc + 1
			cpu.adr = 0x100 + cpu.sp
			cpu.op_cycle = 3
		end,
		[3] = function(cpu)
			setter_cb(cpu, cpu.data)
			cpu.adr = cpu.pc
			cpu.op_cycle = 0
		end,
		[0] = prepare_next_op,
	}
end

local function pla_op()
	return pull_op("PLA", function(cpu, val)
		cpu.a = val
		update_flags(cpu, val)
	end)
end

local function plp_op()
	return pull_op("PLP", function(cpu, val)
		cpu:set_p(bit.bor(val, 16))
	end)
end

local function cmp_op(addr_fun)
	return merge(
		{
			mnemonic = "CMP",
			regs = { "a" }
		},
		addr_fun(
			nil,
			function(cpu, val)
				cpu:exec_sub(cpu.a, val)
			end
		)
	)
end

local function cpx_op(addr_fun)
	return merge(
		{
			mnemonic = "CPX",
			regs = { "x" },
		},
		addr_fun(
			nil,
			function(cpu)
				cpu:exec_sub(cpu.x, cpu.TMP)
			end
		)
	)
end

local function cpy_op(addr_fun)
	return merge(
		{
			mnemonic = "CPY",
			regs = { "y" },
		},
		addr_fun(
			nil,
			function(cpu)
				cpu:exec_sub(cpu.y, cpu.TMP)
			end
		)
	)
end

-- Note: there's only one *legal* NOP operation.
-- But there are many other *illegal* operations,
-- with other addressing modes.
local function nop_op()
	return {
		mnemonic = "NOP",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu)
			cpu.op_cycle = 0
		end,
		[0] = function(cpu)
			prepare_next_op(cpu)
		end
	}
end

local function asl_op(addr_fun)
	return merge(
		{ mnemonic = "ASL" },
		addr_fun(
			nil,
			function(cpu, val)
				val = bit.lshift(val, 1)
				cpu.p.c = val > 0xFF
				return cpu:exec_load(mask_byte(val))
			end
		)
	)
end

local function lsr_op(addr_fun)
	return merge(
		{ mnemonic = "LSR" },
		addr_fun(
			function(cpu, val)
				cpu.p.c = bit0(val)
			end,
			function(cpu, val)
				return cpu:exec_load(bit.rshift(val, 1))
			end
		)
	)
end

local function rol_op(addr_fun)
	return merge(
		{ mnemonic = "ROL" },
		addr_fun(
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
	)
end

local function ror_op(addr_fun)
	return merge(
		{ mnemonic = "ROR" },
		addr_fun(
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
	)
end

local function inc_op(addr_fun)
	return merge(
		{
			mnemonic = "INC"
		},
		addr_fun(
			nil,
			function(cpu, val)
				return cpu:exec_load(mask_byte(val + 1))
			end
		)
	)
end

local function inx_op()
	return {
		mnemonic = "INX",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu) cpu.op_cycle = 0 end,
		[0] = function(cpu)
			cpu.x = inc_byte(cpu.x)
			update_flags(cpu, cpu.x)
			prepare_next_op(cpu)
		end
	}
end

local function iny_op()
	return {
		mnemonic = "INY",
		len = 1,
		adr = ADR_IMPL,
		[1] = function(cpu) cpu.op_cycle = 0 end,
		[0] = function(cpu)
			cpu.y = inc_byte(cpu.y)
			update_flags(cpu, cpu.y)
			prepare_next_op(cpu)
		end
	}
end

local function dec_op(addr_fun)
	return merge(
		{
			mnemonic = "DEC"
		},
		addr_fun(
			nil,
			function(cpu, val)
				return cpu:exec_load(mask_byte(val - 1))
			end
		)
	)
end

local function dex_op()
	return {
		mnemonic = "DEX",
		len = 1,
		adr = ADR_IMPL,
		regs = { "x" },
		[1] = nop_op_cycle0,
		[0] = function(cpu)
			dec_x(cpu)
			prepare_next_op(cpu)
		end
	}
end

local function dey_op()
	return {
		mnemonic = "DEY",
		len = 1,
		adr = ADR_IMPL,
		regs = { "y" },
		[1] = nop_op_cycle0,
		[0] = function(cpu)
			dec_y(cpu)
			prepare_next_op(cpu)
		end
	}
end

local function and_op(addr_fun)
	return merge(
		{ mnemonic = "AND", regs = { "a" } },
		addr_fun(
			function(cpu, val)
				cpu.p.n = bit7(val)
				cpu.p.z = val == 0
			end,
			function(cpu, val)
				cpu.a = cpu:exec_load(bit.band(cpu.a, val))
			end
		)
	)
end

local function ora_op(addr_fun)
	return merge(
		{ mnemonic = "ORA", regs = { "a" } },
		addr_fun(
			nil,
			function(cpu, val)
				cpu.a = cpu:exec_load(bit.bor(cpu.a, val))
			end
		)
	)
end

local function eor_op(addr_fun)
	return merge(
		{ mnemonic = "EOR", regs = { "a" } },
		addr_fun(
			nil,
			function(cpu, val)
				cpu.a = cpu:exec_load(bit.bxor(cpu.a, val))
			end
		)
	)
end

local function bit_zp_op()
	return {
		mnemonic = "BIT",
		len = 2,
		adr = ADR_ZP,
		[1] = read_zp_cycle1,
		[2] = bitop_cyclen,
		[0] = bitop_cycle0,
	}
end

local function bit_abs_op()
	return {
		mnemonic = "BIT",
		len = 3,
		adr = ADR_ABS,
		[1] = generic_abs_cycle1,
		[2] = load_abs_cycle2,
		[3] = bitop_cyclen,
		[0] = bitop_cycle0,
	}
end

local function lda_op(addr_fun)
	return merge(
		{
			mnemonic = "LDA",
		},
		addr_fun(
			function(cpu, val)
				cpu.a = cpu:exec_load(val)
			end,
			nil
		)
	)
end

local function ldy_op(addr_fun)
	return merge(
		{
			mnemonic = "LDY",
		},
		addr_fun(
			function(cpu, val)
				cpu.y = cpu:exec_load(val)
			end,
			nil
		)
	)
end

local function ldx_op(addr_fun)
	return merge(
		{
			mnemonic = "LDX",
		},
		addr_fun(
			function(cpu, val)
				cpu.x = cpu:exec_load(val)
			end,
			nil
		)
	)
end

local function sta_op(addr_fun)
	return merge(
		{ mnemonic = "STA", regs = { "a" } },
		addr_fun(function(cpu) return cpu.a end)
	)
end

local function stx_op(addr_fun)
	return merge(
		{ mnemonic = "STX", regs = { "x" } },
		addr_fun(function(cpu) return cpu.x end)
	)
end

local function sty_op(addr_fun)
	return merge(
		{ mnemonic = "STY", regs = { "y" } },
		addr_fun(function(cpu) return cpu.y end)
	)
end

local function adc_op(addr_fun)
	return merge(
		{ mnemonic = "ADC" },
		addr_fun(
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
					cpu.a = sum
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
					cpu.a = result
				end
			end
		)
	)
end

local function sbc_op(addr_fun)
	return merge(
		{
			mnemonic = "SBC"
		},
		addr_fun(
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
					cpu.a = sum
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
					cpu.a = result
				end
			end
		)
	)
end

INSTRUCTIONS_6502 = {
	[0x00] = brk_op(),
	[0x01] = ora_op(rd_x_ind_op),
	[0x05] = ora_op(rd_zp_op),
	[0x06] = asl_op(rmw_zp_op),
	[0x08] = pushop("PHP", function(cpu)
		return bit.bor(cpu:get_p(), 0x30)
	end),
	[0x09] = ora_op(rmw_immediate_op),
	[0x0A] = asl_op(rmw_impl_op),
	[0x0D] = ora_op(rd_abs_op),
	[0x0E] = asl_op(rmw_abs_op),
	[0x10] = branch_op("BPL", function(cpu) return not cpu.p.n end),
	[0x11] = ora_op(rd_ind_y_op),
	[0x15] = ora_op(rd_zp_x_op),
	[0x16] = asl_op(rmw_zp_x_op),
	[0x18] = clc_op(),
	[0x19] = ora_op(rd_abs_y_op),
	[0x1D] = ora_op(rd_abs_x_op),
	[0x1E] = asl_op(rmw_abs_x_op),
	[0x20] = jsr_op(),
	[0x21] = and_op(rd_x_ind_op),
	[0x24] = bit_zp_op(),
	[0x25] = and_op(rd_zp_op),
	[0x26] = rol_op(rmw_zp_op),
	[0x28] = plp_op(),
	[0x29] = and_op(rmw_immediate_op),
	[0x2A] = rol_op(rmw_impl_op),
	[0x2C] = bit_abs_op(),
	[0x2D] = and_op(rd_abs_op),
	[0x2E] = rol_op(rmw_abs_op),
	[0x30] = branch_op("BMI", function(cpu) return cpu.p.n end),
	[0x31] = and_op(rd_ind_y_op),
	[0x35] = and_op(rd_zp_x_op),
	[0x36] = rol_op(rmw_zp_x_op),
	[0x38] = sec_op(),
	[0x39] = and_op(rd_abs_y_op),
	[0x3D] = and_op(rd_abs_x_op),
	[0x3E] = rol_op(rmw_abs_x_op),
	[0x40] = rti_op(),
	[0x41] = eor_op(rd_x_ind_op),
	[0x45] = eor_op(rd_zp_op),
	[0x46] = lsr_op(rmw_zp_op),
	[0x48] = pushop("PHA", function(cpu) return cpu.a end),
	[0x49] = eor_op(rd_immediate_op),
	[0x4A] = lsr_op(rmw_impl_op),
	[0x4C] = jmp_abs_op(),
	[0x4D] = eor_op(rd_abs_op),
	[0x4E] = lsr_op(rmw_abs_op),
	[0x50] = branch_op("BVC", function(cpu) return not cpu.p.o end),
	[0x51] = eor_op(rd_ind_y_op),
	[0x55] = eor_op(rd_zp_x_op),
	[0x56] = lsr_op(rmw_zp_x_op),
	[0x58] = cli_op(),
	[0x59] = eor_op(rd_abs_y_op),
	[0x5D] = eor_op(rd_abs_x_op),
	[0x5E] = lsr_op(rmw_abs_x_op),
	[0x60] = rts_op(),
	[0x61] = adc_op(rd_x_ind_op),
	[0x65] = adc_op(rd_zp_op),
	[0x66] = ror_op(rmw_zp_op),
	[0x68] = pla_op(),
	[0x69] = adc_op(rmw_immediate_op),
	[0x6A] = ror_op(rmw_impl_op),
	[0x6C] = jmp_indirect_op(),
	[0x6D] = adc_op(rd_abs_op),
	[0x6E] = ror_op(rmw_abs_op),
	[0x70] = branch_op("BVS", function(cpu) return cpu.p.o end),
	[0x71] = adc_op(rd_ind_y_op),
	[0x75] = adc_op(rd_zp_x_op),
	[0x76] = ror_op(rmw_zp_x_op),
	[0x78] = sei_op(),
	[0x79] = adc_op(rd_abs_y_op),
	[0x7D] = adc_op(rd_abs_x_op),
	[0x7E] = ror_op(rmw_abs_x_op),
	[0x81] = sta_op(wr_x_ind_op),
	[0x84] = sty_op(wr_zp_op),
	[0x85] = sta_op(wr_zp_op),
	[0x86] = stx_op(wr_zp_op),
	[0x88] = dey_op(),
	[0x8A] = txa_op(),
	[0x8C] = sty_op(wr_abs_op),
	[0x8D] = sta_op(wr_abs_op),
	[0x8E] = stx_op(wr_abs_op),
	[0x90] = branch_op("BCC", function(cpu) return not cpu.p.c end),
	[0x91] = sta_op(wr_ind_y_op),
	[0x94] = sty_op(wr_zp_x_op),
	[0x95] = sta_op(wr_zp_x_op),
	[0x96] = stx_op(wr_zp_ind_op),
	[0x98] = tya_op(),
	[0x99] = sta_op(wr_abs_y_op),
	[0x9A] = txs_op(),
	[0x9D] = sta_op(wr_abs_x_op),
	[0xA0] = ldy_op(rd_immediate_op),
	[0xA1] = lda_op(rd_x_ind_op),
	[0xA2] = ldx_op(rd_immediate_op),
	[0xA4] = ldy_op(rd_zp_op),
	[0xA5] = lda_op(rd_zp_op),
	[0xA6] = ldx_op(rd_zp_op),
	[0xA8] = tay_op(),
	[0xA9] = lda_op(rd_immediate_op),
	[0xAA] = tax_op(),
	[0xAC] = ldy_op(rd_abs_op),
	[0xAD] = lda_op(rd_abs_op),
	[0xAE] = ldx_op(rd_abs_op),
	[0xB0] = branch_op("BCS", function(cpu) return cpu.p.c end),
	[0xB1] = lda_op(rd_ind_y_op),
	[0xB4] = ldy_op(rd_zp_x_op),
	[0xB5] = lda_op(rd_zp_x_op),
	[0xB6] = ldx_op(rd_zp_y_op),
	[0xB8] = clv_op(),
	[0xB9] = lda_op(rd_abs_y_op),
	[0xBA] = tsx_op(),
	[0xBC] = ldy_op(rd_abs_x_op),
	[0xBD] = lda_op(rd_abs_x_op),
	[0xBE] = ldx_op(rd_abs_y_op),
	[0xC0] = cpy_op(rd_immediate_op),
	[0xC1] = cmp_op(rd_x_ind_op),
	[0xC4] = cpy_op(rd_zp_op),
	[0xC5] = cmp_op(rd_zp_op),
	[0xC6] = dec_op(rmw_zp_op),
	[0xC8] = iny_op(),
	[0xC9] = cmp_op(rd_immediate_op),
	[0xCA] = dex_op(),
	[0xCC] = cpy_op(rd_abs_op),
	[0xCD] = cmp_op(rd_abs_op),
	[0xCE] = dec_op(rmw_abs_op),
	[0xD5] = cmp_op(rd_zp_x_op),
	[0xD9] = cmp_op(rd_abs_y_op),
	[0xDD] = cmp_op(rd_abs_x_op),
	[0xD0] = branch_op("BNE", function(cpu) return not cpu.p.z end),
	[0xD1] = cmp_op(rd_ind_y_op),
	[0xD6] = dec_op(rmw_zp_x_op),
	[0xD8] = cld_op(),
	[0xDE] = dec_op(rmw_abs_x_op),
	[0xE0] = cpx_op(rd_immediate_op),
	[0xE1] = sbc_op(rd_x_ind_op),
	[0xE4] = cpx_op(rd_zp_op),
	[0xE5] = sbc_op(rd_zp_op),
	[0xE6] = inc_op(rmw_zp_op),
	[0xE8] = inx_op(),
	[0xE9] = sbc_op(rmw_immediate_op),
	[0xEA] = nop_op(),
	[0xEC] = cpx_op(rd_abs_op),
	[0xED] = sbc_op(rd_abs_op),
	[0xEE] = inc_op(rmw_abs_op),
	[0xF0] = branch_op("BEQ", function(cpu) return cpu.p.z end),
	[0xF1] = sbc_op(rd_ind_y_op),
	[0xF5] = sbc_op(rd_zp_x_op),
	[0xF6] = inc_op(rmw_zp_x_op),
	[0xF8] = sed_op(),
	[0xF9] = sbc_op(rd_abs_y_op),
	[0xFD] = sbc_op(rd_abs_x_op),
	[0xFE] = inc_op(rmw_abs_x_op),
}

for i, op in pairs(INSTRUCTIONS_6502) do
	if op.adr == nil then
		print("WOHAAA BROKEN:", op.mnemonic)
		os.exit(1)
	end
end


-- Before brk: P=$00, stack = $00, $30 (00110000)
-- Entering interrupt: P=$04, stack = $00, $30, $05, $2e, $1e
-- After brk:  P=$0E, stack = $00, $30

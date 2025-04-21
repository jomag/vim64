require "utils"

Cpu6502 = {}

function Cpu6502:new()
	local cpu = {
		-- Accumulator register
		a = 0,

		-- Index registers
		x = 0,
		y = 0,

		-- Program Counter Register
		pc = 0xFFFC,

		-- Stack Pointer Register
		sp = 0,

		-- Processor Status Register
		-- Bit order: N O 1 B D I Z C
		p = {
			n = false,  -- Negative
			o = false,  -- Overflow
			d = false,  -- Decimal
			i = false,  -- Interrupt Disable
			z = false,  -- Zero
			c = false,  -- Carry
			ignored_bit = false, -- The ignored bit, for correct emu
		},

		-- Instruction Register
		-- Contains the opcode of the current instruction
		-- Special values: -1 = Interrupt sequence, -2 = NMI sequence
		ir = 0,

		-- Interrupt state (OLD! SEE BELOW)
		-- Valid values:
		--    "irq", "nmi", "brk",
		--    "irq_pending", "nmi_pending"
		int_state = nil,

		-- True if there is an interrupt pending to happen, which means
		-- the interrupt handler will be called when current operation
		-- has finished executing.
		int_pending = false,

		-- Vector for the interrupt currently being handled
		-- 0xFFFA/0xFFFB for NMI, 0xFFFE/0xFFFF for IRQ+BRK
		int_vector = nil,

		-- Address to the current operation (PC when IR was set)
		op_adr = nil,

		-- Time Control Unit
		-- Contains the subcycle of current instruction execution.
		-- Resets to zero for each new instruction.
		op_cycle = 0,

		-- Cycle count since reset
		cycle = 0,

		-- Equivalent to the read/write pin
		-- If true, the next half cycle will read from
		-- from bus into "data" (bus:get()).
		-- If false, the next half cycle will write
		-- "data" to bus (bus:set()).
		read = true,

		-- Bus address pins
		adr = 0,

		-- Bus data pins
		data = 0,

		-- Interrupt Request pin (input). True on interrupt request.
		irq = false,

		-- Non-Maskable Interrupt pin (input). Triggers
		-- interrupt on false-to-true edge.
		nmi = true,

		-- Set to true when NMI edge detected
		nmi_edge_detected = false,

		-- Previous state of NMI
		nmi_previous = true,

		-- Points at the instructions for this specific CPU
		instructions = INSTRUCTIONS_6502
	}

	setmetatable(cpu, self)
	Cpu6502.__index = Cpu6502
	return cpu
end

function Cpu6502:get_p()
	local p = 0

	-- FIXME: handle over types of interrupts
	-- TODO: make more efficient by setting B on state change instead
	--       of calculating it on every call to get_p() ...
	local b = 16
	if self.int_state ~= nil or self.int_pending then
		if not self.brk_contaminated then
			if self.int_pending then
				b = 0
			elseif self.int_state == "irq" and self.op_cycle < 5 then
				b = 0
			elseif self.int_state == "nmi" and self.op_cycle < 5 then
				b = 0
			end
		end
	end

	p = bit.bor(p, self.p.n and 128 or 0)
	p = bit.bor(p, self.p.o and 64 or 0)
	p = bit.bor(p, self.p.ignored_bit and 32 or 0)
	p = bit.bor(p, b)
	p = bit.bor(p, self.p.d and 8 or 0)
	p = bit.bor(p, self.p.i and 4 or 0)
	p = bit.bor(p, self.p.z and 2 or 0)
	p = bit.bor(p, self.p.c and 1 or 0)
	return p
end

function Cpu6502:set_p(v)
	self.p.n = bit.band(v, 128) ~= 0
	self.p.o = bit.band(v, 64) ~= 0
	self.p.d = bit.band(v, 8) ~= 0
	self.p.i = bit.band(v, 4) ~= 0
	self.p.z = bit.band(v, 2) ~= 0
	self.p.c = bit.band(v, 1) ~= 0
end

-- Perform subtraction and update flags accordingly
-- All values are treated as unsigned 8 bit integers
function Cpu6502:exec_sub(o1, o2)
	self.p.c = o1 >= o2
	self.p.z = o1 == o2
	self.p.n = bit7(o1 - o2)
	return bit.band(o1 - o2, 0xFF)
end

-- Update flags on load
function Cpu6502:exec_load(v)
	self.p.z = v == 0
	self.p.n = bit7(v)
	return v
end

function Cpu6502:reset_sequence(start_address, preload_data_hack)
	-- Reset sequence is not correctly emulated:
	-- It initializes all registers to their expected values
	-- after initial X cycles, so that it matches the
	-- 6502_functional_test.
	-- FIXME: Research and make it correct!
	self.a = 0xAA
	self.x = 0
	self.y = 0
	if start_address ~= nil then
		validate_u16(start_address)
		self.pc = start_address
	end
	self.sp = 0xBD
	self:prepare_op(0, start_address)
	self.op_cycle = 0
	self.cycle = 0
	self.adr = self.pc

	-- FIXME: this is a hack to kickstart the emu!
	self.data = preload_data_hack or 0

	self.a = 0
	self.x = 0xC0

	self.p.z = true
	self.p.i = true
end

function Cpu6502.format_state(self, style)
	if style == "visual6502" then
		return
	end

	local instr = self.instructions[self.ir]

	return string.format(
		"A:%02x X:%02x Y:%02x SP:%02x IR:%02x PC:%04x OP:%s P:%02x %s",
		self.a, self.x, self.y,
		self.sp, self.ir,
		self.pc,
		(instr and instr.mnemonic) or "-",
		self:get_p(),
		(self.read and "rd") or "wr")
end

function Cpu6502:format_internals()
	return string.format(
		"ADR:%02x DATA:%02x CYCLE:%d", self.adr, self.data, self.op_cycle)
end

function Cpu6502:step()
	self.cycle = self.cycle + 1

	local instr = self.instructions[self.ir]
	local instr_cycles = 1
	while instr[instr_cycles] ~= nil do
		instr_cycles = instr_cycles + 1
	end

	if self.op_cycle == 0 then
		self.brk_contaminated = self.data == 0
	end

	-- print("state: ", self.irq, self.int_state, self.p.i)
	if self.irq and self.int_state == nil and not self.p.i then
		self.int_pending = true
		if self.op_cycle == instr_cycles - 1 then
			self.int_state = "irq"
			self.int_pending = false
			self.int_vector = 0xFFFE
		end
	end

	if self.nmi ~= self.nmi_previous then
		if self.nmi then
			self.nmi_edge_detected = true
		end
		self.nmi_previous = self.nmi
	end

	if self.nmi_edge_detected and self.int_state == nil then
		self.int_pending = true
		self.int_vector = 0xFFFA

		if self.int_state == nil and self.op_cycle == instr_cycles - 1 then
			self.nmi_edge_detected = false
			self.int_state = "nmi"
			self.int_pending = false
			self.int_vector = 0xFFFA

			-- If BRK happens at the same time as NMI, the BRK
			-- operation will "contaminate" the B flag.
			-- https://www.nesdev.org/wiki/Visual6502wiki/6502_BRK_and_B_bit
			self.brk_contaminated = self.ir == 0
		end
	end

	if instr == nil then
		fatal("Unimplemented op: 0x%02x", self.ir)
		return
	end

	-- Hack to restore PC if interrupt triggered
	local pc_before = self.pc
	local adr_before = self.adr

	instr[self.op_cycle](self)

	if self.op_cycle == 1 and self.int_state ~= nil then
		if self.int_state == "irq" or self.int_state == "nmi" or self.int_state == "brk" then
			self.ir = 0
			self.pc = pc_before
			self.adr = adr_before
		end
	end
end

function Cpu6502:prepare_op(opcode, adr)
	self.ir = opcode
	self.op_adr = adr
end

require "cpu_6502_instr"

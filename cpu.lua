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
			b = false,  -- B-flag
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

		-- Time Control Unit
		-- Contains the subcycle of current instruction execution.
		-- Resets to zero for each new instruction.
		tcu = 0,

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

		-- Interrupt pin (input). True on interrupt.
		int = false,
	}

	setmetatable(cpu, self)
	Cpu6502.__index = Cpu6502
	return cpu
end

function Cpu6502:get_p()
	local p = 0
	p = bit.bor(p, self.p.n and 128 or 0)
	p = bit.bor(p, self.p.o and 64 or 0)
	p = bit.bor(p, self.p.ignored_bit and 32 or 0)
	p = bit.bor(p, self.p.b and 16 or 0)
	p = bit.bor(p, self.p.d and 8 or 0)
	p = bit.bor(p, self.p.i and 4 or 0)
	p = bit.bor(p, self.p.z and 2 or 0)
	p = bit.bor(p, self.p.c and 1 or 0)
	return p
end

function Cpu6502:set_p(v)
	self.p.n = bit.band(v, 128) ~= 0
	self.p.o = bit.band(v, 64) ~= 0
	self.p.b = bit.band(v, 16) ~= 0
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
	self.ir = 0
	self.tcu = 0
	self.cycle = 0
	self.adr = self.pc

	-- FIXME: this is a hack to kickstart the emu!
	self.data = preload_data_hack or 0

	self.a = 0
	self.x = 0xC0

	self.p.z = true
	self.p.i = true
	self.p.b = true
end

function Cpu6502.format_state(self, style)
	if style == "visual6502" then
		return
	end

	local instr = self.instructions[self.ir]

	-- print("A:", self.a)
	-- print("X:", self.x)
	-- print("Y:", self.y)

	return string.format(
		"A:%02x X:%02x Y:%02x SP:%02x IR:%02x PC:%04x OP:%s P:%02x %s",
		self.a, self.x, self.y,
		self.sp, self.ir,
		self.pc,
		(instr and instr.op) or "-",
		self:get_p(),
		(self.read and "rd") or "wr")
end

function Cpu6502:format_internals()
	return string.format(
		"ADR:%02x DATA:%02x TCU:%d", self.adr, self.data, self.tcu)
end

function Cpu6502:step()
	self.cycle = self.cycle + 1

	-- On interrupt, the CPU will wait until current instruction
	-- has finished before invoking the interrupt handler.
	-- TODO: handle the exception from this rule: the BRK instruction.
	--
	if self.int and self.p.i then
		print("INT still requesting, but I-flag high and tcu:", self.tcu, self.ir)
	end

	if self.int and not self.p.i and self.tcu == 1 then
		print("TRIGGER!")
		self.p.i = true
		self.p.b = false
		self.ir = -1
	end

	local instr = self.instructions[self.ir]
	if self.ir == -1 then
		instr = interrupt_sequence
	end

	if instr == nil then
		fatal("Unimplemented op: 0x%02x", self.ir)
		return
	end

	instr[self.tcu](self)
end

require "cpu_6502_instr"

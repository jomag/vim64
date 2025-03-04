require "utils"

Cpu6502 = {
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
		n = false,     -- Negative
		o = false,     -- Overflow
		b = false,     -- B-flag
		d = false,     -- Decimal
		i = false,     -- Interrupt Disable
		z = false,     -- Zero
		c = false,     -- Carry
		ignored_bit = false, -- The ignored bit, for correct emu
	},

	-- Instruction Register
	-- Contains the opcode of the current instruction
	ir = 0,

	-- Time Control Unit
	-- Contains the subcycle of current instruction execution.
	-- Resets to zero for each new instruction.
	tcu = 0,

	-- Predecode Register
	-- Contains the last byte read.
	-- This register is not accessible.
	pd = 0,

	-- Cycle count since reset
	cycle = 0,

	-- Equivalent to the read/write pin
	-- If true, the next half cycle will read from
	-- from bus into "data" (mem:get()).
	-- If false, the next half cycle will write
	-- "data" to bus (mem:set()).
	read = true,

	-- Bus address pins
	adr = 0,

	-- Bus data pins
	data = 0,
}

function Cpu6502:new(props)
	local cpu = setmetatable(props or {}, { __index = self })
	return cpu
end

function Cpu6502:get_p()
	local p = 0
	p = p | (self.p.n and 128 or 0)
	p = p | (self.p.o and 64 or 0)
	p = p | (self.p.ignored_bit and 32 or 0)
	p = p | (self.p.b and 16 or 0)
	p = p | (self.p.d and 8 or 0)
	p = p | (self.p.i and 4 or 0)
	p = p | (self.p.z and 2 or 0)
	p = p | (self.p.c and 1 or 0)
	return p
end

function Cpu6502:set_p(v)
	self.p.n = v & 128 ~= 0
	self.p.o = v & 64 ~= 0
	self.p.b = v & 16 ~= 0
	self.p.d = v & 8 ~= 0
	self.p.i = v & 4 ~= 0
	self.p.z = v & 2 ~= 0
	self.p.c = v & 1 ~= 0
end

-- Perform subtraction and update flags accordingly
-- All values are treated as unsigned 8 bit integers
function Cpu6502:exec_sub(o1, o2)
	self.p.c = o1 >= o2
	self.p.z = o1 == o2
	self.p.n = (o1 - o2) & 128 ~= 0
	return (o1 - o2) & 0xFF
end

-- Update flags on load
function Cpu6502:exec_load(v)
	self.p.z = v == 0
	self.p.n = v & 128 ~= 0
	return v
end

function Cpu6502:reset_sequence(mem, force_start_address)
	-- Reset sequence is not correctly emulated:
	-- It initializes all registers to their expected values
	-- after initial X cycles, so that it matches the
	-- 6502_functional_test.
	-- FIXME: Research and make it correct!
	self.a = 0xAA
	self.x = 0
	self.y = 0
	if force_start_address ~= nil then
		validate_u16(force_start_address)
		self.pc = force_start_address
	else
		self.pc = mem:get(0xFFFC) | (mem:get(0xFFFD) << 8)
	end
	self.sp = 0xBD
	self.ir = 0
	self.tcu = 0
	self.cycle = 0
	self.adr = self.pc
	self.data = 4

	self.a = 0
	self.x = 0xC0
	self.pd = mem:get(self.pc)

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

function Cpu6502:step(mem)
	print("\n\n--- Step: cycle " .. self.cycle)
	self.cycle = self.cycle + 1

	if self.read then
		self.data = mem:get(self.adr)
		printf(" - Bus state: adr: %04x, data (read): %02x\n", self.adr, self.data)
	else
		printf(" - Bus state: adr: %04x, data (write): %02x\n", self.adr, self.data)
		mem:set(self.adr, self.data)
	end

	local instr = self.instructions[self.ir]
	if instr == nil then
		fatal("Unimplemented op: 0x%02x", self.ir)
	end

	printf(" - Op execution state: %s, tcu %d\n", instr.op, self.tcu)

	instr[self.tcu](self)
end

-- Step a full cycle (two half-cycles)
function Cpu6502:step_x(mem) -- REMOVEME: stepping function
	-- that handled a lot of the timing and pc fiddling
	-- New implementation puts more responsibility on each instruction
	-- handler.
	self.cycle = self.cycle + 1

	if self.read then
		self.data = mem:get(self.adr)
		printf("New data read from %04x: %02x\n", self.adr, self.data)
	else
		printf("Data written to %04x: %02x\n", self.adr, self.data)
		mem:set(self.adr, self.data)
	end

	print("  --- TCU " .. tostring(self.tcu) .. " ---")

	if self.tcu == 0 then
		-- First cycle of next operation, which is
		-- also the last cycle of previous operation
		local instr = self.instructions[self.ir]

		instr[self.tcu](self)
		print("DOING TCU 0 FOR " .. instr.op)
		if self.read then
			self.tcu = 1
			self.adr = self.pc
			self.ir = self.data
		else
			self.tcu = 99
			self.adr = self.pc
			self.read = true
		end
	elseif self.tcu == 99 then
		self.pc = self.pc + 1
		self.adr = self.pc
		self.ir = self.data
		self.tcu = 1
	elseif self.tcu == 1 then
		-- Second cycle of current operation
		local instr = self.instructions[self.ir]
		if instr == nil then
			fatal("Unsupported instruction: 0x%02x\n", self.ir)
		end
		print("DOING TCU 1 FOR " .. instr.op)
		assert(instr[self.tcu] ~= nil)
		instr[self.tcu](self)
		if instr[2] == nil then
			self.tcu = 0
		else
			self.tcu = 2
		end
	elseif self.tcu == 2 then
		-- Third cycle of current operation
		local instr = self.instructions[self.ir]
		print("DOING TCU 2 FOR " .. instr.op)
		if instr == nil then
			fatal("Unsupported instruction: 0x%02x\n", self.ir)
		end
		assert(instr[self.tcu] ~= nil)
		instr[self.tcu](self)
		if instr[3] == nil then
			self.tcu = 0
		else
			self.tcu = 3
		end
	elseif self.tcu == 3 then
		-- Fourth cycle of current operation
		local instr = self.instructions[self.ir]
		if instr == nil then
			fatal("Unsupported instruction: 0x%02x\n", self.ir)
		end
		assert(instr[self.tcu] ~= nil)
		instr[self.tcu](self)
		if instr[4] == nil then
			self.adr = self.pc
			self.tcu = 0
		else
			self.tcu = 4
		end
	end
end

require "cpu_6502_instr"

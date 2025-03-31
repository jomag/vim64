Debugger = {}

function Debugger:new()
	local dbg = {
		stopped = false,
		breakpoints = {},
	}
	setmetatable(dbg, { __index = self })
	return dbg
end

function Debugger:break_at(adr)
	self.breakpoints[adr] = true
end

function Debugger:format_instruction_at(cpu, bus, adr)
	return ""
end

function Debugger:format_cpu_state(cpu)
	local s = ""
	s = s .. (
		"6502: A: %02x, X: %02x, Y: %02x\n"
	):format(cpu.a, cpu.x, cpu.y)

	s = s .. (
		"      P: %02x\n"
	):format(cpu:get_p())

	s = s .. (
		"      PC: %04x, SP: %02x\n"
	):format(cpu.pc, cpu.sp)

	s = s .. ("Bus: adr: %04x, data: %02x, op: %s\n"):format(
		cpu.adr, cpu.data, (cpu.read and "read") or "write"
	)

	return s
end

function Debugger:format_stack(cpu, bus)
	if cpu.sp == 0xFF then
		return "Stack: empty\n"
	end
	local s = "Stack:\n"
	local ptr = 0xFF
	while ptr > cpu.sp do
		local data = bus:inspect(ptr + 0x100)
		s = s .. ("  @%03x: %02x (%s)\n"):format(
			ptr + 0x100,
			data,
			format_bits(data)
		)
		ptr = ptr - 1
	end
	return s
end

function Debugger:prompt(cpu, bus)
	io.write(self:format_cpu_state(cpu))
	io.write(self:format_stack(cpu, bus))
	io.write("dbg> ")
	io.flush()
	local cmd = io.read()
	return cmd
end

function Debugger:update(cpu)
	if self.breakpoints[cpu.pc] then
		self.stopped = true
	end
end

function Debugger:stop()
	self.stopped = true
end

function Debugger:continue()
	self.stopped = false
end

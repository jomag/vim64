Debugger = {}

function Debugger:new()
	local dbg = {
		stopped = false,

		-- Number of cycles to execute before stopping
		-- It will decrement for every cycle until it
		-- reaches zero, and then it will be set to nil.
		-- Ignored if the value is nil.
		cycles_before_stopping = nil,

		-- Number of operations to execute before stopping
		-- It will decrement for every operation until it
		-- reaches zero, and then it will be set to nil.
		-- Ignored if the value is nil.
		ops_before_stopping = nil,

		breakpoints = {},
		max_width = 60
	}
	setmetatable(dbg, { __index = self })
	return dbg
end

function Debugger:break_at(adr)
	self.breakpoints[adr] = true
end

function Debugger:format_flags(cpu)
	local p = cpu:get_p()
	return ("%s%s%s%s%s%s%s%s"):format(
		(bit_set(p, 7) and "N") or "-",
		(bit_set(p, 6) and "V") or "-",
		(bit_set(p, 5) and "1") or "-",
		(bit_set(p, 4) and "B") or "-",
		(bit_set(p, 3) and "D") or "-",
		(bit_set(p, 2) and "I") or "-",
		(bit_set(p, 1) and "Z") or "-",
		(bit_set(p, 0) and "C") or "-"
	)
end

function Debugger:format_instruction_at(cpu, bus, adr, with_extras)
	local opcode = bus:inspect(adr)
	local instr = cpu.instructions[opcode]

	local operand = ""
	local extras = ""

	if instr.adr == ADR_IMMEDIATE then
		operand = ("#$%02X"):format(bus:inspect(adr + 1))
		extras = "immediate"
	elseif instr.adr == ADR_REL then
		local rel = byte_as_i8(bus:inspect(adr + 1)) + instr.len
		if rel == 0 then
			operand = "*"
		elseif rel >= 0 then
			operand = ("*+%d"):format(rel)
		else
			operand = ("*%d"):format(rel)
		end
		extras = ("abs: $%04X"):format(adr + rel)
	elseif instr.adr == ADR_ABS then
		local lo = bus:inspect(adr + 1)
		local hi = bus:inspect(adr + 2)
		operand = ("$%04X"):format(word(lo, hi))
	elseif instr.adr == ADR_ZP then
		local zp = bus:inspect(adr + 1)
		operand = ("$%02X"):format(zp)
		extras = ("zp, value at $%02X: %02X"):format(zp, bus:inspect(zp))
	elseif instr.adr == ADR_IMPL then
		operand = ""
		extras = ""
	elseif instr.adr == ADR_ABS_X then
		local lo = bus:inspect(adr + 1)
		local hi = bus:inspect(adr + 2)
		operand = ("$%04X,X"):format(word(lo, hi))
		local adr2 = word(lo, hi) + cpu.x
		extras = ("[$%04X] = $%02X"):format(adr2, bus:inspect(adr2))
	else
		operand = "???"
		extras = "fixme, adr mode: " .. instr.adr
	end

	if instr.regs then
		for _, reg in ipairs(instr.regs) do
			local val
			reg = string.upper(reg)
			if reg == "A" then
				val = cpu.a
			elseif reg == "X" then
				val = cpu.x
			elseif reg == "Y" then
				val = cpu.y
			elseif reg == "SP" then
				val = cpu.sp
			elseif reg == "P" then
				val = cpu:get_p()
			else
				val = nil
			end

			if val ~= nil then
				if #extras == 0 then
					extras = ("%s=$%X"):format(reg, val)
				else
					extras = ("%s, %s=$%X"):format(extras, reg, val)
				end
			end
		end
	end

	if #extras > 0 then
		extras = "\t\t; " .. extras
	end

	if not with_extras then
		extras = ""
	end

	return ("[$%04X]  %s\t%s%s"):format(adr, instr.mnemonic, operand, extras)
end

function Debugger:format_cpu_state(cpu)
	local s = ""
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

function Debugger:format_bus_status(cpu)
	local str = "Bus status:\n"
	str = str .. ("  Adr: $%04X   Data: $%02X   RW: %s\n"):format(cpu.adr, cpu.data, (cpu.read and "read") or "write")
	return str
end

function Debugger:format_rich(cpu, bus, event)
	local str = ""

	if event then
		local center = ("[ %s ]"):format(event)
		local l = math.floor((self.max_width - #center) / 2)
		local r = self.max_width - l - #center
		str = ("\n%s%s%s\n\n"):format(string.rep("─", l), center, string.rep("─", r))
	else
		str = "\n" .. string.rep("─", self.max_width) .. "\n\n"
	end

	str = str .. self:format_instruction_at(cpu, bus, cpu.op_adr, true) .. "\n\n"

	str = str .. ("Registers:\n")
	str = str ..
		("  PC: $%04X   A: $%02X   X: $%02X   Y: $%02X   SP: $%02X   P: %02X\n\n"):format(cpu.pc, cpu.a, cpu.x, cpu.y,
			cpu.sp, cpu:get_p())

	str = str .. ("Flags: %s   Cycle: %d   IR: $%02X\n\n"):format(self:format_flags(cpu), cpu.cycle, cpu.ir)

	str = str .. ("Half Cycle: %d   Int State: %s   Op cycle: %d\n"):format(cpu.cycle * 2, cpu.int_state, cpu.op_cycle)
	str = str .. ("Pins: IRQ: %s   NMI: %s\n\n"):format(tostring(cpu.irq), tostring(cpu.nmi))

	str = str .. self:format_stack(cpu, bus) .. "\n"

	str = str .. self:format_bus_status(cpu) .. "\n"

	str = str .. string.rep("─", self.max_width) .. "\n"
	return str
end

local function cmd_read(args, dbg, machine)
	local start = args[1]
	local count = args[2] or 1

	if count == 1 then
		local val = machine:inspect(start)
		print(("[$%04X] = %d = $%02x = 0b%s"):format(start, val, val, format_bits(val)))
	else
		print("FIXME: Reading range is not supported yet")
	end

	return true
end

local function cmd_step(args, dbg, machine)
	dbg:step(math.max(args[1] or 1, 1))
end

local function cmd_next(args, dbg, machine)
	dbg:next(math.max(args[1] or 1, 1))
end

local function cmd_continue(args, dbg, machine)
	dbg:continue()
end

local function cmd_list(args, dbg, machine)
	local n = 10
	local adr = machine.cpu.op_adr
	for i = 1, n do
		print(dbg:format_instruction_at(machine.cpu, machine, adr, adr == machine.cpu.op_adr))
		local opcode = machine:inspect(adr)
		local instr = machine.cpu.instructions[opcode]
		adr = adr + instr.len
	end
	return true
end

local function cmd_examine(args, dbg, machine)
	print(dbg:format_rich(machine.cpu, machine))
	return true
end

local function cmd_help(args, dbg, machine)
	print(dbg:format_usage())
	return true
end

local function cmd_add_breakpoint(args, dbg, machine)
	local adr = args[1]
	dbg:break_at(adr)
	return true
end

local commands = {
	{
		description = "Step one cycle",
		long = "step",
		short = "s",
		args = {
			{ name = "count", num = true, default = 1 }
		},
		fun = cmd_step,
	},
	{
		description = "Continue until next op",
		long = "next",
		short = "n",
		args = {
			{ name = "count", num = true, default = 1 }
		},
		fun = cmd_next,
	},
	{
		description = "Continue execution",
		long = "continue",
		short = "c",
		fun = cmd_continue,
	},
	{
		description = "List the next n operations",
		long = "list",
		short = "l",
		fun = cmd_list,
	},
	{
		description = "Print current state",
		long = "examine",
		short = "x",
		fun = cmd_examine,
	},
	{
		description = "Read from memory",
		long = "read",
		short = "r",
		args = {
			{ name = "adr",   num = true },
			{ name = "count", default = 1, num = true }
		},
		fun = cmd_read,
	},
	{
		description = "Display usage",
		long = "help",
		short = "?",
		fun = cmd_help,
	},
	{
		description = "Add breakpoint",
		long = "break",
		short = "b",
		args = {
			{ name = "adr", num = true },
		},
		fun = cmd_add_breakpoint,
	}
}

function Debugger:format_usage()
	local s = "Commands:\n"

	for i, doc in ipairs(commands) do
		local pre = ("%s, %s"):format(doc.short, doc.long)

		local args = ""
		for j, arg in ipairs(doc.args or {}) do
			local s = ("<%s>"):format(arg.name)
			if arg.default then
				s = "[" .. s .. "]"
			end
			args = args .. " " .. s
		end

		s = s .. ("  %s%s%s -- %s\n"):format(
			pre,
			args,
			string.rep(" ", 24 - #pre - #args),
			doc.description
		)
	end
	return s
end

function Debugger:handle_prompt_input(inp, machine)
	local cmdname, rest = inp:match("^(%S+)%s*(.*)$")

	local cmd = find(commands, function(c)
		return c.long == cmdname or c.short == cmdname
	end)

	if cmd == nil then
		print("Invalid command. Use '?' or 'help' to see usage")
		return true
	end

	local cmd_args = cmd.args or {}
	local args_raw = split(rest)

	if #args_raw > #cmd_args then
		print(("Command takes max %d arguments (%d given)"):format(#cmd_args, #args_raw))
		return true
	end

	local args = {}
	for i, meta in ipairs(cmd_args) do
		local val = args_raw[i]

		if val == nil then
			if meta.default ~= nil then
				val = meta.default
			else
				print(("Missing argument: %s"):format(meta.name))
				return true
			end
		else
			if meta.num then
				val = parse_number(val)
			end
		end

		table.insert(args, val)
	end

	return not not (cmd.fun)(args, self, machine)
end

function Debugger:prompt(cpu, machine)
	local loop = true

	while loop do
		loop = false
		io.write("dbg> ")
		io.flush()
		local inp = trim(io.read())

		if inp == "" then
			loop = true
		else
			loop = self:handle_prompt_input(inp, machine)
		end
	end
end

-- Update debugger state
-- This method should be called once every cycle
function Debugger:update(cpu, bus)
	if self.cycles_before_stopping ~= nil then
		if self.cycles_before_stopping == 0 then
			if cpu.op_cycle == 1 then
				print(self:format_instruction_at(cpu, bus, cpu.op_adr, true))
			end
			self:stop()
			self.cycles_before_stopping = nil
		else
			self.cycles_before_stopping = self.cycles_before_stopping - 1
		end
	end

	if cpu.op_cycle == 1 then
		if self.ops_before_stopping == 0 then
			print(self:format_instruction_at(cpu, bus, cpu.op_adr, true))
			self:stop()
			self.ops_before_stopping = nil
		elseif self.breakpoints[cpu.op_adr] then
			print(self:format_rich(cpu, bus, ("BREAKPOINT HIT @ $%04x"):format(cpu.op_adr)))
			self:stop()
		end

		if self.ops_before_stopping ~= nil then
			self.ops_before_stopping = self.ops_before_stopping - 1
		end
	end
end

function Debugger:stop()
	self.stopped = true
end

function Debugger:continue()
	self.stopped = false
	self.ops_before_stopping = nil
	self.cycles_before_stopping = nil
end

function Debugger:next(n)
	if n == nil then
		n = 1
	end
	self.stopped = false
	self.ops_before_stopping = math.max(n - 1, 0)
	self.cycles_before_stopping = nil
end

function Debugger:step(n)
	if n == nil then
		n = 1
	end
	print("STEPPING CYCLES", n)
	self.stopped = false
	self.cycles_before_stopping = math.max(n - 1, 0)
	self.ops_before_stopping = nil
end

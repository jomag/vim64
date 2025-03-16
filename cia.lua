-- References:
-- https://www.c64-wiki.com/wiki/CIA
-- https://sta.c64.org/cbm64mem.html
--
-- TODO:
-- Time-of-day functionality
-- Shift register
-- Count pulses on /CNT. Only phi2 pulses handled today (every step() invocation)

CIA = {
	chip_enabled    = false,

	port_a          = {
		-- For each bit, 0 = read, 1 = write		
		dir = 0,
		value = 0,
	},

	port_b          = {
		-- For each bit, 0 = read, 1 = write		
		dir = 0,
		value = 0,
	},

	timer_a         = {
		control = 0,
		start = 0,
		value = 0,
	},

	timer_b         = {
		control = 0,
		start = 0,
		value = 0,
	},

	int_control_reg = 0,
	int_status_reg  = 0
}

function CIA:set_int_status_reg(v)
	-- Bit 7 decides if bits should be turned off or on
	-- For all bits 0..6 that are set, the corresponding bit in the interrupt
	-- status register will be set to the same value as bit 7, the "fill bit".
	if bit_set(v, 7) then
		self.int_status_reg = bit.bor(self.int_status_reg, bit.band(v, 0x7F))
	else
		self.int_status_reg = bit.band(self.int_status_reg, bit.bnot(v))
	end
end

function CIA:get(adr)
	local function notimplemented(msg)
		local info = ("CIA: Not Implemented: %s (@%04X)\n"):format(msg, adr)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	adr = bit.band(adr, 0xF)

	if adr == 0x00 then
		print("Reading port A value")
		return self.port_a.value
	elseif adr == 0x0E then
		return self.timer_a.control
	else
		notimplemented("Invalid address")
	end
end

function CIA:set(adr, val)
	local function notimplemented(msg)
		local info = ("CIA: Not Implemented: %s (@%04X = %02X)\n"):format(msg, adr, val)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	adr = bit.band(adr, 0xF)

	if adr == 0x00 then
		print("Write port A", val)
		self.port_a.value = val
	elseif adr == 0x01 then
		print("Write port B", val)
		self.port_a.value = val
	elseif adr == 0x02 then
		self.port_a.dir = val
	elseif adr == 0x03 then
		self.port_b.dir = val
	elseif adr == 0x04 then
		print("Timer A start (lo)", val)
		self.timer_a.start = set_lo_byte(self.timer_a.start, val)
	elseif adr == 0x05 then
		print("Timer A start (hi)", val)
		self.timer_a.start = set_hi_byte(self.timer_a.start, val)
		if not bit_set(self.timer_a.control, 0) then
			self.timer_a.value = self.timer_a.start
		end
	elseif adr == 0x06 then
		print("Timer B start (lo)", val)
		self.timer_b.start = set_lo_byte(self.timer_b.start, val)
	elseif adr == 0x07 then
		print("Timer B start (hi)", val)
		self.timer_b.start = set_hi_byte(self.timer_b.start, val)
		if not bit_set(self.timer_b.control, 0) then
			self.timer_b.value = self.timer_b.start
		end
	elseif adr == 0x0D then
		self:set_int_status_reg(val)
	elseif adr == 0x0E then
		if bit_set(val, 4) then
			self.timer_a.value = self.timer_a.start
		end
		self.timer_a.control = bit.band(val, 0xEF)
		print(self:debug_print())
	elseif adr == 0x0F then
		if bit_set(val, 4) then
			self.timer_b.value = self.timer_b.start
		end
		self.timer_b.control = bit.band(val, 0xEF)
		print(self:debug_print())
	else
		notimplemented("Invalid address")
	end

	-- print("\nCIA status update after change:")
	-- print(self:debug_print())
end

function CIA:debug_print()
	local s = ""
	s = s .. "Port A:\n"
	s = s .. ("  Value: %02x (%s)\n"):format(self.port_a.value, format_bits(self.port_a.value))
	s = s .. ("  Dir:   %02x (%s)\n"):format(self.port_a.dir, format_bits(self.port_a.dir))
	s = s .. "Port B:\n"
	s = s .. ("  Value: %02x (%s)\n"):format(self.port_b.value, format_bits(self.port_b.value))
	s = s .. ("  Dir:   %02x (%s)\n"):format(self.port_b.dir, format_bits(self.port_b.dir))
	s = s .. "Timer A:\n"
	s = s .. ("  Start value: %04x\n"):format(self.timer_a.start)
	s = s .. ("  Value:       %04x\n"):format(self.timer_a.value)
	s = s .. ("  Control reg: %02x (%s)\n"):format(self.timer_a.control, format_bits(self.timer_a.control))
	s = s .. "Timer B:\n"
	s = s .. ("  Start value: %04x\n"):format(self.timer_b.start)
	s = s .. ("  Value:       %04x\n"):format(self.timer_b.value)
	s = s .. ("  Control reg: %02x (%s)\n"):format(self.timer_b.control, format_bits(self.timer_b.control))
	s = s .. ("Int control reg: %02x (%s)\n"):format(self.int_control_reg, format_bits(self.int_control_reg))
	s = s .. ("Int status reg:  %02x (%s)\n"):format(self.int_control_reg, format_bits(self.int_control_reg))
	return s
end

function CIA:new(props)
	local v = setmetatable(props or {}, { __index = self })
	return v
end

-- in_a, in_b: input state of port a and b
function CIA:step(in_a, in_b)
	in_a = bit.band(bit.bnot(self.port_a.dir), in_a)
	in_b = bit.band(bit.bnot(self.port_b.dir), in_b)

	if not bit_set(self.timer_a.control, 5) then
		if bit_set(self.timer_a.control, 0) then
			if self.timer_a.value == 0 then
				self.timer_a.value = self.timer_a.start
				if bit_set(self.timer_a.control, 4) then
					self.timer_a.running = false
				end
			else
				self.timer_a.value = self.timer_a.value - 1
			end
		end
	end

	if not bit_set(self.timer_b.control, 5) then
		if bit_set(self.timer_b.control, 0) then
			if self.timer_b.value == 0 then
				self.timer_b.value = self.timer_a.start
				if bit_set(self.timer_b.control, 4) then
					self.timer_b.running = false
				end
			else
				self.timer_b.value = self.timer_a.value - 1
			end
		end
	end
end

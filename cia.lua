-- References:
-- https://www.c64-wiki.com/wiki/CIA
-- https://sta.c64.org/cbm64mem.html
--
-- TODO:
-- Time-of-day functionality
-- Shift register
-- Count pulses on /CNT. Only phi2 pulses handled today (every step() invocation)

CIA = {
}

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
		return self:get_port_a()
	elseif adr == 0x01 then
		-- printf("Reading port B value: $%02X\n", self:get_port_b())
		return self:get_port_b()
	elseif adr == 0x0D then
		-- print("INT_DATA READ! Clearing INT_DATA and IRQ pin")
		local retval = self.int_data
		self.int_data = 0
		self.irq = false
		return retval
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
		self.port_a.output = val
	elseif adr == 0x01 then
		self.port_b.output = val
	elseif adr == 0x02 then
		if self.port_a.dir ~= val then
			printf("New DDR for PORTA: $%02X\n", val)
			self.port_a.dir = val
		end
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
		-- Bit 7 decides if bits should be turned off or on
		-- For all bits 0..6 that are set, the corresponding bit in the interrupt
		-- status register will be set to the same value as bit 7, the "fill bit".
		if bit_set(val, 7) then
			self.int_mask = bit.bor(self.int_mask, bit.band(val, 0x7F))
		else
			self.int_mask = bit.band(self.int_mask, bit.band(bit.bnot(val), 0x7F))
		end
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
	local pa = self:get_port_a()
	local pb = self:get_port_b()
	local s = ""
	s = s .. "Port A:\n"
	s = s .. ("  Value: %02x (%s)\n"):format(pa, format_bits(pa))
	s = s .. ("  Dir:   %02x (%s)\n"):format(self.port_a.dir, format_bits(self.port_a.dir))
	s = s .. "Port B:\n"
	s = s .. ("  Value: %02x (%s)\n"):format(pb, format_bits(pb))
	s = s .. ("  Dir:   %02x (%s)\n"):format(self.port_b.dir, format_bits(self.port_b.dir))
	s = s .. "Timer A:\n"
	s = s .. ("  Start value: %04x\n"):format(self.timer_a.start)
	s = s .. ("  Value:       %04x\n"):format(self.timer_a.value)
	s = s .. ("  Control reg: %02x (%s)\n"):format(self.timer_a.control, format_bits(self.timer_a.control))
	s = s .. "Timer B:\n"
	s = s .. ("  Start value: %04x\n"):format(self.timer_b.start)
	s = s .. ("  Value:       %04x\n"):format(self.timer_b.value)
	s = s .. ("  Control reg: %02x (%s)\n"):format(self.timer_b.control, format_bits(self.timer_b.control))
	s = s .. ("Int Mask: %02x (%s)\n"):format(self.int_mask, format_bits(self.int_mask))
	s = s .. ("Int Data: %02x (%s)\n"):format(self.int_data, format_bits(self.int_data))
	return s
end

function CIA:new(props)
	local v = setmetatable(props or {
		chip_enabled = false,

		port_a       = {
			-- For each bit: 0 = input, 1 = output
			dir = 0,
			input = 0xFF,
			output = 0
		},

		port_b       = {
			-- For each bit: 0 = input, 1 = output
			dir = 0,
			input = 0xFF,
			output = 0
		},

		timer_a      = {
			control = 0,
			start = 0,
			value = 0,
		},

		timer_b      = {
			control = 0,
			start = 0,
			value = 0,
		},

		-- Turns true on interrupt request (IRQ pin is reversed)
		irq          = false,
		int_mask     = 0,
		int_data     = 0
	}, { __index = self })
	return v
end

-- Returns the pin values of port A, depending on data direction of each pin
function CIA:get_port_a()
	return bit.bor(
		bit.band(self.port_a.output, self.port_a.dir),
		bit.band(self.port_a.input, bit.bnot(self.port_a.dir))
	)
end

-- Returns the pin values of port B, depending on data direction of each pin
function CIA:get_port_b()
	return bit.bor(
		bit.band(self.port_b.output, self.port_b.dir),
		bit.band(self.port_b.input, bit.bnot(self.port_b.dir))
	)
end

function CIA:step(adr, data, inp_a, inp_b)
	local retval = nil

	if adr ~= nil and data ~= nil then
		self:set(adr, data)
	end

	if adr ~= nil and data == nil then
		retval = self:get(adr)
	end

	if inp_a ~= nil then
		self.port_a.input = inp_a
	end

	if inp_b ~= nil then
		self.port_b.input = inp_b
	end

	if not bit_set(self.timer_a.control, 5) then
		if bit_set(self.timer_a.control, 0) then
			if self.timer_a.value == 0 then
				self.int_data = bit.bor(self.int_data, 1)
				if bit.band(self.int_mask, 1) == 0 then
					self.int_data = bit.bor(self.int_data, 0xFF)
				else
					self.int_data = bit.bor(self.int_data, 0x81)
					self.irq = true
				end

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
				self.int_data = bit.bor(self.int_data, 2)
				if bit.band(self.int_mask, 2) == 0 then
					self.int_data = bit.bor(self.int_data, 2)
				else
					self.int_data = bit.bor(self.int_data, 0x82)
					print("IRQ from CIA timer 2")
					self.irq = true
				end

				self.timer_b.value = self.timer_a.start
				if bit_set(self.timer_b.control, 4) then
					self.timer_b.running = false
				end
			else
				self.timer_b.value = self.timer_a.value - 1
			end
		end
	end

	return retval
end

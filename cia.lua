-- References:
-- https://www.c64-wiki.com/wiki/CIA
-- https://sta.c64.org/cbm64mem.html

CIA = {
	porta = {
		-- For each bit, 0 = read, 1 = write		
		dir = 0
	},

	portb = {
		-- For each bit, 0 = read, 1 = write		
		dir = 0
	},

	timer_a = {
		-- True if timer is currently running
		running = false,

		-- If true, underflow will be indicated on port B, bit 6
		underflow_bit_enabled = false,

		-- How the underflow bit will change on underflow:
		-- If true, underflow bit will be inverted
		-- If false, a positive edge will be made present on underflow bit
		invert_bit_on_underflow = 0,

		-- If true, the timer will restart on underflow
		restart = false,

		-- Mode for what will cause timer to increment
		-- 0: the timer will increment every cycle
		-- 1: the timer will increment on positive edge of CNT pin
		count_mode = 0,

		-- Direction of data on serial shift register
		-- False = read (input), True = write (output)
		serial_shift_dir = false,

		-- Interrupt on underflow
		underflow_enabled = false,

		-- Start value (16-bit)
		start_value = 0,

		-- Current value (16-bit)
		value = 0
	},

	timer_b = {
		-- True if timer is currently running
		running = false,

		-- If true, underflow will be indicated on port B, bit 7
		underflow_bit_enabled = false,

		-- How the underflow bit will change on underflow:
		-- If true, underflow bit will be inverted
		-- If false, a positive edge will be made present on underflow bit
		invert_bit_on_underflow = 0,

		-- If true, the timer will restart on underflow
		restart = false,

		-- Mode for what will cause timer to increment
		-- 0: the timer will increment every cycle
		-- 1: the timer will increment on positive edge of CNT pin
		-- 2: timer counts on underflow of timer A
		-- 3: timer counts on underflow of timer A along with positive edge on CNT pin
		count_mode = 0,

		-- Interrupt on underflow
		underflow_enabled = false,

		-- Start value
		start_value = 0,

		-- Current value
		value = 0
	},

	tod = {
		-- If true, writes to TOD register will set alarm time
		-- If false, it will set TOD
		write_to_alarm = false,

		-- Time-of-day speed (50 or 60)
		speed = 60,
	},

	-- Interrupt on time-of-day
	tod_enabled = false,

	-- Interrupt when data received on serial shift register
	rcv_int_enabled = false,

	-- Interrupt on positive edge on FLAG pin
	flag_int_enabled = false,

	-- Bit 0..5 sets if corresponding keyboard column is selected.
	-- 0 = selected, 1 = unselected
	keyboard_matrix_column = 0,

	-- Paddle selection (1 or 2)
	paddle_selection = 0,
}

function CIA:set_int_status_reg(v)
	local fill_bit = bit_set(v, 7)

	if fill_bit then
		if bit_set(v, 0) then self.timer_a.underflow_enabled = true end
		if bit_set(v, 1) then self.timer_b.underflow_enabled = true end
		if bit_set(v, 2) then self.tod_enabled = true end
		if bit_set(v, 3) then self.rcv_int_enabled = true end
		if bit_set(v, 4) then self.flag_int_enabled = true end
	else
		if not bit_set(v, 0) then self.timer_a.underflow_enabled = false end
		if not bit_set(v, 1) then self.timer_b.underflow_enabled = false end
		if not bit_set(v, 2) then self.tod_enabled = false end
		if not bit_set(v, 3) then self.rcv_int_enabled = false end
		if not bit_set(v, 4) then self.flag_int_enabled = false end
	end
end

function CIA:set_timer_a_control_reg(v)
	self.timer_a.running = bit_set(v, 0)
	self.timer_a.underflow_bit_enabled = bit_set(v, 1)
	self.timer_a.invert_bit_on_underflow = not bit_set(v, 2)
	self.timer_a.restart = not bit_set(v, 3)

	if bit_set(v, 4) then
		self.timer_a.value = self.timer_a.start_value
	end

	self.count_mode = (bit_set(v, 5) and 0) or 1
	self.serial_shift_dir = bit_set(v, 6)
	self.tod.speed = (bit_set(v, 7) and 50) or 60
end

function CIA:set_timer_b_control_reg(v)
	self.timer_b.running = bit_set(v, 0)
	self.timer_b.underflow_bit_enabled = bit_set(v, 1)
	self.timer_b.invert_bit_on_underflow = not bit_set(v, 2)
	self.timer_b.restart = not bit_set(v, 3)

	if bit_set(v, 4) then
		self.timer_b.value = self.timer_b.start_value
	end

	self.timer_b.count_mode = bit.band(bit.rshift(v, 5), 3)
	self.tod.write_to_alarm = bit_set(v, 7)
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

	notimplemented("Invalid address")
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

	if adr == 0x00 then
		self.keyboard_matrix_column = bit.band(val, 0x3F)
		self.paddle_selection = bit.rshift(val, 6)
	elseif adr == 0x02 then
		self.porta.dir = val
	elseif adr == 0x03 then
		self.portb.dir = val
	elseif adr == 0x04 then
		self.timer_a.value = set_lo_byte(self.timer_a.start_value, val)
	elseif adr == 0x05 then
		-- Note: there's a comment on the c64 wiki (see above) that the
		-- high byte will be reset as well, if timer is stopped.
		self.timer_a.value = set_hi_byte(self.timer_a.start_value, val)
	elseif adr == 0x06 then
		self.timer_b.value = set_lo_byte(self.timer_b.start_value, val)
	elseif adr == 0x07 then
		-- Note: there's a comment on the c64 wiki (see above) that the
		-- high byte will be reset as well, if timer is stopped.
		self.timer_b.value = set_hi_byte(self.timer_b.start_value, val)
	elseif adr == 0x0D then
		self:set_int_status_reg(val)
	elseif adr == 0x0E then
		self:set_timer_a_control_reg(val)
	elseif adr == 0x0F then
		self:set_timer_b_control_reg(val)
	else
		notimplemented("Invalid address")
	end
end

function CIA:step()
end

function CIA:new(props)
	local v = setmetatable(props or {}, { __index = self })
	return v
end

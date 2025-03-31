VIC_BANK = 0xDD00

VicII = {
	-- Horizontal raster scroll, screen width, multicolor
	screen_control_register_1 = 00,
	screen_control_register_2 = 0xC8,
	sprite_sprite_collision_reg = 0,
	sprite_bg_collision_reg = 0,
	border_color = 0,
	background_color = 0,
	sprite_extra_color1 = 0,
	sprite_extra_color2 = 0,
	extra_bg_color_1 = 0,
	extra_bg_color_2 = 0,
	extra_bg_color_3 = 0,
	sprite_double_width_reg = 0,
	sprite_multicolor_mode_reg = 0,
	sprites = {},
}

function VicII:get(adr)
	local function notimplemented(msg)
		local info = ("VicII: Not Implemented: %s (@%04X)\n"):format(msg, adr + 0xD000)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	print("ADR", adr)

	if adr >= 0 and adr <= 0xF then
		if adr % 2 == 0 then
			return self.sprites[adr / 2].x
		else
			return self.sprites[(adr - 1) / 2].y
		end
	elseif adr == 0x12 then
		-- Return current raster line
		return 0
	elseif adr == 0x16 then
		return self.screen_control_register_2
	elseif adr == 0x19 then
		-- Return interrupt status (raster line, collisions, etc)
		return 0
	else
		notimplemented("")
		return 0
	end
end

function VicII:set(adr, val)
	local function notimplemented(msg)
		local info = ("VicII: Not Implemented: %s (@%04X = %02X)\n"):format(msg, adr + 0xD000, val)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	if adr >= 0 and adr <= 0xF then
		if adr % 2 == 0 then
			self.sprites[adr / 2].x = bit.band(val, 0x7F)
		else
			self.sprites[(adr - 1) / 2].y = val
		end
	elseif adr == 0x10 then
		-- The 8'th bit of each sprites X coordinate!
		for i = 0, 7 do
			if bit_set(val, 0) then
				self.sprites[i].x = bit.bor(val, 0x80)
			else
				self.sprites[i].x = bit.band(val, 0x7F)
			end
		end
	elseif adr == 0x11 then
		self.screen_control_register_1 = val
	elseif adr == 0x12 then
		-- Raster line to generate interrupt at
		self.raster_line_for_int = val
	elseif adr == 0x13 or adr == 0x14 then
		-- Light pen coordinate. Read only.
	elseif adr == 0x15 then
		self.sprite_enable_register = val
	elseif adr == 0x16 then
		self.screen_control_register_2 = val
	elseif adr == 0x17 then
		self.sprite_double_height_reg = val
	elseif adr == 0x18 then
		self.memory_setup_reg = val
	elseif adr == 0x19 then
		self.int_status_reg = val
	elseif adr == 0x1A then
		self.int_control_reg = val
	elseif adr == 0x1B then
		self.sprite_priority_reg = val
	elseif adr == 0x1C then
		self.sprite_multicolor_mode_reg = val
	elseif adr == 0x1D then
		self.sprite_double_width_reg = val
	elseif adr == 0x1E then
		self.sprite_sprite_collision_reg = val
	elseif adr == 0x1F then
		self.sprite_bg_collision_reg = val
	elseif adr == 0x20 then
		self.border_color = val
	elseif adr == 0x21 then
		self.background_color = val
	elseif adr == 0x22 then
		self.extra_bg_color_1 = val
	elseif adr == 0x23 then
		self.extra_bg_color_2 = val
	elseif adr == 0x24 then
		self.extra_bg_color_3 = val
	elseif adr == 0x25 then
		self.sprite_extra_color_1 = val
	elseif adr == 0x26 then
		self.sprite_extra_color_2 = val
	elseif adr >= 0x27 and adr <= 0x2E then
		self.sprites[adr - 0x27].color = val
	else
		notimplemented("")
	end
end

-- adr is the local adress, if this device is selected (chip enabled)
-- data is 8-bit bus data for write operations, nil for read operations
function VicII:step(adr, data)
	if adr ~= nil then
		if data ~= nil then
			self:set(adr, data)
		else
			print("Should return something. Will return", self:get(adr))
			return self:get(adr)
		end
	end
end

function VicII:new(props)
	local v = setmetatable(props or {}, { __index = self })
	v.sprites = {
		[0] = { color = 0, x = 0, y = 0 },
		[1] = { color = 0, x = 0, y = 0 },
		[2] = { color = 0, x = 0, y = 0 },
		[3] = { color = 0, x = 0, y = 0 },
		[4] = { color = 0, x = 0, y = 0 },
		[5] = { color = 0, x = 0, y = 0 },
		[6] = { color = 0, x = 0, y = 0 },
		[7] = { color = 0, x = 0, y = 0 },
	}
	return v
end

-- Returns true if text mode, and false if bitmap mode
function VicII:is_text_mode()
	return bit_set(self.screen_control_register_1, 5)
end

function VicII:get_char_memory_ptr()
	if not self:is_text_mode() then
		fatal("can not get char mem offset in bitmap mode")
	end
	return bit.lshift(bit.band(self.memory_setup_reg, 0x7), 11)
end

-- Do a naive render of the whole screen
-- draw is a function with args: x, y, color
function VicII:naive_render(draw, c64)
	-- First fill all borders
	local c = self.border_color
	for y = 0, BORDER - 1 do
		for x = 0, WIDTH - 1 do
			draw(x, y, c)
			draw(x, BORDER + 200 + y, c)
		end
	end

	for y = BORDER, BORDER + 200 - 1 do
		for x = 0, BORDER - 1 do
			draw(x, y, c)
			draw(BORDER + 320 + x, y, c)
		end
	end

	-- 3C ..1111..
	-- 66 .11..11.
	-- 6E .11.111.
	-- 6E .11.111.
	-- 60 .11.....
	-- 62 .11...1.
	-- 3C ..1111..

	local bg = self.background_color
	-- local char_offset = 0xD000 -- self:get_char_memory_ptr()
	local char_offset = 0
	for cy = 0, 24 do
		for cx = 0, 39 do
			local fg = bit.band(c64.color_ram[cy * 40 + cx], 0xF)
			local char = c64:inspect_byte(0x400 + cy * 40 + cx)
			local ptr = char_offset + char * 8
			local x = cx * 8
			for y = 0, 7 do
				local row = c64.char_rom[ptr + y]

				if bit_set(row, 7) then
					draw(x + BORDER, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 6) then
					draw(x + BORDER + 1, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 1, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 5) then
					draw(x + BORDER + 2, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 2, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 4) then
					draw(x + BORDER + 3, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 3, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 3) then
					draw(x + BORDER + 4, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 4, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 2) then
					draw(x + BORDER + 5, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 5, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 1) then
					draw(x + BORDER + 6, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 6, y + BORDER + cy * 8, bg)
				end

				if bit_set(row, 0) then
					draw(x + BORDER + 7, y + BORDER + cy * 8, fg)
				else
					draw(x + BORDER + 7, y + BORDER + cy * 8, bg)
				end
			end
		end
	end
end

VicII = {
	-- Horizontal raster scroll, screen width, multicolor
	screen_control_register_1 = 0,
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
	sprite_priority_reg = 0,
	sprites = {},
}

function VicII:pet2ascii(pet)
	local conv_a = "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[$]?? !\"#$%&'()*+,-./0123456789:;<=>?"
	local conv_b = "@abcdefghijklmnopqrstuvwxyz[$]?? !\"#$%&'()*+,-./0123456789:;<=>?-ABCDEFGHIJKLMNOPQRSTUVWXYZ"

	local conv = (self:get_char_offset() == 0x1800 and conv_b) or conv_a

	local asc = conv:sub(pet + 1, pet + 1)
	if asc == nil or asc == "" then
		return " "
	else
		return asc
	end
end

function VicII:get(adr)
	if adr >= 0 and adr <= 0xF then
		if adr % 2 == 0 then
			return self.sprites[bit.rshift(adr, 1)].x
		else
			return self.sprites[bit.rshift(adr, 1)].y
		end
	elseif adr == 0x11 then
		return self.screen_control_register_1
	elseif adr == 0x12 then
		-- Return current raster line
		return 0
	elseif adr == 0x15 then
		return self.sprite_enable_register
	elseif adr == 0x16 then
		return self.screen_control_register_2
	elseif adr == 0x17 then
		return self.sprite_double_height_reg
	elseif adr == 0x18 then
		return self.memory_setup_reg
	elseif adr == 0x19 then
		-- Return interrupt status (raster line, collisions, etc)
		return 0
	elseif adr == 0x1B then
		return self.sprite_priority_reg
	elseif adr == 0x1C then
		return self.sprite_multicolor_mode_reg
	elseif adr == 0x1D then
		return self.sprite_double_width_reg
	elseif adr == 0x1E then
		return self.sprite_sprite_collision_reg
	elseif adr == 0x1F then
		return self.sprite_bg_collision_reg
	elseif adr == 0x20 then
		return self.border_color
	elseif adr == 0x21 then
		return self.background_color
	elseif adr == 0x25 then
		return self.sprite_extra_color_1
	elseif adr == 0x26 then
		return self.sprite_extra_color_2
	elseif adr >= 0x27 and adr <= 0x2E then
		return self.sprites[adr - 0x27].color
	else
		local info = ("VicII: Not Implemented: (@%04X)\n"):format(msg, adr + 0xD000)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
		return 0
	end
end

function VicII:get_screen_offset()
	return bit.band(bit.rshift(self.memory_setup_reg, 4), 0xF) * 0x400
end

function VicII:get_char_offset()
	if not self:is_text_mode() then
		print("can not get char mem offset in bitmap mode")
		return 0
	end
	return bit.band(bit.rshift(self.memory_setup_reg, 1), 7) * 0x800
end

function VicII:set(adr, val)
	if adr >= 0 and adr <= 0xF then
		if adr % 2 == 0 then
			self.sprites[bit.rshift(adr, 1)].x = bit.band(val, 0x7F)
		else
			self.sprites[bit.rshift(adr, 1)].y = val
		end
	elseif adr == 0x10 then
		-- The 8'th bit of each sprites X coordinate!
		for i = 0, 7 do
			if bit0(val) then
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
		local info = ("VicII: Not Implemented: %s (@%04X = %02X)\n"):format(msg, adr + 0xD000, val)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end
end

-- adr is the local adress, if this device is selected (chip enabled)
-- data is 8-bit bus data for write operations, nil for read operations
function VicII:step(adr, data)
	if adr ~= nil then
		if data ~= nil then
			self:set(adr, data)
		else
			return self:get(adr)
		end
	end
end

function VicII:new(props)
	local v = {
		memory_setup_reg = 0,
	}

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

	setmetatable(props or v, self)
	VicII.__index = VicII
	return v
end

-- Returns true if text mode, and false if bitmap mode
function VicII:is_text_mode()
	return not bit5(self.screen_control_register_1)
end

function VicII:naive_text_render(c64)
	local vic_bank = c64:get_vic_bank()
	local scr = self:get_screen_offset()
	local rows = {}
	for y = 0, 24 do
		row = {}
		for x = 0, 39 do
			local c = c64:inspect(vic_bank + scr + y * 40 + x)
			row[#row + 1] = self:pet2ascii(c)
		end
		rows[#rows + 1] = table.concat(row)
	end
	return rows
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

	local vic_bank = c64:get_vic_bank()
	local char_offset = self:get_char_offset()
	local scr = self:get_screen_offset()

	-- Memory references:
	-- https://www.c64-wiki.com/wiki/VIC_bank
	local use_char_rom = (vic_bank == 0 or vic_bank == 0x8000) and (char_offset == 0x1000 or char_offset == 0x1800)

	for cy = 0, 24 do
		for cx = 0, 39 do
			local fg = bit.band(c64.color_ram[cy * 40 + cx], 0xF)
			local char = c64:inspect(vic_bank + scr + cy * 40 + cx)
			-- printf("char: %x\n", char)
			local ptr = char_offset + char * 8
			local x = cx * 8
			for y = 0, 7 do
				local ptry = ptr + y

				local row
				if use_char_rom then
					row = c64.char_rom[char_offset + char * 8 + y - 0x1000]
				else
					row = c64:inspect(char * 8 + 0x9000 + y) -- vic_bank + ptry)
				end

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

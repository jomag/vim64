C64 = {}

function C64:new(props, kernal_path, basic_path, char_path)
	local ram = {}
	for i = 0, 65536 do
		ram[i] = 0
	end

	local color_ram = {}
	for i = 0, 1024 do
		color_ram[i] = 0
	end

	local c64 = setmetatable(props or {
		cpu = Cpu6502:new(),
		vic = VicII:new(),
		cia1 = CIA:new(),
		cia2 = CIA:new(),
		sid = SID:new(),
		ram = ram,
		color_ram = color_ram,
		kernal_rom = load_bin(kernal_path),
		basic_rom = load_bin(basic_path),
		char_rom = load_bin(char_path),
	}, { __index = self })

	c64.bank_a000_bfff = c64.ram
	c64.bank_d000_d3ff = c64.vic
	c64.bank_d400_d7ff = c64.sid
	c64.bank_d800_dbff = c64.color_ram
	c64.bank_dc00_dcff = c64.cia1
	c64.bank_dd00_ddff = c64.cia2
	c64.bank_e000_ffff = c64.kernal_rom
	return c64
end

function C64:inspect_byte(adr)
	local chip, chip_adr = self:update_bus(adr)
	if chip == self.ram or chip == self.kernal_rom or chip == self.basic_rom or chip == self.char_rom then
		return chip[chip_adr]
	end

	fatal("This bank does not support inspection yet: 0x%04x", adr)
end

function C64:update_bus(adr)
	if adr >= 0 and adr <= 0xFFF then
		return self.ram, adr
	elseif adr >= 0x1000 and adr <= 0x7FFF then
		return self.ram, adr
	elseif adr >= 0x8000 and adr <= 0x9FFF then
		return self.ram, adr
	elseif adr >= 0xA000 and adr <= 0xBFFF then
		return self.bank_a000_bfff, adr - 0xA000
	elseif adr >= 0xC000 and adr <= 0xCFFF then
		return self.ram, adr
	elseif adr >= 0xD000 and adr <= 0xD3FF then
		return self.bank_d000_d3ff, adr - 0xD000
	elseif adr >= 0xD400 and adr <= 0xD7FF then
		return self.bank_d400_d7ff, adr - 0xD400
	elseif adr >= 0xD800 and adr <= 0xDBE7 then
		return self.bank_d800_dbff, adr - 0xD800
	elseif adr >= 0xDC00 and adr <= 0xDCFF then
		return self.bank_dc00_dcff, adr - 0xDC00
	elseif adr >= 0xDD00 and adr <= 0xDDFF then
		return self.bank_dd00_ddff, adr - 0xDD00
	elseif adr >= 0xE000 and adr <= 0xFFFF then
		return self.bank_e000_ffff, adr - 0xE000
	else
		fatal("Access unimplemented address: 0x%04x", adr)
	end
end

function C64:step()
	self.cpu.int = self.cia1.irq or self.cia2.irq
	self.cpu:step()
	local chip, adr = self:update_bus(self.cpu.adr)

	if self.cpu.adr == 1 and not self.cpu.read then
		-- TODO: This is correct, as long as cartridge signals (GAME and EXROM) are
		-- not considered. See: https://www.c64-wiki.com/wiki/Bank_Switching
		local data = self.cpu.data
		local charen, hiram, loram = bit_set(data, 2), bit_set(data, 1), bit_set(data, 0)

		if hiram and loram then
			self.bank_a000_bfff = self.basic_rom
		else
			self.bank_a000_bfff = self.ram
		end

		if (not hiram) and (not loram) then
			self.bank_d000_d3ff = self.ram
			self.bank_d400_d7ff = self.ram
			self.bank_d800_dbff = self.ram
			self.bank_dc00_dcff = self.ram
			self.bank_dd00_ddff = self.ram
		elseif charen then
			self.bank_d000_d3ff = self.vic
			self.bank_d400_d7ff = self.sid
			self.bank_d800_dbff = self.color_ram
			self.bank_dc00_dcff = self.cia1
			self.bank_dd00_ddff = self.cia2
		else
			self.bank_d000_d3ff = self.char_rom
			self.bank_d400_d7ff = self.char_rom
			self.bank_d800_dbff = self.char_rom
			self.bank_dc00_dcff = self.char_rom
			self.bank_dd00_ddff = self.char_rom
		end

		if hiram then
			self.bank_e000_ffff = self.kernal_rom
		else
			self.bank_e000_ffff = self.ram
		end
	end

	if self.cpu.adr == 0x02A6 and self.cpu.read then
		-- PAL/NTSC switch. 0 = NTSC, 1 = PAL
		-- Temporary hack!
		self.cpu.data = 1
	end

	if chip == self.vic then
		if self.cpu.read then
			self.cpu.data = self.vic:step(adr)
		else
			self.vic:step(adr, self.cpu.data)
		end
	else
		self.vic:step()
	end

	if chip == self.cia1 then
		if self.cpu.read then
			self.cpu.data = self.cia1:step(adr)
		else
			self.cia1:step(adr, self.cpu.data)
		end
	else
		self.cia1:step()
	end

	if chip == self.cia2 then
		if self.cpu.read then
			self.cpu.data = self.cia2:step(adr)
		else
			self.cia2:step(adr, self.cpu.data)
		end
	else
		self.cia2:step()
	end

	if chip == self.sid then
		if self.cpu.read then
			self.cpu.data = self.sid:step(adr)
		else
			self.sid:step(adr, self.cpu.data)
		end
	else
		self.sid:step()
	end

	if chip == self.ram or chip == self.kernal_rom or chip == self.basic_rom or chip == self.char_rom or chip == self.color_ram then
		if self.cpu.read then
			self.cpu.data = chip[adr]
		else
			chip[adr] = self.cpu.data
		end
	end
end

C64 = {}

function C64:new(props, kernal_path, basic_path, char_path)
	local c64 = setmetatable(props or {
		cpu = Cpu6502:new(),
		bus = BusC64:new(),
		vic = VicII:new(),
		cia1 = CIA:new(),
		cia2 = CIA:new(),
		sid = SID:new(),
		ram = { 1, 2, 3 },
		kernal_rom = load_bin(kernal_path),
		basic_rom = load_bin(basic_path),
		char_rom = load_bin(char_path),
		bank_d000 = nil
	}, { __index = self })

	c64.bank_d000 = self.char
	return c64
end

function C64:update_bus(adr)
	if adr >= 0 and adr <= 0x200 then
		return self.ram, adr
	elseif adr >= 0x1000 and adr <= 0x7FFF then
		-- Note: in some modes, RAM in this page is not available
		return self.ram, adr
	elseif adr >= 0x8000 and adr <= 0x9FFF then
		-- Cartridge area
		return self.ram, adr
	elseif adr >= 0xA000 and adr <= 0xBFFF then
		return self.basic_rom, adr - 0xA000
	elseif adr >= 0xC000 and adr <= 0xCFFF then
		-- Note: in some modes, RAM in this page is not available
		return self.ram, adr
	elseif adr >= 0xD000 and adr <= 0xD3FF then
		return self.vic, adr - 0xD000
	elseif adr >= 0xD400 and adr <= 0xD7FF then
		return self.sid, adr - 0xD400
	elseif adr >= 0xD800 and adr <= 0xDBE7 then
		-- I'm not sure if this is stored in RAM or somewhere else
		-- Also, it says only bit 0..3 are used, but it's not clear
		-- if the remaining can be read/written.
		return self.ram, adr
	elseif adr >= 0xDC00 and adr <= 0xDCFF then
		return self.cia1, adr - 0xDC00
	elseif adr >= 0xDD00 and adr <= 0xDD00 then
		return self.cia2, adr - 0xDD00
	elseif adr >= 0xE000 and adr <= 0xFFFF then
		return self.kernal_rom, adr - 0xE000
	else
		fatal("Access unimplemented address: 0x%04x", adr)
	end
end

function C64:step()
	self.cpu:step()
	local chip, adr = self:update_bus(self.cpu.adr)

	if self.cpu.adr == 1 and not self.cpu.read then
		if bit_set(self.cpu.data, 2) then
			self.bank_d000 = self.vic
		else
			self.bank_d000 = self.char_rom
		end
	end

	if self.cpu.adr == 0x02A6 and self.cpu.read then
		-- PAL/NTSC switch. 0 = NTSC, 1 = PAL
		-- Temporary hack!
		self.cpu.data = 1
	end

	self.pla:step(self)

	self.cpu.data = the_new_data_fixme
end

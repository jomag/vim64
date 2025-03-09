require "bus"

BusC64 = {
	kernal = nil,
	basic = nil,
	video = {}
}
setmetatable(BusC64, { __index = Bus })

function BusC64:new(o)
	o = Bus:new(o or {
		kernal = nil,
		basic = nil,
		video = nil,
	})

	setmetatable(o, self)
	self.__index = self
	return o
end

function BusC64:load_kernal_rom(path)
	self.kernal = load_bin(path)
end

function BusC64:load_basic_rom(path)
	self.basic = load_bin(path)
end

function BusC64:load(path, adr)
	local bin = load_bin(path)
	if bin == nil then
		printf("Failed to load %s\n", path)
		return
	end

	for i, v in ipairs(bin) do
		self:set(adr + i - 1, v)
	end
end

function BusC64:get(adr)
	local function notimplemented(msg)
		local info = ("Not Implemented: %s (@%04X)\n"):format(msg, adr)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	local function unclear(msg)
		printf("Unclear implementation: %s (@%04X)\n", msg, adr)
	end

	if adr >= 0xD000 and adr <= 0xD3FF then
		return self.video:get(adr - 0xD000)
	end

	if adr >= 0xD400 and adr <= 0xD7FF then
		return self.sid:get(adr - 0xD400)
	end

	if adr >= 0xDC00 and adr <= 0xDCFF then
		return self.cia1:get(adr - 0xDC00)
	end

	if adr >= 0xDD00 and adr <= 0xDDFF then
		return self.cia2:get(adr - 0xDD00)
	end

	if adr >= 0xE000 and adr < 0x10000 then
		return self.kernal[adr - 0xE000 + 1]
	end

	if adr >= 0x8000 and adr < 0xA000 then
		-- Cartridge area
		return 0
	end

	if adr >= 0 and adr < 0x200 then
		-- Zero-page and stack
		return self.ram[adr]
	end

	if adr == 0x02A6 then
		-- PAL/NTSC switch. 0 = NTSC, 1 = PAL
		return 1
	end

	if adr == 0xDC0E then
		-- Timer A control register
		notimplemented("Timer A")
		return 0
	end

	if adr >= 0 and adr <= 0xFFF then
		return self.ram[adr]
	end

	if adr >= 0x1000 and adr <= 0x7FFF then
		-- Note: in some modes, RAM in this page is not available
		return self.ram[adr]
	end

	if adr >= 0xC000 and adr <= 0xCFFF then
		-- Note: in some modes, RAM in this page is not available
		return self.ram[adr]
	end

	if adr >= 0xD800 and adr <= 0xDBE7 then
		-- I'm not sure if this is stored in RAM or somewhere else
		-- Also, it says only bit 0..3 are used, but it's not clear
		-- if the remaining can be read/written.
		return self.ram[adr]
	end

	if adr == 0xDC00 then
		notimplemented("Port A, keyboard and joystick")
		return 0
	end

	if adr == 0xDC01 then
		notimplemented("Port B, keyboard and joystick")
		return 0
	end

	if adr == 0xDC0D then
		notimplemented("Interrupt status and control register")
		return 0
	end

	if adr >= 0xA000 and adr <= 0xBFFF then
		return self.basic[adr - 0xA000]
	end


	fatal(("GET 0x%04x: unimplemented memory range\n"):format(adr))
end

function BusC64:set(adr, val)
	local function notimplemented(msg)
		local info = ("Not Implemented: %s (@%04X = %02X)\n"):format(msg, adr, val)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	local function unclear(msg)
		printf("Unclear implementation: %s (@%04X=%02X)\n", msg, adr, val)
	end

	if adr >= 0xD000 and adr <= 0xD3FF then
		self.video:set(adr - 0xD000, val)
		return
	end

	if adr >= 0xD400 and adr <= 0xD7FF then
		self.sid:set(adr - 0xD400, val)
		return
	end

	if adr >= 0xDC00 and adr <= 0xDCFF then
		self.cia1:set(adr - 0xDC00, val)
		return
	end

	if adr >= 0xDD00 and adr <= 0xDDFF then
		self.cia2:set(adr - 0xDD00, val)
		return
	end

	if adr >= 0 and adr <= 0xFFF then
		if adr >= 0x400 and adr <= 0x7E7 then
			print(("WRITE TO SCREEN  %04x=%02x"):format(adr, val))
		end
		self.ram[adr] = val
		return
	end

	if adr >= 0x8000 and adr <= 0x9FFF then
		-- NOTE: Shared with cartridge memory!
		self.ram[adr] = val
		return
	end

	if adr >= 0x1000 and adr <= 0x7FFF then
		-- Note: in some modes, RAM in this page is not available
		self.ram[adr] = val
		return
	end

	if adr >= 0xC000 and adr <= 0xCFFF then
		-- Note: in some modes, RAM in this page is not available
		self.ram[adr] = val
		return
	end

	if adr >= 0xE000 and adr < 0x10000 then
		printf("Write to kernal ROM ignored (@%04x = %02x)\n", adr, val)
		return
	end

	if adr == 0xD016 then
		notimplemented("Screen Control Register #2")
		return
	end

	if adr == 0xDC0D then
		notimplemented("Interrupt control and status register")
		return
	end

	if adr == 0xDD0D then
		notimplemented("Interrupt control and status register")
		return
	end

	if adr == 0xDC00 then
		notimplemented("Port A, keyboard matrix and joystick #2")
		return
	end

	if adr == 0xDC0E or adr == 0xDD0E then
		notimplemented("Timer A control register")
		return
	end

	if adr == 0xDC0F or adr == 0xDD0F then
		notimplemented("Timer B control register")
		return
	end

	if adr == 0xDC03 or adr == 0xDD03 then
		notimplemented("Port B data direction register")
		return
	end

	if adr == 0xDC02 or adr == 0xDD02 then
		notimplemented("Port A data direction register")
		return
	end

	if adr == 0xD418 then
		notimplemented("Volume and filter modes")
		return
	end

	if adr == 0xDD00 then
		notimplemented("Port A serial bus access")
		return
	end

	if adr == 0xDC04 then
		notimplemented("Timer A set timer start value (lo)")
		return
	end
	if adr == 0xDC05 then
		notimplemented("Timer A set timer start value (hi)")
		return
	end

	if adr >= 0xFD30 and adr <= 0xFD4F then
		notimplemented("Unclear write to kernal area, hm?")
		return
	end

	if adr >= 0xD027 and adr <= 0xD02E then
		notimplemented("sprite color")
		return
	end

	if adr >= 0xD025 and adr <= 0xD026 then
		notimplemented("sprite extra color")
		return
	end

	if adr >= 0xD022 and adr <= 0xD024 then
		notimplemented("extra background color")
		return
	end

	if adr == 0xD021 then
		notimplemented("background color")
		return
	end

	if adr == 0xD020 then
		notimplemented("border color")
		return
	end

	if adr == 0xD01F then
		notimplemented("sprite-background collision register")
		return
	end

	if adr == 0xD01E then
		notimplemented("sprite-sprite collision register")
		return
	end

	if adr == 0xD01D then
		notimplemented("sprite double width register")
		return
	end

	if adr >= 0xD000 and adr < 0xD01D then
		notimplemented("VIC-II register")
		return
	end

	if adr >= 0xD800 and adr <= 0xDBE7 then
		-- I'm not sure if this is stored in RAM or somewhere else
		-- Also, it says only bit 0..3 are used, but it's not clear
		-- if the remaining can be read/written.
		self.ram[adr] = val
		return
	end

	fatal(("SET 0x%04x=%02x: unimplemented memory range\n"):format(adr, val))
end

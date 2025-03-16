require "bus"

BusC64 = {
	kernal = nil,
	basic = nil,
	char = nil,
	video = {}
}
setmetatable(BusC64, { __index = Bus })

function BusC64:new(o)
	o = Bus:new(o or {
		kernal = nil,
		basic = nil,
		video = nil,
		char = nil
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

function BusC64:load_char_rom(path)
	self.char = load_bin(path)
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

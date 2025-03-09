Bus = {
	ram = UNINITIALIZED
}

function Bus:new(o)
	o = o or {}
	o.ram = o.ram or {}

	if next(o.ram) == nil then
		for i = 0, 65535 do
			o.ram[i] = 0
		end
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

function Bus:get(adr)
	validate_u16(adr)
	return self.ram[adr]
end

function Bus:get_word(adr)
	return bit.bor(self:get(adr), bit.lshift(self:get(adr + 1), 8))
end

function Bus:get_wo_sideffects(adr)
	validate_u16(adr)
	return self.ram[adr]
end

function Bus:set(adr, val)
	validate_u8(val)
	self.ram[adr] = val
end

function Bus:pprint(start, len)
	if len == nil then
		len = 0x10000 - start
	end

	while len > 0 do
		local line = string.format("%04x:", start)
		for j = 0, 15 do
			line = line .. string.format(" %02x", self:get(start))
			if j == 7 then
				line = line .. " "
			end

			start = start + 1
			len = len - 1
			if len == 0 then
				break
			end
		end
		print(line)
	end
end

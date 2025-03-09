SID = {
	ignore_unimplemented = true
}

function SID:get(adr)
	local function notimplemented(msg)
		local info = ("SID: Not Implemented: %s (@%04X)\n"):format(msg, adr + 0xDC00)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end

	notimplemented()
	return 0
end

function SID:set(adr, val)
	local function notimplemented(msg)
		local info = ("SID: Not Implemented: %s (@%04X = %02X)\n"):format(msg, adr + 0xDC00, val)
		if self.ignore_unimplemented then
			print(info)
		else
			fatal(info)
		end
	end
	notimplemented()
end

function SID:step()
end

function SID:new(props)
	local v = setmetatable(props or {}, { __index = self })
	return v
end

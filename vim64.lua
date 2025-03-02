require "cpu"
require "utils"

local function memory_mapper_c64()
	local kernal = load_bin("kernal.901227-03.bin")

	local ram = {}
	for i = 0, 65536 do
		ram[i] = 0
	end

	local m = {
		get = function(adr)
			if adr >= 0xE000 and adr < 0x10000 then
				return kernal[adr - 0xE000 + 1]
			end
			return ram[adr]
		end,
		set = function(adr, val)
		end,
		ram = ram,
		kernal = kernal,
	}
	return m
end

local machine = {
	mem = memory_mapper_c64(),
	cpu = Cpu6502:new(),

	-- Emulate 1 clock cycle
	step = function(self)
		self.cpu:step(self)
	end
}

local function emulate(state, verbose, cycles)
	print("PC: " .. state.cpu.pc)
	-- for i = 0xFFF0, 0xFFFF do
	-- 	printf("%04x: %02x\n", i, machine.mem.get(i))
	-- end
	machine.cpu:reset_sequence(machine)
	while true do
		if cycles ~= nil and cycles >= state.cpu.cycle then
			break
		end

		-- printf("Cycle %d, TCU: %d\n", i - 1, machine.cpu.tcu)
		machine:step()
		if verbose then
			print(machine.cpu:format_state(style="visual6502")
		end
	end
end

-- emulate(machine)

-- Setup testing same as in Visual 6502
machine.pc = 0

-- JMP 0x0190
machine.ram[0] = 0x4C
machine.ram[1] = 0x90
machine.ram[2] = 0x01

-- LDX 0x31
machine.ram[0x190] = 0xA2
machine.ram[0x191] = 0x31

-- LDX 0x31
machine.ram[0x192] = 0xA2
machine.ram[0x193] = 0x46

-- ???
machine.ram[0x194] = 0xAD
machine.ram[0x195] = 0x70

emulate(machine, true, 10)

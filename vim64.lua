require "cpu"
require "utils"
require "mem_c64"
require "video"
require "cia"
require "sid"

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

local function emulate(machine, cycles)
	local mem = machine.mem
	local cpu = machine.cpu
	local cia1 = machine.cia1
	local cia2 = machine.cia2
	local video = machine.video
	local sid = machine.sid

	-- for i = 0xFFF0, 0xFFFF do
	-- 	printf("%04x: %02x\n", i, machine.mem.get(i))
	-- end

	cpu:reset_sequence(mem)

	while true do
		if cycles ~= nil and cycles <= cpu.cycle then
			print("Done!")
			break
		end

		-- printf("Cycle %d, TCU: %d\n", cpu.cycle, machine.cpu.tcu)
		-- printf("%s %s\n", cpu:format_state(), cpu:format_internals())
		cpu:step(mem)
		cia1:step()
		cia2:step()
		video:step()
	end
end

local machine = {
	cpu = Cpu6502:new(),
	mem = C64MemoryMapper:new(),
	video = VicII:new(),
	cia1 = CIA:new(),
	cia2 = CIA:new(),
	sid = SID:new(),
}

machine.mem:load_kernal_rom("kernal.901227-03.bin")
machine.mem:load_basic_rom("basic.901226-01.bin")
machine.mem.video = machine.video
machine.mem.cia1 = machine.cia1
machine.mem.cia2 = machine.cia2
machine.mem.sid = machine.sid
emulate(machine, 300000000)

local w = 40
for y = 0, 20 do
	for x = 0, w do
		printf("%s", string.char(machine.mem:get(0x400 + y * w + x)))
	end
	printf("\n")
end

for y = 0, 20 do
	for x = 0, w do
		printf("%x ", machine.mem:get(0x400 + y * w + x))
	end
	printf("\n")
end

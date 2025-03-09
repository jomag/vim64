require "cpu"
require "utils"
require "bus_c64"
require "video"
require "cia"
require "sid"

local function emulate(machine, cycles)
	local bus = machine.bus
	local cpu = machine.cpu
	local cia1 = machine.cia1
	local cia2 = machine.cia2
	local video = machine.video
	local sid = machine.sid

	cpu:reset_sequence(bus)

	while true do
		if cycles ~= nil and cycles <= cpu.cycle then
			print("Done!")
			break
		end

		local data
		if cpu.read then
			data = bus:get(cpu.adr)
		else
			data = cpu.data
			bus:set(cpu.dar, data)
		end

		-- printf("Cycle %d, TCU: %d\n", cpu.cycle, machine.cpu.tcu)
		-- printf("%s %s\n", cpu:format_state(), cpu:format_internals())
		cpu:step(data)
		cia1:step()
		cia2:step()
		video:step()
	end
end

local machine = {
	cpu = Cpu6502:new(),
	bus = BusC64:new(),
	video = VicII:new(),
	cia1 = CIA:new(),
	cia2 = CIA:new(),
	sid = SID:new(),
}

machine.bus:load_kernal_rom("kernal.901227-03.bin")
machine.bus:load_basic_rom("basic.901226-01.bin")
machine.bus.video = machine.video
machine.bus.cia1 = machine.cia1
machine.bus.cia2 = machine.cia2
machine.bus.sid = machine.sid
emulate(machine, 300000000)

local w = 40
for y = 0, 20 do
	for x = 0, w do
		printf("%s", string.char(machine.bus:get(0x400 + y * w + x)))
	end
	printf("\n")
end

for y = 0, 20 do
	for x = 0, w do
		printf("%x ", machine.bus:get(0x400 + y * w + x))
	end
	printf("\n")
end

require "cpu"
require "utils"
require "video"
require "cia"
require "sid"

local function cmd_print_stack(cpu, bus)
	printf("SP: %d (0x%02X)\n", cpu.sp, cpu.sp)
	printf("%d bytes on stack:\n", 0x200 - cpu.sp)
	local adr = 0xFF
	while adr > cpu.sp do
		printf("@%03X: %02x\n", 0x100 + adr, bus:get(0x100 + adr))
		adr = adr - 1
	end
end

local function emulate(machine, cycles, breakpoint)
	local bus = machine.bus
	local cpu = machine.cpu
	local cia1 = machine.cia1
	local cia2 = machine.cia2
	local video = machine.video
	local sid = machine.sid

	local step_debug = false

	cpu:reset_sequence(bus)

	while true do
		if cycles ~= nil and cycles <= cpu.cycle then
			print("Done!")
			break
		end

		if cpu.pc == breakpoint then
			step_debug = true
			print("Breakpoint reached!")
		end

		local data
		if cpu.read then
			data = bus:get(cpu.adr)
		else
			data = cpu.data
			bus:set(cpu.adr, data)
		end

		-- printf("Cycle %d, TCU: %d\n", cpu.cycle, machine.cpu.tcu)
		-- printf("%s %s\n", cpu:format_state(), cpu:format_internals())

		if step_debug then --  and cpu.tcu == 0 then
			printf("Cycle %d, OpCycle: %d\n", cpu.cycle, machine.cpu.op_cycle)
			printf("%s %s\n", cpu:format_state(), cpu:format_internals())

			while true do
				io.write("> ")
				local inp = io.read()
				if inp == "c" then
					print("Continuing...")
					step_debug = false
					break
				elseif inp == "stack" then
					cmd_print_stack(cpu, bus)
				elseif inp == "n" or inp == "" then
					break
				elseif inp:sub(1, 1) == "@" then
					local adr = tonumber(inp:sub(2), 16)
					print("Adr", adr)
					print("Data", bus:get(adr))
					printf("@%04X: %02X\n", adr, bus:get(adr))
				else
					print("Invalid input: " .. inp)
				end
			end
		end

		cpu:step(data)
		cia1:step(0, 0)
		cia2:step(0, 0)
		video:step()
		sid:step()
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
emulate(machine, 3000000000, nil)

-- Walkthrough of kernal:
-- https://gist.github.com/cbmeeks/4287745eab43e246ddc6bcbe96a48c19

local w = 40
for y = 0, 20 do
	for x = 0, w do
		printf("%s", pet2ascii(machine.bus:get(0x400 + y * w + x)))
	end
	printf("\n")
end

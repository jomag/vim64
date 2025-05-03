STEP_KEY = "n"
CONTINUE_KEY = "c"
BREAK_KEY = "b"

local numeric_prefix = ""
local grid = 8

function draw_textbox(x, y, w, h, text)
	love.graphics.setColor(0.5, 0.6, 0.9, 0.3)
	love.graphics.rectangle("fill", x * grid, y * grid, w * grid, h * grid, grid, grid)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(text, (x + 1) * grid, (y + 1) * grid)
end

function format_cia(name, cia)
	local txt =
	"-- %s --\nINT MASK: %s\nINT DATA: %s\n\n-- TIMER A --\nVALUE: %04x\nSTART: %04x\n\n-- TIMER B --\nVALUE: %04x\nSTART: %04x\n\n-- PORT A+B --\nPA: %02X\nPB: %02X\nDDRA: %02X\nDDRB: %02X"

	return txt:format(
		name,
		format_bits(cia.int_mask),
		format_bits(cia.int_data),
		cia.timer_a.value,
		cia.timer_a.start,
		cia.timer_b.value,
		cia.timer_b.start,
		cia:get_port_a(),
		cia:get_port_b(),
		cia.port_a.dir,
		cia.port_b.dir
	)
end

function format_vic()
	local vic = STATE.machine.vic
	local c64 = STATE.machine

	local txt =
	"-- VIC-II --\nBANK: %04x\nCHAR: %04x\nSCR:  %04x\n"

	return txt:format(
		c64:get_vic_bank(),
		vic:get_char_offset(),
		vic:get_screen_offset()
	)
end

function draw_inspector()
	local w, h = love.graphics.getDimensions()
	local m = 8

	local cpu = STATE.machine.cpu
	local cia1 = STATE.machine.cia1
	local cia2 = STATE.machine.cia2

	local cpu_stats = ("-- CPU --\nA:    %02x\nX:    %02x\nY:    %02x\nPC:   %04x\nSP:   1%02x\nP:    %02x\nADR:  %04x\nDATA: %02x %s\n\nCYCLE: %d")
		:format(cpu.a, cpu.x, cpu.y, cpu.pc, cpu.sp, cpu:get_p(), cpu.adr, cpu.data, (cpu.read and "RD") or "WR",
			cpu.cycle)

	draw_textbox(1, 1, 16, 32, cpu_stats)

	draw_textbox(18, 1, 20, 18, format_cia("CIA1", cia1))
	draw_textbox(18, 20, 20, 18, format_cia("CIA2", cia2))

	draw_textbox(39, 1, 20, 18, format_vic())

	if numeric_prefix ~= "" then
		local tw = 8 * #numeric_prefix
		draw_textbox(w - m - m - tw, m, w + m + m, 8 * 3, numeric_prefix)
	end
end

function inspector_keypress(key)
	if is_digit(key) then
		numeric_prefix = numeric_prefix .. key
		return
	end

	if key == STEP_KEY then
		if numeric_prefix == "" then
			step(1)
		else
			step(tonumber(numeric_prefix))
		end
	elseif key == CONTINUE_KEY then
		STATE.paused = false
	elseif key == BREAK_KEY then
		STATE.paused = true
	end

	numeric_prefix = ""
end

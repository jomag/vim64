STEP_KEY = "n"
CONTINUE_KEY = "c"
BREAK_KEY = "b"

local numeric_prefix = ""

function draw_textbox(x, y, w, h, text)
	love.graphics.setColor(0.5, 0.6, 0.9, 0.3)
	love.graphics.rectangle("fill", x, y, w, h, 8, 8)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(text, x + 8, y + 8)
end

function draw_inspector()
	local w, h = love.graphics.getDimensions()
	local m = 8

	local cpu = STATE.cpu

	local cpu_stats = ("-- CPU --\nA:    %02x\nX:    %02x\nY:    %02x\nPC:   %04x\nSP:   1%02x\nP:    %02x\nADR:  %04x\nDATA: %02x %s\n\nCYCLE: %d")
		:format(cpu.a, cpu.x, cpu.y, cpu.pc, cpu.sp, cpu:get_p(), cpu.adr, cpu.data, (cpu.read and "RD") or "WR",
			cpu.cycle)

	draw_textbox(m, m, 16 * 8, h - m - m, cpu_stats)

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

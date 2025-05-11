require "cpu"
require "cia"
require "sid"
require "video"
require "keyboard"
require "c64"

require "inspector"

BORDER = 40
WIDTH = 320 + BORDER + BORDER
HEIGHT = 200 + BORDER + BORDER

STATE = {
	-- If true, the emulation is paused
	paused = false,

	-- If true, the inspection (debugger) view is visible
	inspection = false,

	-- The C64 machine instance
	machine = nil
}

-- Love wants color values as float point (0..1)
FP_COLORS = {
	[0] = { 0x00 / 0xFF, 0x00 / 0xFF, 0x00 / 0xFF },
	[1] = { 0xFF / 0xFF, 0xFF / 0xFF, 0xFF / 0xFF },
	[2] = { 0x88 / 0xFF, 0x00 / 0xFF, 0x00 / 0xFF },
	[3] = { 0xAA / 0xFF, 0xFF / 0xFF, 0xEE / 0xFF },
	[4] = { 0xCC / 0xFF, 0x44 / 0xFF, 0xCC / 0xFF },
	[5] = { 0x00 / 0xFF, 0xCC / 0xFF, 0x55 / 0xFF },
	[6] = { 0x00 / 0xFF, 0x00 / 0xFF, 0xAA / 0xFF },
	[7] = { 0xEE / 0xFF, 0xEE / 0xFF, 0x77 / 0xFF },
	[8] = { 0xDD / 0xFF, 0x88 / 0xFF, 0x55 / 0xFF },
	[9] = { 0x66 / 0xFF, 0x44 / 0xFF, 0x00 / 0xFF },
	[10] = { 0xFF / 0xFF, 0x77 / 0xFF, 0x77 / 0xFF },
	[11] = { 0x33 / 0xFF, 0x33 / 0xFF, 0x33 / 0xFF },
	[12] = { 0x77 / 0xFF, 0x77 / 0xFF, 0x77 / 0xFF },
	[13] = { 0xAA / 0xFF, 0xFF / 0xFF, 0x66 / 0xFF },
	[14] = { 0x00 / 0xFF, 0x88 / 0xFF, 0xFF / 0xFF },
	[15] = { 0xBB / 0xFF, 0xBB / 0xFF, 0xBB / 0xFF }
}

function love.draw()
	local w, h = love.graphics.getDimensions()

	STATE.buf_image:replacePixels(STATE.buf)

	if not STATE.inspection then
		love.graphics.draw(STATE.buf_image, 0, 0, 0, 2, 2)
		love.graphics.print("CURRENT FPS: " .. tostring(love.timer.getFPS()), 10, 10)
	end

	if STATE.inspection then
		if STATE.tint_background then
			love.graphics.setColor(0, 0, 0, 0.8) -- 50% opaque black
			love.graphics.rectangle("fill", 0, 0, w, h)
		end
		love.graphics.setColor(1, 1, 1, 1)
		draw_inspector()
	end
end

local love2d_to_c64_key = {
	a = 'a',
	b = 'b',
	c = 'c',
	d = 'd',
	e = 'e',
	f = 'f',
	g = 'g',
	h = 'h',
	i = 'i',
	j = 'j',
	k = 'k',
	l = 'l',
	m = 'm',
	n = 'n',
	o = 'o',
	p = 'p',
	q = 'q',
	r = 'r',
	s = 's',
	t = 't',
	u = 'u',
	v = 'v',
	w = 'w',
	x = 'x',
	y = 'y',
	z = 'z',
	['0'] = 'key_0',
	['1'] = 'key_1',
	['2'] = 'key_2',
	['3'] = 'key_3',
	['4'] = 'key_4',
	['5'] = 'key_5',
	['6'] = 'key_6',
	['7'] = 'key_7',
	['8'] = 'key_8',
	['9'] = 'key_9',
	space = 'key_space',
	['return'] = 'key_return',
	rshift = 'key_right_shift',
	lshift = 'key_left_shift',
	rctrl = 'key_control',
	lctrl = 'key_control',
	escape = 'key_run_stop',
	['\\'] = 'key_equal',
	['.'] = 'key_period',
	[','] = 'key_comma',
	['-'] = 'key_plus',
	[';'] = 'key_semicolon'
}

function love.keypressed(key)
	if key == "f10" then
		STATE.inspection = not STATE.inspection
		STATE.paused = STATE.inspection
	elseif STATE.inspection then
		inspector_keypress(key)
	else
		local c64_key = love2d_to_c64_key[key]
		if c64_key ~= nil then
			STATE.machine.keyboard:key_down(c64_key)
		end
	end
end

function love.keyreleased(key)
	if STATE.inspection then
	else
		local c64_key = love2d_to_c64_key[key]
		if c64_key ~= nil then
			STATE.machine.keyboard:key_up(c64_key)
		end
	end
end

function generate_c64_font()
	local chars = "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[_]__ !\"#$%&'()*+,-./0123456789:;<=>?"
	local bmp = load_bin("characters.325018-02.bin")
	if bmp == nil then
		print("Failed to load character ROM")
		return
	end
	local w = #chars * (8 + 2)
	local h = 8
	local img = love.image.newImageData(w, h)
	img:mapPixel(function() return 1, 0, 0, 1 end)

	local x = 2
	for n = 0, #chars - 1 do
		local offs = n * 8
		for y = 0, 7 do
			local row = bmp[offs]
			for b = 0, 7 do
				if bit.band(row, bit.lshift(1, 7 - b)) == 0 then
					img:setPixel(x + b, y, 0, 0, 0, 0)
				else
					img:setPixel(x + b, y, 1, 1, 1, 1)
				end
			end
			offs = offs + 1
		end
		x = x + 10
	end

	return love.graphics.newImageFont(img, chars)
end

function print_usage(quit)
	print("Usage: vim64 [--help] [filename.prg]")
	if quit then
		love.event.quit(true)
	end
end

function love.load(args)
	local prg_file = nil

	for i = 1, #args do
		local arg = args[i]
		if arg == "--help" or arg == "-h" then
			print_usage(true)
			return
		elseif arg:match("%.prg$") then
			if prg_file ~= nil then
				print("Max one prg file can be loaded")
				print_usage(true)
				return
			end
			prg_file = arg
		end
	end

	STATE.machine = C64:new(nil, "kernal.901227-03.bin", "basic.901226-01.bin", "characters.325018-02.bin")

	print("Setting up rendering engine...")
	STATE.buf = love.image.newImageData(WIDTH, HEIGHT)
	STATE.buf_image = love.graphics.newImage(STATE.buf)
	STATE.buf_image:setFilter("nearest", "nearest")

	love.window.setVSync(0)

	if prg_file then
		STATE.machine:load_prg(prg_file)
	end

	print("Resetting machine...")
	local start_adr = word(
		STATE.machine:inspect(0xFFFC),
		STATE.machine:inspect(0xFFFD)
	)
	STATE.machine.cpu:reset_sequence(
		start_adr,
		STATE.machine:inspect(start_adr)
	)

	print("Generating font...")
	local font = generate_c64_font();
	love.graphics.setFont(font)

	print("Ready!")
end

function step(count)
	for i = 1, count do
		STATE.machine:step()
	end
end

function love.update()
	if STATE.paused then
		return
	end

	step(16667)

	STATE.machine.vic:naive_render(function(x, y, c)
		local cc = FP_COLORS[c]
		STATE.buf:setPixel(x, y, cc[1], cc[2], cc[3], 1)
	end, STATE.machine)
end

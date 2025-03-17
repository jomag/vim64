require "cpu"
require "cia"
require "sid"
require "video"
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

COLORS = {
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

function love.keypressed(key)
	if key == "f10" then
		STATE.inspection = not STATE.inspection
		STATE.paused = STATE.inspection
	elseif STATE.inspection then
		inspector_keypress(key)
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

function love.load()
	STATE.machine = C64:new(nil, "kernal.901227-03.bin", "basic.901226-01.bin", "characters.325018-02.bin")

	print("Setting up rendering engine...")
	STATE.buf = love.image.newImageData(WIDTH, HEIGHT)
	STATE.buf_image = love.graphics.newImage(STATE.buf)
	STATE.buf_image:setFilter("nearest", "nearest")

	print("Resetting machine...")
	STATE.machine.cpu:reset_sequence(
		STATE.bus,
		word(
			STATE.machine:inspect_byte(0xFFFC),
			STATE.machine:inspect_byte(0xFFFD)
		)
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
		local cc = COLORS[c]
		STATE.buf:setPixel(x, y, cc[1], cc[2], cc[3], 1)
	end, STATE.machine)
end

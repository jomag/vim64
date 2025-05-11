require "cpu"
require "cia"
require "sid"
require "video"
require "keyboard"
require "c64"

local ns = vim.api.nvim_create_namespace("vim64")

for fg, a in pairs(C64_COLORS) do
	for bg, b in pairs(C64_COLORS) do
		local aa = ("#%02X%02X%02X"):format(a[1], a[2], a[3])
		local bb = ("#%02X%02X%02X"):format(b[1], b[2], b[3])
		vim.cmd(("highlight c64_%d_%d guifg=%s guibg=%s"):format(fg, bg, aa, bb))
	end
end

local function count_table_size(tbl, seen)
	seen = seen or {}
	if seen[tbl] then return 0 end
	seen[tbl] = true

	local size = 0
	for k, v in pairs(tbl) do
		if type(k) == "table" then
			size = size + count_table_size(k, seen)
		end
		if type(v) == "table" then
			size = size + count_table_size(v, seen)
		end
	end

	-- Add size of the table itself (arbitrary, for comparison only)
	size = size + 1

	return size
end

function render(machine, buf)
	local lines = machine.vic:naive_text_render(machine)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	local bg = machine.vic.background_color

	local w = 40
	local h = 24

	for y = 0, h do
		local x = 0
		local prev_x = 0
		local prev_fg = nil
		while x < w do
			local fg = machine.color_ram[y * w + x]
			if fg == nil then
				fatal("BORKED")
			end
			if fg ~= prev_fg then
				if prev_fg ~= nil then
					-- vim.api.nvim_buf_add_highlight(buf, ns, ("c64_%d_%d"):format(prev_fg, bg), y, prev_x, x)
				end
				prev_fg = fg
				prev_x = x
			end
			x = x + 1
		end

		vim.api.nvim_buf_add_highlight(buf, ns, ("c64_%d_%d"):format(prev_fg, bg), y, prev_x, x)
	end

	vim.api.nvim_buf_set_lines(buf, 25, 26, false, {
		("---    Tbl Wegiht: %d    --- "):format(collectgarbage("count"))
	})
	-- collectgarbage("collect")
end

function update(machine)
	for i = 1, 16667 do
		machine:step()
	end

	if machine.updates_since_key_down < 5 then
		machine.updates_since_key_down = machine.updates_since_key_down + 1
	else
		machine.keyboard:release_all()
	end
end

function handle_key(key, machine)
	local transl = {
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
		[' '] = 'key_space',
		["<CR>"] = 'key_return',
	}

	machine.updates_since_key_down = 0
	machine.keyboard:key_down(transl[key] or key)
end

function setup_keyboard(machine)
	-- General function to set mappings
	local function set_global_keymap(key)
		-- Map the key in normal, insert, and command-line modes
		vim.keymap.set('n', key, function()
			handle_key(key, machine)
		end, { noremap = true, silent = true })

		vim.keymap.set('i', key, function()
			handle_key(key, machine)
			-- To prevent entering insert mode, we'll simulate a return to normal mode
			-- You may want to handle special cases like 'Esc' if needed
			return "<Esc>"
		end, { noremap = true, silent = true })

		-- vim.keymap.set('c', key, function()
		-- handle_key(key, machine)
		-- end, { noremap = true, silent = true })
	end

	-- Example: Listen for all key presses and prevent entering insert mode
	-- List the keys you'd like to intercept (all alphanumeric keys, for example)
	for _, key in ipairs({ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '<CR>', ' ' }) do
		set_global_keymap(key)
	end
end

function setup()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
	vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	vim.api.nvim_win_set_buf(0, buf)

	local machine = C64:new(nil, "kernal.901227-03.bin", "basic.901226-01.bin", "characters.325018-02.bin")

	machine.updates_since_key_down = 0

	local prg_file = "software/64-doctor87.prg"
	if prg_file then
		machine:load_prg(prg_file)
	end

	-- Reset machine
	local start_adr = word(
		machine:inspect(0xFFFC),
		machine:inspect(0xFFFD)
	)

	machine.cpu:reset_sequence(
		start_adr,
		machine:inspect(start_adr)
	)

	setup_keyboard(machine)

	local wrap = vim.schedule_wrap(function()
		update(machine)
		vim.api.nvim_buf_set_option(buf, 'modifiable', true)
		render(machine, buf)
		vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	end)

	local timer = vim.loop.new_timer()
	timer:start(0, 16, wrap)
end

setup()

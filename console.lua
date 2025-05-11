local ffi = require("ffi")

require "cpu"
require "cia"
require "sid"
require "video"
require "keyboard"
require "c64"

-- local profile = require("jit.profile")
-- profile.start("l",)

ffi.cdef [[
typedef void FILE;
typedef unsigned long chtype;

int initscr(void);
int endwin(void);
int cbreak(void);
int noecho(void);
int keypad(void *win, int bf);
int getch(void);
int printw(const char *fmt, ...);
int refresh(void);
int clear(void);
int move(int y, int x);
int curs_set(int visibility);
int nodelay(void *win, int bf);
void *stdscr;
]]

local curses = ffi.load("ncurses")

function setup()
	-- Initialize ncurses
	curses.initscr()
	curses.cbreak()
	curses.noecho()
	curses.keypad(curses.stdscr, 1)
	curses.curs_set(0)
	curses.nodelay(curses.stdscr, 1)

	local machine = C64:new(nil, "kernal.901227-03.bin", "basic.901226-01.bin", "characters.325018-02.bin")

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

	return machine
end

function cleanup()
	curses.endwin()
end

local machine = setup()
machine.DIAG1 = 0

local last_key = 0

local avg_count = 0

while true do
	local ch = curses.getch()
	if ch == -1 then
		machine.keyboard:release_all()
	else
		last_key = ch
		if ch == 10 then
			ch = "key_return"
		else
			ch = string.char(ch)
		end
		if ch == "q" then
			break
		end
		machine.keyboard:key_down(ch)
	end

	for i = 1, 16667 do
		machine:step()
	end

	curses.clear()
	curses.move(0, 0)
	local lines = machine.vic:naive_text_render(machine)
	for _, line in pairs(lines) do
		curses.printw(line .. "\n")
	end
	local c = collectgarbage("count")
	avg_count = 0.98 * avg_count + 0.02 * c
	curses.printw("")

	curses.printw("KEY: " .. last_key .. "\n")
	curses.printw("ALLOC:    " .. c .. "\n")
	curses.printw("AVGALLOC: " .. avg_count .. "\n")
	curses.printw("DIAG1:    " .. machine.DIAG1)
	curses.refresh()

	collectgarbage("collect")
end

cleanup()

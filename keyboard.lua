Keyboard = {}

local key_table = {
	insert_delete = { row = 0x01, col = 0x01 },
	key_return = { row = 0x01, col = 0x02 },
	cursor_horz = { row = 0x01, col = 0x04 },
	f7 = { row = 0x01, col = 0x08 },
	f1 = { row = 0x01, col = 0x10 },
	f3 = { row = 0x01, col = 0x20 },
	f5 = { row = 0x01, col = 0x40 },
	cursor_vert = { row = 0x01, col = 0x80 },

	key_3 = { row = 0x02, col = 0x01 },
	w = { row = 0x02, col = 0x02 },
	a = { row = 0x02, col = 0x04 },
	key_4 = { row = 0x02, col = 0x08 },
	z = { row = 0x02, col = 0x10 },
	s = { row = 0x02, col = 0x20 },
	e = { row = 0x02, col = 0x40 },
	key_left_shift = { row = 0x02, col = 0x80 },

	key_5 = { row = 0x04, col = 0x01 },
	r = { row = 0x04, col = 0x02 },
	d = { row = 0x04, col = 0x04 },
	key_6 = { row = 0x04, col = 0x08 },
	c = { row = 0x04, col = 0x10 },
	f = { row = 0x04, col = 0x20 },
	t = { row = 0x04, col = 0x40 },
	x = { row = 0x04, col = 0x80 },

	key_7 = { row = 0x08, col = 0x01 },
	y = { row = 0x08, col = 0x02 },
	g = { row = 0x08, col = 0x04 },
	key_8 = { row = 0x08, col = 0x08 },
	b = { row = 0x08, col = 0x10 },
	h = { row = 0x08, col = 0x20 },
	u = { row = 0x08, col = 0x40 },
	v = { row = 0x08, col = 0x80 },

	key_9 = { row = 0x10, col = 0x01 },
	i = { row = 0x10, col = 0x02 },
	j = { row = 0x10, col = 0x04 },
	key_0 = { row = 0x10, col = 0x08 },
	m = { row = 0x10, col = 0x10 },
	k = { row = 0x10, col = 0x20 },
	o = { row = 0x10, col = 0x40 },
	n = { row = 0x10, col = 0x80 },

	key_plus = { row = 0x20, col = 0x01 },
	p = { row = 0x20, col = 0x02 },
	l = { row = 0x20, col = 0x04 },
	key_minus = { row = 0x20, col = 0x08 },
	key_period = { row = 0x20, col = 0x10 },
	key_colon = { row = 0x20, col = 0x20 },
	key_at = { row = 0x20, col = 0x40 },
	key_comma = { row = 0x20, col = 0x80 },

	key_pound = { row = 0x40, col = 0x01 },
	key_asterisk = { row = 0x40, col = 0x02 },
	key_semicolon = { row = 0x40, col = 0x04 },
	key_clear_home = { row = 0x40, col = 0x08 },
	key_right_shift = { row = 0x40, col = 0x10 },
	key_equal = { row = 0x40, col = 0x20 },
	key_up_arrow = { row = 0x40, col = 0x40 },
	key_slash = { row = 0x40, col = 0x80 },

	key_1 = { row = 0x80, col = 0x01 },
	key_left_arrow = { row = 0x80, col = 0x02 },
	key_control = { row = 0x80, col = 0x04 },
	key_2 = { row = 0x80, col = 0x08 },
	key_space = { row = 0x80, col = 0x10 },
	key_commodore = { row = 0x80, col = 0x20 },
	q = { row = 0x80, col = 0x40 },
	key_run_stop = { row = 0x80, col = 0x80 },
}

function Keyboard:new()
	local kb = {
		pressed = {},
		cache = {}
	}

	setmetatable(kb, self)
	Keyboard.__index = Keyboard
	return kb
end

local ctr = 0

function Keyboard:key_down(key)
	self.pressed[key] = key_table[key]
	self.cache = {}
end

function Keyboard:key_up(key)
	self.pressed[key] = nil
	self.cache = {}
end

function Keyboard:release_all()
	self.pressed = {}
	self.cache = {}
end

function Keyboard:scan(row)
	local cached = self.cache[row]
	if cached ~= nil then
		return cached
	end

	local nrow = bit.band(bit.bnot(row), 0xFF)

	local out = 0
	for _, k in pairs(self.pressed) do
		if bit.band(nrow, k.row) ~= 0 then
			out = bit.bor(k.col)
		end
	end

	out = bit.band(bit.bnot(out), 0xFF)

	self.cache[row] = out
	return out
end

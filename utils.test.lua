require "utils"

function assert(b, msg)
	if not b then
		printf("Test failed: %s", msg or "(no details)")
		os.exit(1)
	end
end

function test_map_range()
	-- Empty range
	local r = map_range(0, function() return "ok" end)
	assert(type(r) == "table")
	assert(table_length(r) == 0, "expected empty")

	-- Single item
	r = map_range(1, function() return "ok" end)
	assert(type(r) == "table", "unexpected type")
	assert(table_length(r) == 1, "unexpected length" .. table_length(r))
	assert(r[0] == "ok", "unexpected value")

	-- A few items
	r = map_range(5, function(i) return "item" .. i end)
	assert(type(r) == "table")
	assert(table_length(r) == 5)
	assert(r[0] == "item0")
	assert(r[4] == "item4")
end

function test_zb()
	local r = zb({})
	assert(type(r) == "table")
	assert(table_length(r) == 0)

	r = zb({ "foo" })
	assert(type(r) == "table")
	assert(table_length(r) == 1)
	assert(r[0] == "foo")

	r = zb({ "foo", "bar" })
	assert(type(r) == "table")
	assert(table_length(r) == 2)
	assert(r[0] == "foo")
	assert(r[1] == "bar")
end

test_map_range()
test_zb()

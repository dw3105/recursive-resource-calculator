--UW1: gray + magenta (legalcopilot-dev 2026-09-28) shipped molten-iron pipe pair (8,88)-(10,88) inside pair
--(6,88)-(16,88) on the same row; a new underground end may not sit inside an existing same-family, same-axis span.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local key = Route._coordinate_key
local inside = Route._test.inside_same_axis_span

local function world(kind)
    local pair = {segment_id = "outer", kind = kind, underground = true, underground_entry_x = 6, underground_entry_y = 88,
        underground_exit_x = 16, underground_exit_y = 88}
    return {segments_by_cell = {[key(6, 88)] = pair, [key(16, 88)] = pair}}
end

H.test("UW1 an end strictly inside a same-family pair on the same axis is refused", function()
    H.equal(inside(world("pipe"), 8, 88, 1, 0, true, 10), true)
    H.equal(inside(world("pipe"), 10, 88, -1, 0, true, 10), true)
    io.write("UW1\n")
end)
H.test("UW2 other family, other axis or outside the span is allowed", function()
    H.equal(inside(world("belt"), 8, 88, 1, 0, true, 10), false)
    H.equal(inside(world("pipe"), 8, 88, 0, 1, true, 10), false)
    H.equal(inside(world("pipe"), 17, 88, 1, 0, true, 10), false)
    io.write("UW2\n")
end)
H.done("test_route_underground_weave")

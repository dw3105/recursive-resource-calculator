--The shared world-box conversion, pinned from explicit coordinates.
--
--Every expectation below is written out by hand. None of them calls a production predicate to decide what the
--answer should be, because a test that asks the code under test what it thinks proves only that it is
--consistent with itself. That is exactly how the planner and the validator drifted apart: each was internally
--consistent, and they disagreed with each other.
local H = require "tests.harness"
local Geometry = require "logic.bp.geometry"
local Grid = require "logic.bp.grid"

--A local prototype collision box, engine shaped.
local function corners(left, top, right, bottom)
    return {left_top = {x = left, y = top}, right_bottom = {x = right, y = bottom}}
end

local function box_equal(actual, expected, label)
    H.deep_equal({actual.left, actual.top, actual.right, actual.bottom}, expected, label)
end

H.test("GE1 a tile member with no collision box falls back to its footprint, and says so", function()
    local box, source = Geometry.world_box({x = 3, y = 4, w = 3, h = 3}, {})
    box_equal(box, {3, 4, 6, 7}, "a 3x3 tile member at 3,4 spans 3..6 by 4..7")
    H.equal(source, "tile_fallback", "the caller can tell a substituted footprint from a real box")
end)

H.test("GE2 a collision box smaller than the tile footprint shrinks the member", function()
    local spec = {collision_box = corners(-0.7, -0.7, 0.7, 0.7), tile_w = 3, tile_h = 3}
    local box, source = Geometry.world_box({x = 3, y = 4, w = 3, h = 3}, spec)
    box_equal(box, {3.8, 4.8, 5.2, 6.2}, "centre 4.5,5.5 plus a 0.7 half extent")
    H.equal(source, "collision_box", "the real box is reported as such")
end)

--The counterexample that made this module necessary. A beacon at 3,0 with reach 3 supplies down to y 4.5.
--A 3x3 machine at 3,4 overlaps that area on its tile footprint, and does not overlap it once its real
--collision box is used. Tile-rectangle overlap and collision-box overlap are different questions.
H.test("GE3 tile overlap and collision-box overlap disagree, and the collision box decides", function()
    local beacon = {x = 3, y = 0, w = 3, h = 3}
    local supply = Geometry.supply_box_of(beacon, 3, 3)
    box_equal(supply, {1.5, -1.5, 7.5, 4.5}, "reach is measured from the beacon centre, never from its edge")

    local machine = {x = 3, y = 4, w = 3, h = 3}
    local fallback = Geometry.world_box(machine, {})
    box_equal(fallback, {3, 4, 6, 7}, "the tile footprint starts at y 4")
    H.equal(Geometry.box_overlaps_supply(fallback, supply), true, "4 < 4.5, so the footprint overlaps")

    local narrow = Geometry.world_box(machine, {collision_box = corners(-0.7, -0.7, 0.7, 0.7)})
    box_equal(narrow, {3.8, 4.8, 5.2, 6.2}, "the real box starts at y 4.8")
    H.equal(Geometry.box_overlaps_supply(narrow, supply), false, "4.8 > 4.5, so the real box does not overlap")
end)

H.test("GE4 an asymmetric box survives a quarter turn by its corners, never by swapping w and h", function()
    --Local box 2 wide by 1 tall, pushed off centre. A naive swap would keep it centred and lose the offset.
    local spec = {collision_box = corners(-1.5, -0.25, 0.5, 0.25)}
    local north = Geometry.world_box({x = 0, y = 0, w = 1, h = 1, dir = Grid.NORTH}, spec)
    box_equal(north, {-1, 0.25, 1, 0.75}, "north keeps the box as authored, about centre 0.5,0.5")

    local east = Geometry.world_box({x = 0, y = 0, w = 1, h = 1, dir = Grid.EAST}, spec)
    box_equal(east, {0.25, -1, 0.75, 1}, "a quarter turn carries the offset onto the other axis")

    local south = Geometry.world_box({x = 0, y = 0, w = 1, h = 1, dir = Grid.SOUTH}, spec)
    box_equal(south, {0, 0.25, 2, 0.75}, "half a turn mirrors the offset")

    local west = Geometry.world_box({x = 0, y = 0, w = 1, h = 1, dir = Grid.WEST}, spec)
    box_equal(west, {0.25, 0, 0.75, 2}, "three quarters mirrors it on the other axis")
end)

H.test("GE5 a symmetric box is unchanged by every direction", function()
    local spec = {collision_box = corners(-0.4, -0.4, 0.4, 0.4)}
    for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
        local box = Geometry.world_box({x = 2, y = 2, w = 1, h = 1, dir = dir}, spec)
        box_equal(box, {2.1, 2.1, 2.9, 2.9}, "direction " .. tostring(dir) .. " leaves a symmetric box alone")
    end
end)

--Collision is strict. Factorio places entities edge to edge all day, so touching is legal.
H.test("GE6 touching edges do not collide, and one tile of overlap does", function()
    local other = {left = 0, top = 0, right = 10, bottom = 10}
    H.equal(Geometry.boxes_overlap({left = 10, top = 0, right = 12, bottom = 10}, other), false,
        "a member whose left edge is the other's right edge only touches")
    H.equal(Geometry.boxes_overlap({left = 9, top = 0, right = 12, bottom = 10}, other), true,
        "one tile inside is a collision")
    H.equal(Geometry.boxes_overlap({left = 0, top = 10, right = 10, bottom = 12}, other), false,
        "the same on the other axis")
    H.equal(Geometry.boxes_overlap({left = 11, top = 11, right = 13, bottom = 13}, other), false,
        "a genuine miss stays a miss")
end)

--Supply is tolerant, and deliberately the opposite of collision at the boundary: a machine sitting exactly on
--the edge of a supply area is supplied. That is the rule the validator already applies to poles.
H.test("GE7 supply includes the boundary, and still refuses a real gap", function()
    local supply = {left = 0, top = 0, right = 10, bottom = 10}
    H.equal(Geometry.box_overlaps_supply({left = 10, top = 0, right = 12, bottom = 10}, supply), true,
        "a member touching the supply edge is supplied, unlike collision")
    H.equal(Geometry.box_overlaps_supply({left = 10 + 1e-6, top = 0, right = 12, bottom = 10}, supply), false,
        "a gap a thousand times the tolerance is a real gap")
    H.equal(Geometry.box_overlaps_supply({left = 11, top = 0, right = 13, bottom = 10}, supply), false,
        "a whole tile away is not supplied")
    H.equal(Geometry.tolerance(0) >= Geometry.EPSILON, true, "the tolerance never falls below epsilon")
    H.equal(Geometry.tolerance(1e6) > Geometry.EPSILON, true, "and grows with the magnitude compared")
end)

H.test("GE8 a supply area is a distance from the centre, never half a width", function()
    local supply = Geometry.supply_box(0, 0, 3, 3)
    box_equal(supply, {-3, -3, 3, 3}, "reach 3 spans 6 tiles across, not 3")
    local oblong = Geometry.supply_box(5, 5, 4, 2)
    box_equal(oblong, {1, 3, 9, 7}, "the two axes are independent")
    local square = Geometry.supply_box(5, 5, 4)
    box_equal(square, {1, 1, 9, 9}, "a single reach applies to both axes")
end)

H.test("GE9 an engine-style position outranks a tile rectangle for the centre", function()
    local x, y = Geometry.center({position = {x = 12.5, y = 7.5}, x = 0, y = 0, w = 3, h = 3})
    H.deep_equal({x, y}, {12.5, 7.5}, "a placed entity reports its own centre")
    local tx, ty = Geometry.center({x = 4, y = 6, w = 4, h = 2})
    H.deep_equal({tx, ty}, {6, 7}, "a planner member derives its centre from its rectangle")
end)

H.test("GE10 box_in_supply answers the whole question in one call", function()
    local beacon = {x = 3, y = 0, w = 3, h = 3}
    local cx, cy = Geometry.center(beacon)
    H.deep_equal({cx, cy}, {4.5, 1.5}, "the beacon centre")
    H.equal(Geometry.box_in_supply({x = 3, y = 4, w = 3, h = 3}, {}, cx, cy, 3, 3), true,
        "the tile-fallback machine is supplied")
    H.equal(Geometry.box_in_supply({x = 3, y = 4, w = 3, h = 3},
        {collision_box = corners(-0.7, -0.7, 0.7, 0.7)}, cx, cy, 3, 3), false,
        "the narrow-boxed machine is not")
end)

H.test("GE11 a malformed or absent collision box falls back rather than guessing", function()
    H.equal(Geometry.local_box(nil, Grid.NORTH), nil, "no box at all")
    H.equal(Geometry.local_box({}, Grid.NORTH), nil, "a table with no corners")
    H.equal(Geometry.local_box(corners(0 / 0, 0, 1, 1), Grid.NORTH), nil, "a non-finite corner")
    local box, source = Geometry.world_box({x = 0, y = 0, w = 2, h = 2}, {collision_box = {}})
    box_equal(box, {0, 0, 2, 2}, "the footprint stands in")
    H.equal(source, "tile_fallback", "and the caller is told")
end)

H.done("test_geometry")

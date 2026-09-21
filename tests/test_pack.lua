--MaxRects packs opaque blocks deterministically, yields inside its region scan, and never hides a region-cap breach.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

local function fixture(blocks, obstacles, limits)
    return {
        area = Grid.rect(0, 0, 10, 10),
        obstacles = obstacles or {Grid.rect(4, 4, 2, 2)},
        blocks = blocks,
        limits = limits or {},
    }
end

local function drive(state, ops, maximum)
    local steps = 0
    maximum = maximum or 1000
    while not state.done and steps < maximum do
        Pack.step(state, {ops = ops})
        steps = steps + 1
    end
    H.equal(state.done, true, "packer completes within the test bound")
    return state, steps
end

local function run(input, ops)
    return drive(Pack.begin(input), ops)
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
    return copy
end

local function assert_plain(value, path, seen)
    local value_type = type(value)
    H.equal(value_type == "function" or value_type == "userdata", false, path .. " is plain data")
    if value_type ~= "table" then return end
    H.equal(getmetatable(value), nil, path .. " has no metatable")
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        assert_plain(key, path .. ".<key>", seen)
        assert_plain(child, path .. "." .. tostring(key), seen)
    end
end

local function placements(input, ops)
    return run(input, ops).result.placements
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " P1 central obstacle keeps a tall block beside it", function()
        local state = run(fixture({{block_id = "tall", w = 3, h = 8, allowed_dirs = {Grid.NORTH}}}), 100)
        local placement = state.result.placements[1]
        H.equal(state.ok, true, "the tall block packs")
        H.equal(placement ~= nil, true, "the tall block has a placement")
        H.equal(placement.x == 0 or placement.x == 6, true, "the tall block is beside the obstacle")
        H.equal(placement.w, 3, "the rotation-forbidden width is retained")
        H.equal(placement.h, 8, "the rotation-forbidden height is retained")
    end)

    H.test(shape .. " P2 placements stay in the area and out of obstacles and each other", function()
        local state = run(fixture({
            {block_id = "a", w = 3, h = 3, allowed_dirs = {Grid.NORTH}},
            {block_id = "b", w = 3, h = 3, allowed_dirs = {Grid.NORTH}},
            {block_id = "c", w = 2, h = 4, allowed_dirs = {Grid.NORTH, Grid.EAST}},
        }), 100)
        H.equal(#state.result.placements, 3, "all blocks are placed")
        for i, placement in ipairs(state.result.placements) do
            H.equal(placement.x >= 0 and placement.y >= 0, true, "placement " .. i .. " starts in the area")
            H.equal(placement.x + placement.w <= 10 and placement.y + placement.h <= 10,
                true, "placement " .. i .. " stays in the area")
            H.equal(Grid.intersects(placement, Grid.rect(4, 4, 2, 2)), false,
                "placement " .. i .. " avoids the obstacle")
            for previous = 1, i - 1 do
                H.equal(Grid.intersects(placement, state.result.placements[previous]), false,
                    "placement " .. i .. " avoids an earlier block")
            end
        end
    end)

    H.test(shape .. " P3 no-fit names the block and leaves earlier geometry alone", function()
        local input = fixture({
            {block_id = "first", w = 3, h = 8, allowed_dirs = {Grid.NORTH}},
            {block_id = "impossible", w = 20, h = 20, allowed_dirs = {Grid.NORTH}},
        })
        local first_only = run(fixture({input.blocks[1]}), 100).result
        local state = run(input, 100)
        H.equal(state.ok, false, "an unplaceable block fails the pack")
        H.deep_equal(state.errors, {{code = "BP_P_NO_FIT", block_id = "impossible"}},
            "the no-fit error names the block")
        H.deep_equal(state.result.placements, first_only.placements, "the earlier placement remains")
        H.deep_equal(state.result.free_regions, first_only.free_regions, "the earlier free geometry remains")
    end)

    H.test(shape .. " P4 identical inputs produce identical placements", function()
        local input = fixture({
            {block_id = "one", w = 3, h = 8},
            {block_id = "two", w = 2, h = 3},
            {block_id = "three", w = 4, h = 2},
        })
        H.deep_equal(placements(input, 100), placements(input, 100), "the placement result is deterministic")
    end)

    H.test(shape .. " P5 one operation per step matches an unbounded scan", function()
        local input = fixture({{block_id = "tall", w = 3, h = 8, allowed_dirs = {Grid.NORTH}}})
        local fast, fast_steps = run(input, 100)
        local slow, slow_steps = run(input, 1)
        H.deep_equal(slow.result.placements, fast.result.placements, "bounded and unbounded placements match")
        H.deep_equal(slow.result.free_regions, fast.result.free_regions, "bounded and unbounded geometry matches")
        H.equal(slow_steps > fast_steps, true, "the bounded run yields inside the region scan")
    end)

    H.test(shape .. " P6 the cursor is plain data and a copied cursor resumes identically", function()
        local state = Pack.begin(fixture({{block_id = "tall", w = 3, h = 8, allowed_dirs = {Grid.NORTH}}}))
        Pack.step(state, {ops = 1})
        H.equal(state.done, false, "one scan operation does not finish the block")
        H.equal(state.cursor.region_index > 1, true, "the cursor advanced within the scan")
        assert_plain(state, "state")

        local resumed = clone(state)
        drive(state, 1)
        drive(resumed, 1)
        H.deep_equal(resumed.result, state.result, "a copied cursor produces the same result")
    end)

    H.test(shape .. " P7 region cap reports the breach without dropping the placement", function()
        local state = run(fixture({{block_id = "tall", w = 3, h = 8, allowed_dirs = {Grid.NORTH}}}), 100)
        local capped = run(fixture({{block_id = "tall", w = 3, h = 8, allowed_dirs = {Grid.NORTH}}}, nil,
            {max_free_regions = state.stats.peak_free_regions - 1}), 100)
        H.equal(capped.ok, false, "a cap breach fails the pack")
        H.deep_equal(capped.errors, {{code = "BP_P_REGION_LIMIT"}}, "the cap has the packing reason code")
        H.equal(capped.stats.peak_free_regions > capped.limits.max_free_regions, true,
            "the reported peak is not silently truncated")
        H.equal(#capped.result.placements, 1, "the block is not lost when the cap is breached")
    end)

    H.test(shape .. " P8 a rotation-forbidden block is never rotated", function()
        local state = run(fixture({{block_id = "fixed", w = 2, h = 7, allowed_dirs = {Grid.NORTH}}}), 100)
        local placement = state.result.placements[1]
        H.equal(placement.dir, Grid.NORTH, "only the allowed direction is used")
        H.equal(placement.w, 2, "forbidden rotation cannot swap width")
        H.equal(placement.h, 7, "forbidden rotation cannot swap height")
    end)

    H.test(shape .. " P9 BSSF prefers the tighter short side", function()
        local short, long = Pack.bssf_score(Grid.rect(0, 0, 8, 5), 6, 3)
        H.deep_equal({short, long}, {2, 2}, "BSSF returns short side before long side")

        local input = {
            area = Grid.rect(0, 0, 10, 8),
            obstacles = {Grid.rect(0, 3, 10, 2)},
            blocks = {{block_id = "fit", w = 3, h = 3, allowed_dirs = {Grid.NORTH}}},
            limits = {},
        }
        local state = run(input, 100)
        local placement = state.result.placements[1]
        H.equal(placement.x, 0, "the tighter short-side region wins")
        H.equal(placement.y, 0, "the upper region is the tighter fit")
    end)

    H.test(shape .. " P10 BSSF short side beats earlier coordinate tie-breaks", function()
        local input = {
            area = Grid.rect(0, 0, 12, 14),
            obstacles = {Grid.rect(5, 0, 4, 14), Grid.rect(9, 0, 3, 2)},
            blocks = {{block_id = "tight", w = 4, h = 3, allowed_dirs = {Grid.NORTH, Grid.EAST}}},
            limits = {},
        }
        local state = run(input, 100)
        local placement = state.result.placements[1]
        H.equal(placement ~= nil, true, "the block has a placement")
        H.equal(placement.x, 9, "the tighter short-side region beats the earlier tie-breaks")
        H.equal(placement.y, 2, "the tighter region starts below the earlier region")
        H.equal(placement.dir, Grid.EAST, "the tighter region uses its only fitting direction")
    end)

    H.test(shape .. " P11 BSSF long side breaks an equal short-side tie", function()
        local input = {
            area = Grid.rect(0, 0, 12, 20),
            obstacles = {Grid.rect(0, 8, 12, 3)},
            blocks = {{block_id = "long-tie", w = 10, h = 3, allowed_dirs = {Grid.NORTH}}},
            limits = {},
        }
        local state = run(input, 100)
        local placement = state.result.placements[1]
        H.equal(placement ~= nil, true, "the block has a placement")
        H.equal(placement.x, 0, "the tighter long-side region starts at the left")
        H.equal(placement.y, 0, "the tighter long-side region is selected")
    end)

    H.test(shape .. " P12 rejects a region that fits on one axis only", function()
        local input = {
            area = Grid.rect(0, 0, 10, 8),
            obstacles = {Grid.rect(2, 0, 3, 8), Grid.rect(5, 5, 5, 3)},
            blocks = {{block_id = "open-only", w = 3, h = 3, allowed_dirs = {Grid.NORTH}}},
            limits = {},
        }
        local state = run(input, 100)
        local placement = state.result.placements[1]
        H.equal(placement ~= nil, true, "the block has a placement")
        H.equal(placement.x, 5, "the block is placed in the open region")
        H.equal(placement.y, 0, "the block starts in the open region")
        H.equal(placement.x >= 0 and placement.y >= 0, true, "the placement starts inside the area")
        H.equal(placement.x + placement.w <= 10 and placement.y + placement.h <= 8,
            true, "the placement stays inside the area")
        H.equal(Grid.intersects(placement, Grid.rect(2, 0, 3, 8)), false,
            "the placement avoids the corridor wall")
        H.equal(Grid.intersects(placement, Grid.rect(5, 5, 5, 3)), false,
            "the placement avoids the lower obstacle")
    end)

    H.test(shape .. " P13 no-fit names a block when only its width fits", function()
        local input = {
            area = Grid.rect(0, 0, 10, 5),
            obstacles = {Grid.rect(0, 2, 10, 1)},
            blocks = {{block_id = "height-only", w = 5, h = 3, allowed_dirs = {Grid.NORTH}}},
            limits = {},
        }
        local state = run(input, 100)
        H.equal(state.ok, false, "a block that fits on one axis only fails the pack")
        H.deep_equal(state.errors, {{code = "BP_P_NO_FIT", block_id = "height-only"}},
            "the no-fit error names the block")
    end)

    H.test(shape .. " P14 a pinned port has only its authored slot", function()
        local state = run({
            area = Grid.rect(0, 0, 10, 10), obstacles = {}, limits = {},
            blocks = {{block_id = "pinned", w = 3, h = 3, allowed_dirs = {Grid.NORTH, Grid.EAST}, ports = {{
                port_id = "pinned-port", role = "in", flow_id = "item/pinned", inserter_id = "hand:1",
                attach_dx = 1, attach_dy = 3, normal_dir = Grid.NORTH, travel_dir = Grid.NORTH,
            }}}},
        }, 100)
        H.equal(state.ok, true, "the pinned block packs")
        local slot = state.result.placements[1].port_slots[1]
        H.deep_equal({slot.attach_dx, slot.attach_dy}, {1, 3}, "the authored attach is retained")
    end)

    H.test(shape .. " P15 a pinned port may move the block when its own tile is occupied", function()
        local state = Pack.begin({
            area = Grid.rect(0, 0, 10, 10), obstacles = {}, limits = {},
            blocks = {{block_id = "pinned", w = 2, h = 2, allowed_dirs = {Grid.NORTH}, ports = {{
                port_id = "pinned-port", role = "in", flow_id = "item/pinned", inserter_id = "hand:1",
                attach_dx = 0, attach_dy = 2, normal_dir = Grid.NORTH, travel_dir = Grid.NORTH,
            }}}},
        })
        --The authored slot at the first origin is occupied by an existing port cell, but the same block can
        --move one tile inside the free region without changing its hand/port relationship.
        state.port_cells = {{x = 0, y = 2}}
        drive(state, 100)
        H.equal(state.ok, true, "the pinned block moves to a free authored slot")
        H.equal(state.result.placements[1].x ~= 0 or state.result.placements[1].y ~= 0,
            true, "the block moves inside the region")
        H.deep_equal({state.result.placements[1].port_slots[1].attach_dx,
            state.result.placements[1].port_slots[1].attach_dy}, {0, 2},
            "the authored slot does not become a synthetic edge slot")
    end)
end

H.done("test_pack")

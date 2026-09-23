local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Buffer = require "logic.bp.buffer"
local Pack = require "logic.bp.pack"

local function machine(key, ring)
    return {x = 0, y = 0, w = 2, h = 2, ring = ring or 2, key = key}
end

local function run(input, ops)
    local state, steps = Pack.begin(input), 0
    while not state.done and steps < 100000 do
        Pack.step(state, {ops = ops})
        steps = steps + 1
    end
    H.equal(state.done, true, "pack finishes")
    return state
end

local function input(width, height, second_key)
    return {area = Grid.rect(0, 0, width, height), blocks = {
        {block_id = "a", w = 2, h = 2, allowed_dirs = {Grid.NORTH}, buffer_zones = {machine("a", 2)}},
        {block_id = "b", w = 2, h = 2, allowed_dirs = {Grid.NORTH}, buffer_zones = {machine(second_key or "b", 2)}},
    }}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PZ1 different machine keys keep four empty tiles between footprints", function()
        local state = run(input(10, 4), 100000)
        H.equal(state.ok, true, "both machines fit")
        local a, b = state.placements[1], state.placements[2]
        local ra, rb = {x = a.x, y = a.y, w = 2, h = 2}, {x = b.x, y = b.y, w = 2, h = 2}
        H.equal(Buffer.conflict({rect = ra, ring = 2, key = "a"}, {rect = rb, ring = 2, key = "b"}), false,
            "different keys do not enter one another's ring")
        H.equal((math.max(ra.x, rb.x) - math.min(ra.x + ra.w, rb.x + rb.w) >= 4)
            or (math.max(ra.y, rb.y) - math.min(ra.y + ra.h, rb.y + rb.h) >= 4), true,
            "footprints have at least four empty tiles between them")
    end)

    H.test(shape .. " PZ2 matching machines can share ring space only along a row or column", function()
        local state = run(input(6, 4, "a"), 100000)
        H.equal(state.ok, true, "same-key machines fit together")
        local a, b = state.placements[1], state.placements[2]
        H.equal(a.x == b.x or a.y == b.y, true, "the close pair shares a column or row")
    end)

    H.test(shape .. " PZ3 one operation per call matches an unbounded buffer-aware scan", function()
        local fast = run(input(10, 4), 100000)
        local slow = run(input(10, 4), 1)
        H.deep_equal(slow.result.placements, fast.result.placements, "bounded and unbounded placements match")
    end)

    H.test(shape .. " PZ4 blocks without zones retain the round-25-base placements", function()
        local state = run({area = Grid.rect(0, 0, 12, 8), blocks = {
            {block_id = "legacy-a", w = 2, h = 2, allowed_dirs = {Grid.NORTH}},
            {block_id = "legacy-b", w = 3, h = 2, allowed_dirs = {Grid.NORTH}},
        }}, 100000)
        H.deep_equal(state.result.placements, {
            {block_id = "legacy-a", x = 0, y = 0, dir = 0, w = 2, h = 2, port_slots = nil},
            {block_id = "legacy-b", x = 0, y = 2, dir = 0, w = 3, h = 2, port_slots = nil},
        }, "legacy placements match the stored base output")
    end)
end

H.done("test_pack_buffer")

-- Regression: the former layered fallback stacked unrelated source blocks down the grid, so their
-- shared downstream consumer had long vertical feeds instead of a compact producer row.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

H.test("AP1 independent producers occupy one row before their shared consumer", function()
    local blocks = {}
    for i = 1, 3 do
        blocks[#blocks + 1] = {block_id = "producer-" .. i, w = 2, h = 2,
            allowed_dirs = {Grid.NORTH}}
    end
    blocks[#blocks + 1] = {block_id = "consumer", w = 2, h = 2,
        allowed_dirs = {Grid.NORTH}}
    local links = {}
    for i = 1, 3 do
        links[#links + 1] = {a = {block_id = "producer-" .. i}, b = {block_id = "consumer"}}
    end
    local state = Pack.begin({area = Grid.rect(0,0,20,12), obstacles = {}, blocks = blocks,
        links = links, layered = true})
    local ticks = 0
    while not state.done and ticks < 1000 do Pack.step(state, {ops = 1000}); ticks = ticks + 1 end
    H.equal(state.ok, true, "the linked blocks pack")
    local ys, producer_right, consumer_x = {}, nil, nil
    for _, p in ipairs(state.result.placements) do
        if tostring(p.block_id):match("^producer") then
            ys[#ys + 1] = p.y
            producer_right = math.max(producer_right or 0, p.x + p.w)
        elseif p.block_id == "consumer" then
            consumer_x = p.x
        end
    end
    H.equal(#ys, 3, "all producers are placed")
    H.equal(ys[1] == ys[2] and ys[2] == ys[3], true,
        "producer peers share a row beside their consumer layer")
    H.equal(consumer_x - producer_right <= 1, true,
        "the consumer starts next to the producer row")
end)

H.done("test_pack_adjacent_producers")

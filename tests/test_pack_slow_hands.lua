-- Regression: before the fix, a compact opaque block carrying many distinct hands could be refused
-- even though every pinned attachment and approach tile fits in the grid.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

H.test("SH1 a block with many pinned hand ports still packs", function()
    local ports = {}
    local points = {
        {-1,1},{-1,2},{-1,3},{-1,4},{-1,5},
        {1,2,4,12},{2,2,4,12},{1,-1},{2,-1},{3,-1},
        {6,1},{6,2},{6,3},{6,4},{6,5},
    }
    for i, p in ipairs(points) do
        ports[i] = {port_id = "p" .. i, inserter_id = "h" .. i,
            role = "out", attach_dx = p[1], attach_dy = p[2],
            normal_dir = p[3], travel_dir = p[4]}
    end
    local input = {area = Grid.rect(0,0,14,14), obstacles = {}, blocks = {
        {block_id = "many-hands", w = 6, h = 7, allowed_dirs = {Grid.NORTH}, ports = ports},
    }}
    local state = Pack.begin(input)
    local ticks = 0
    while not state.done and ticks < 1000 do Pack.step(state, {ops = 1000}); ticks = ticks + 1 end
    H.equal(state.ok, true, "the many-hand block has a legal placement")
    H.equal(#state.result.placements, 1, "the block is placed")
end)

H.done("test_pack_slow_hands")

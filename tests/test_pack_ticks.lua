-- Linked packing evaluates each origin once and bounds work to the caller's tick budget.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

local function fixture(disable_cut)
    local blocks, links = {}, {}
    for i = 1, 8 do
        blocks[i] = {block_id = "p" .. i, w = 2, h = 2, allowed_dirs = {Grid.NORTH}, ports = {{
            port_id = "hand", role = "in", flow_id = "f" .. i, inserter_id = "hand:" .. i,
            attach_dx = 0, attach_dy = 2, normal_dir = Grid.NORTH, travel_dir = Grid.NORTH,
        }}}
        links[i] = {a = {block_id = "p" .. i, port_id = "hand"}, b = {edge = "left"}}
    end
    return {area = Grid.rect(0, 0, 54, 54), obstacles = {}, blocks = blocks, links = links,
        disable_link_cut = disable_cut}
end

local function run(input)
    local state, worst, calls = Pack.begin(input), 0, 0
    while not state.done and calls < 100000 do
        local start = os.clock()
        Pack.step(state, {ops = 2000})
        local elapsed = os.clock() - start
        if elapsed > worst then worst = elapsed end
        calls = calls + 1
    end
    H.equal(state.done, true, "packing completes")
    return state, worst
end

H.test("linked 54x54 packing matches the uncropped reference with fewer origins and short ticks", function()
    local cut, cut_tick = run(fixture(false))
    local reference = run(fixture(true))
    H.deep_equal(cut.result.placements, reference.result.placements, "the cut preserves every placement byte of data")
    H.equal(cut.counters.evaluated_origins * 2 <= reference.counters.evaluated_origins, true,
        "the bound evaluates at most half the reference origins")
    H.equal(cut_tick <= 0.03, true, "no 2000-op step exceeds 0.03 seconds")
end)

H.done("test_pack_ticks")

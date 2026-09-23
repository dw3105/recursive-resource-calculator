-- Packing scan work is sliced at origin boundaries and remains deterministic across slice sizes.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

local function pinned_input(size)
    return {area = Grid.rect(0, 0, size, size), obstacles = {}, blocks = {{
        block_id = "pinned", w = 2, h = 2, allowed_dirs = {Grid.NORTH}, ports = {{
            port_id = "hand", role = "in", flow_id = "item/x", inserter_id = "hand:1",
            attach_dx = 0, attach_dy = 2, normal_dir = Grid.NORTH, travel_dir = Grid.NORTH,
        }},
    }}}
end

local function run(input, slice)
    local state, calls = Pack.begin(input), 0
    while not state.done and calls < 200000 do
        calls = calls + 1
        Pack.step(state, {ops = slice})
    end
    H.equal(state.done, true, "packing completes")
    return state
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PB1 pinned scan yields after each bounded set of origins", function()
        local state = Pack.begin(pinned_input(40))
        --Make the first authored endpoint unavailable, forcing the movable pinned-port scan.
        state.port_cells = {{x = 0, y = 2}}
        local before = state.counters.origins
        local budget = {ops = 50}
        Pack.step(state, budget)
        H.equal(budget.ops, 0, "the 50-op slice is consumed")
        H.equal(state.done, false, "the large scan remains resumable")
        H.equal(state.counters.origins - before <= 50, true, "at most 50 origins were scanned in this call")
    end)

    H.test(shape .. " PB2 one-op and huge slices choose identical placements", function()
        local input = pinned_input(12)
        local sliced, whole = run(input, 1), run(input, 1000000000)
        H.deep_equal(sliced.result.placements, whole.result.placements,
            "slice size preserves x, y, direction and port slots")
    end)
end

H.done("test_pack_budget")

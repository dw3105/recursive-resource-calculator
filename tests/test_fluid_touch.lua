--This test fails on round-40-base because its foreign-fluid adjacency cases pass through the base stubs.
local H = require "tests.harness"
local FluidTouch = require "logic.bp.fluid_touch"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
local function segment(flow, extra)
    local result = {kind = "pipe", flow_id = flow}
    for k, v in pairs(extra or {}) do result[k] = v end
    return result
end
local demand = {kind = "pipe", flow_id = "fluid/a"}

H.test("FT1 foreign plain pipe beside path is blocked", function()
    H.equal(FluidTouch.path_blocked({[key(2, 1)] = segment("fluid/b")}, key, demand, 1, 1), true)
end)
H.test("FT2 same-flow pipe beside path is free", function()
    H.equal(FluidTouch.path_blocked({[key(2, 1)] = segment("fluid/a")}, key, demand, 1, 1), false)
end)
H.test("FT3 foreign pipe-to-ground beside path is free", function()
    H.equal(FluidTouch.path_blocked({[key(2, 1)] = segment("fluid/b", {underground = true})}, key, demand, 1, 1), false)
end)
H.test("FT4 belt demand beside foreign pipe is free", function()
    H.equal(FluidTouch.path_blocked({[key(2, 1)] = segment("fluid/b")}, key, {kind = "belt", flow_id = "item/a"}, 1, 1), false)
end)
H.test("FT5 unbury observes foreign flow and ignores same-flow and belt pairs", function()
    local pair, foreign = segment("fluid/a", {underground = true}), segment("fluid/b")
    local tiles = {{x = 1, y = 1}}
    H.equal(FluidTouch.unbury_blocked({[key(2, 1)] = foreign}, key, pair, tiles), true)
    H.equal(FluidTouch.unbury_blocked({[key(2, 1)] = segment("fluid/a")}, key, pair, tiles), false)
    H.equal(FluidTouch.unbury_blocked({[key(2, 1)] = foreign}, key, {kind = "belt", flow_id = "fluid/a"}, tiles), false)
end)

local function route_input()
    local function block(id, x, y, role, flow, dx, dy, normal, travel)
        return {block_id = id, machines = {{step_id = id}}, x = x, y = y, w = 1, h = 1,
            ports = {{port_id = id .. ":port", role = role, kind = "fluid", flow_id = flow, rate_per_second = 5,
                attach_dx = dx, attach_dy = dy, normal_dir = normal, travel_dir = travel}}}
    end
    local function flow(id, source, sink)
        return {flow_id = id, is_fluid = true, producers = {{step_id = source, share_per_second = 5}},
            consumers = {{step_id = sink, share_per_second = 5}}}
    end
    return {grid = Grid.new(14, 14), catalog = {pipe = {pipe = "plain", underground = "buried", throughput_per_second = 100,
        underground_max_distance = 5}}, blocks = {
        block("as", 1, 6, "out", "fluid/a", 1, 0, Grid.WEST, Grid.EAST),
        block("at", 12, 6, "in", "fluid/a", -1, 0, Grid.EAST, Grid.EAST),
        block("bs", 1, 8, "out", "fluid/b", 1, 0, Grid.WEST, Grid.EAST),
        block("bt", 12, 8, "in", "fluid/b", -1, 0, Grid.EAST, Grid.EAST)},
        flows = {flow("fluid/a", "as", "at"), flow("fluid/b", "bs", "bt")}}
end

H.test("FT6 route keeps different-flow plain pipes from touching", function()
    local state = Route.begin(route_input())
    local ticks = 0
    while not state.done and ticks < 2000 do ticks = ticks + 1; Route.step(state, {ops = 10000}) end
    H.equal(state.done, true, "route completes")
    H.equal(state.ok, true, "both fluid routes succeed: " .. tostring(state.errors and state.errors[1] and state.errors[1].code))
    local cells = state.work.segments_by_cell or {}
    for cell_key, segment_value in pairs(cells) do
        if not segment_value.underground then
            local x, y = string.match(cell_key, "^([^:]+):([^:]+)$")
            x, y = tonumber(x), tonumber(y)
            for _, delta in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
                local other = cells[key(x + delta[1], y + delta[2])]
                if other and not other.underground and other.flow_id ~= segment_value.flow_id then
                    H.equal(true, false, "different-flow plain pipes touch at " .. cell_key)
                end
            end
        end
    end
end)

H.done("test_fluid_touch")

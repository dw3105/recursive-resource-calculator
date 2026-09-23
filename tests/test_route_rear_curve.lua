--Round 28: a one-flow row's rear port may be entered by a curve. Measured 2026-09-23 on legalcopilot-dev, v8
--(~/share/RRC/player-red-science-1s-20260923-v8.txt): iron ore surfaced south-west of the furnace row's rear port
--and had to U-turn (up, right, down) because the port only accepted a straight entry. The player flagged it.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local ORE = "item/iron-ore"
local function make_input()
    local tiles = {}
    for x = 10, 14 do tiles[#tiles + 1] = {x = x, y = 10} end
    local run = {role = "in", flows = {ORE}, tiles = tiles, dir = Grid.EAST, head = {x = 10, y = 10}, feeds = {}}
    local rear = {port_id = "row:in:" .. ORE, row_port = true, rear = true, role = "in", kind = "item", flow_id = ORE,
        flow_ids = {ORE}, step_id = "furnace", x = 9, y = 10, travel_dir = Grid.EAST, normal_dir = Grid.EAST,
        rate_per_second = 1}
    local source = {port_id = "source:ore", role = "in", flow_id = ORE, x = 9, y = 15, travel_dir = Grid.NORTH,
        rate_per_second = 1}
    return {grid = {w = 30, h = 30}, blocks = {{block_id = "furnace", step_id = "furnace", x = 0, y = 0, w = 1, h = 1,
        entities = {}, ports = {rear}}}, perimeter_ports = {source},
        flows = {{flow_id = ORE, producers = {{port_id = "source:ore", step_id = "$external", share_per_second = 1}},
            consumers = {{step_id = "furnace", share_per_second = 1}}}},
        belt_runs = {run}, multi_flow_hands = true, catalog = {belt = {belt = "basic-belt", items_per_second = 10}}}
end
local function finish(input)
    local state, ticks = Route.begin(input), 0
    while not state.done and ticks < 10000 do ticks = ticks + 1; Route.step(state, {ops = 64}) end
    return state
end
local function belts_off_run(state)
    local result, run = {}, {}
    for x = 10, 14 do run[x .. ":10"] = true end
    for _, e in ipairs((state.result or {}).entities or {}) do
        local x, y = math.floor(e.position.x), math.floor(e.position.y)
        if not run[x .. ":" .. y] then result[#result + 1] = {x = x, y = y, dir = e.direction or e.dir, name = e.name} end
    end
    return result
end

H.test("RC1 ore arriving from below curves onto the rear port: no U-turn", function()
    local state = finish(make_input())
    H.equal(state.ok, true, "route finishes")
    local belts = belts_off_run(state)
    H.equal(#belts, 6, "six belts from (9,15) up to the rear port (9,10), no detour")
    local at_port
    for _, b in ipairs(belts) do if b.x == 9 and b.y == 10 then at_port = b end end
    H.equal(at_port ~= nil, true, "a belt sits on the rear port tile")
    H.equal(at_port and at_port.dir, Grid.EAST, "the rear port belt faces into the head: a curve")
    for _, b in ipairs(belts) do H.equal(b.x == 8, false, "nothing west of the port column (no U-turn)") end
end)
H.done("test_route_rear_curve")

--A hand can hop around its machine to face the source and shorten the final approach.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input(hops)
    return {
        grid = Grid.new(12, 8),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
            items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 3, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/iron", rate_per_second = 1,
                    x = 2, y = 3, attach_dx = 1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
            }},
            {block_id = "sink", machines = {{step_id = "sink"}}, x = 5, y = 2, w = 2, h = 2, ports = {
                {port_id = "sink-in", role = "in", kind = "item", flow_id = "item/iron", rate_per_second = 1,
                    x = 8, y = 3, attach_dx = 3, attach_dy = 1, normal_dir = Grid.EAST, travel_dir = Grid.WEST,
                    hand_x = 7, hand_y = 3, hop_options = hops},
            }},
        },
        flows = {{flow_id = "item/iron", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 1}},
            consumers = {{step_id = "sink", share_per_second = 1}}}},
    }
end

local function run(hops)
    local state = Route.begin(input(hops))
    local ticks = 0
    while not state.done and ticks < 600 do ticks = ticks + 1; Route.step(state, {ops = 100000}) end
    H.equal(state.done, true, "route finishes")
    return state
end

local hop = {hand_x = 4, hand_y = 3, port_x = 3, port_y = 3, turns = 2}

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RH1 a hop turns the sink hand toward the source and shortens the route", function()
        local fixed, hopped = run(nil), run({hop})
        H.equal(fixed.ok, true, "fixed route succeeds " .. tostring(fixed.errors and fixed.errors[1] and fixed.errors[1].code))
        H.equal(hopped.ok, true, "hopped route succeeds")
        H.equal(#hopped.result.port_slides, 1, "one hop is published")
        local published = hopped.result.port_slides[1]
        H.equal(published.port_id, "sink-in", "sink hand moved")
        H.equal(published.hop.hand_x, 4, "hand x")
        H.equal(published.hop.hand_y, 3, "hand y")
        H.equal(published.hop.port_x, 3, "port x")
        H.equal(published.hop.port_y, 3, "port y")
        H.equal(published.hop.turns, 2, "rotation")
        H.equal(#hopped.result.entities < #fixed.result.entities, true, "fewer belts")
        H.equal(hopped.work.endpoint_by_id["sink-in"].travel_dir, Grid.EAST, "travel direction rotated")
        local last
        for _, entity in ipairs(hopped.result.entities) do
            if math.floor(entity.position.x) == 3 and math.floor(entity.position.y) == 3 then last = entity end
        end
        H.equal(last and last.direction, Grid.EAST, "last belt heads along rotated travel_dir")
    end)

    H.test(shape .. " RH2 a taken hand tile refuses the hop without changing the endpoint", function()
        local state = run({{hand_x = 7, hand_y = 3, port_x = 8, port_y = 3, turns = 0}})
        H.equal(state.ok, true, "route succeeds")
        H.equal(#state.result.port_slides, 0, "blocked hop is not published")
        local endpoint = state.work.endpoint_by_id["sink-in"]
        H.equal(endpoint.x, 8, "port unchanged")
        H.equal(endpoint.y, 3, "port unchanged")
        H.equal(endpoint.hand_x, 7, "hand unchanged")
        H.equal(endpoint.hand_y, 3, "hand unchanged")
    end)
end

H.done("test_route_hop")

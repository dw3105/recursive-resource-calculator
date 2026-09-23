--A hand slides one tile along its machine face when that ends its belt straight.
--The player placed v4 on 2026-09-23 on legalcopilot-dev and boxed two belts: "Why these bends?".  A science
--input hand at (11,5) picked from (12,5) off a run along y=6, so the run jogged up one tile at its end.
--Here: machine (2..4, 2..4), input hand at (5,2) picking from (6,2), iron arriving WEST along y=3 from the
--edge.  Sliding the hand to (5,3) ends the run straight at (6,3), one belt shorter.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input(slide_options)
    return {
        grid = Grid.new(10, 8),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
            items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}},
        blocks = {
            {block_id = "m", machines = {{step_id = "m"}}, x = 2, y = 2, w = 3, h = 3, ports = {
                {port_id = "m-in", role = "in", kind = "item", flow_id = "item/iron", rate_per_second = 1,
                    x = 6, y = 2, attach_dx = 4, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.WEST,
                    slide_options = slide_options, hand_x = 5, hand_y = 2},
            }},
        },
        perimeter_ports = {{port_id = "in:item/iron", role = "in", kind = "item", flow_id = "item/iron",
            rate_per_second = 1, x = 9, y = 3, travel_dir = Grid.WEST}},
        flows = {{flow_id = "item/iron", is_fluid = false,
            producers = {{step_id = "$external", share_per_second = 1}},
            consumers = {{step_id = "m", share_per_second = 1}}}},
    }
end

local function run(slide_options)
    local state = Route.begin(input(slide_options))
    local ticks = 0
    while not state.done and ticks < 600 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route finishes")
    return state
end

local function describe(state, shape, tag)
    local rows = {}
    for _, entity in ipairs(state.result and state.result.entities or {}) do
        rows[#rows + 1] = string.format("(%d,%d)%s", math.floor(entity.position.x), math.floor(entity.position.y),
            tostring(entity.direction))
    end
    print(shape .. " " .. tag .. " " .. table.concat(rows, " "))
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " HS1 a hand slides so its belt ends straight", function()
        local fixed = run(nil)
        local slid = run({{dx = 0, dy = 1}})
        describe(fixed, shape, "fixed"); describe(slid, shape, "slid")
        H.equal(slid.ok, true, "the slid layout routes")
        H.equal(#(slid.result.port_slides or {}), 1, "one hand moved")
        local slide = (slid.result.port_slides or {})[1] or {}
        H.equal(slide.port_id, "m-in", "the machine's input hand moved")
        H.equal(slide.dy, 1, "one tile down its face")
        H.equal(#slid.result.entities, #fixed.result.entities - 1, "one belt fewer than with the hand fixed")
        for _, entity in ipairs(slid.result.entities) do
            H.equal(math.floor(entity.position.y), 3, "every belt runs straight along y=3")
        end
    end)

    H.test(shape .. " HS2 no slide is offered, the hand stays", function()
        local fixed = run(nil)
        H.equal(fixed.ok, true, "routes")
        H.equal(#(fixed.result.port_slides or {}), 0, "no hand moved")
    end)

    H.test(shape .. " HS3 a slide that buys nothing is refused", function()
        local state = run({{dx = 0, dy = -1}})
        H.equal(state.ok, true, "routes")
        H.equal(#(state.result.port_slides or {}), 0, "sliding up to (5,1) is no shorter, so the hand stays")
    end)
end

H.done("test_route_hand_slide")

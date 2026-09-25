local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Geometry = require "logic.bp.geometry"

local catalog = {entity = {
    ["assembling-machine-3"] = {name = "assembling-machine-3", tile_w = 3, tile_h = 3},
    beacon = {name = "beacon", tile_w = 3, tile_h = 3, beacon = {supply_w = 3.5, supply_h = 3.5}},
    inserter = {name = "inserter", tile_w = 1, tile_h = 1},
}, beacon = {beacon = {supply_w = 3.5, supply_h = 3.5}}, inserter = {name = "inserter"}}

local plan = {steps = {{step_id = "row", recipe = "iron", machine = "assembling-machine-3",
    machine_count = 10, inputs = {{flow_id = "item/ore", rate_per_second = 1},
        {flow_id = "item/coal", rate_per_second = 1}},
    outputs = {{flow_id = "item/plate", rate_per_second = 1}},
    beacon_groups = {{signature = "speed", name = "beacon", count_per_machine = 3,
        has_speed_module = true}}}}, flows = {
    {flow_id = "item/ore"}, {flow_id = "item/coal"}, {flow_id = "item/plate"},
}}

local state = Groups.begin({plan = plan, catalog = catalog})
for _ = 1, 1000 do
    if state.done then break end
    Groups.step(state, {ops = 10})
end
H.equal(state.done, true, "grouping completes")
local candidate = state.result and state.result.candidates and state.result.candidates[1]
H.test("a ten-machine row keeps both hands and gets three shared beacons", function()
    H.equal(candidate ~= nil, true, "row candidate exists")
    if not candidate then return end
    local block = candidate.blocks[1]
    H.equal(block.failure == nil, true, "both hand faces remain usable")
    local ys = {}
    for _, beacon in ipairs(block.beacons) do ys[beacon.y] = true end
    local row_count = 0
    for _ in pairs(ys) do row_count = row_count + 1 end
    H.equal(row_count, 1, "one shared beacon row covers the machines")
    H.equal(next(ys) > block.belt_runs[2].tiles[1].y, true, "beacon row follows output belt")
    local hands = {}
    for _, hand in ipairs(block.inserters) do hands[hand.role] = hand end
    H.equal(hands.input ~= nil and hands.output ~= nil, true, "input and output hand faces exist")
    for _, beacon in ipairs(block.beacons) do
        for _, hand in ipairs(block.inserters) do
            H.equal(beacon.x < hand.x or beacon.x >= hand.x + hand.w
                or beacon.y < hand.y or beacon.y >= hand.y + hand.h, true, "beacon avoids hand tile")
        end
        for _, run in ipairs(block.belt_runs) do
            for _, tile in ipairs(run.tiles) do
                H.equal(beacon.x < tile.x or beacon.x >= tile.x + 1
                    or beacon.y < tile.y or beacon.y >= tile.y + 1, true, "beacon avoids belt tile")
            end
        end
    end
    for _, machine in ipairs(block.machines) do
        local machine_spec = catalog.entity[machine.name]
        local box = Geometry.world_box(machine, machine_spec)
        local got = 0
        for _, beacon in ipairs(block.beacons) do
            local bx, by = Geometry.center(beacon)
            --Engine: a beacon's supply_area_distance counts from its edge (vanilla 3x3, distance 3 -> 9x9).
            local supply = Geometry.supply_box(bx, by, beacon.supply_w + beacon.w / 2, beacon.supply_h + beacon.h / 2)
            if Geometry.box_overlaps_supply(box, supply) then got = got + 1 end
        end
        H.equal(got >= 3, true, "each machine receives at least three supply boxes")
    end
end)
H.done("test_groups_beacon_row")

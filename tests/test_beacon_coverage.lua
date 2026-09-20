-- Beacon coverage is checked on the placed rectangles, independently of the grouping predicate.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

local function catalog(supply)
    return {
        entity = {
            assembler = {name = "assembler", tile_w = 3, tile_h = 3},
            beacon = {name = "beacon", tile_w = 3, tile_h = 3,
                beacon = {supply_w = supply, supply_h = supply}},
        },
        beacon = {beacon = {supply_w = supply, supply_h = supply}},
    }
end

local function plan(machine_count, signature)
    return {
        steps = {{step_id = "machine", machine = "assembler", machine_count = machine_count,
            beacon_groups = {{signature = signature, name = "beacon", count_per_machine = 1,
                has_speed_module = false, modules = {}}}}},
        flows = {}, ports = {},
    }
end

local function finish(input)
    local state = Groups.begin(input)
    for _ = 1, 20 do
        if state.done then break end
        Groups.step(state, {ops = 20})
    end
    H.equal(state.done, true, "grouping finishes")
    H.equal(state.result ~= nil and #state.result.candidates > 0, true, "a grouping candidate exists")
    return state.result.candidates[1].blocks[1]
end

local function entities_of_kind(placed, kind)
    local result = {}
    for _, entity in ipairs(placed.entities) do
        if entity.kind == kind then result[#result + 1] = entity end
    end
    return result
end

-- This is deliberately separate from Groups' source-frame predicate.  The validator asks whether the
-- machine centre is within the placed beacon centre's configured supply rectangle.
local function independently_covered(beacon, machine)
    local beacon_x = beacon.x + beacon.w / 2
    local beacon_y = beacon.y + beacon.h / 2
    local machine_x = machine.x + machine.w / 2
    local machine_y = machine.y + machine.h / 2
    return machine_x >= beacon_x - beacon.supply_w and machine_x <= beacon_x + beacon.supply_w
        and machine_y >= beacon_y - beacon.supply_h and machine_y <= beacon_y + beacon.supply_h
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B1 one beacon covers its machine in all four placed directions", function()
        local block = finish({plan = plan(1, "one"), catalog = catalog(3)})
        H.equal(#block.beacons, 1, "one physical beacon is placed")
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = dir})
            local beacon = entities_of_kind(placed, "beacon")[1]
            local machine = entities_of_kind(placed, "machine")[1]
            H.equal(independently_covered(beacon, machine), true,
                "placed beacon covers the machine at direction " .. tostring(dir))
            H.equal(#block.beacon_coverage[block.machines[1].id], 1,
                "source block records the required beacon")
        end
    end)

    H.test(shape .. " B2 one placed beacon covers both machines that request its group", function()
        local block = finish({plan = plan(2, "shared"), catalog = catalog(4)})
        H.equal(#block.beacons, 1, "sharing uses one physical beacon")
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = dir})
            local beacons = entities_of_kind(placed, "beacon")
            local machines = entities_of_kind(placed, "machine")
            for _, machine in ipairs(machines) do
                H.equal(independently_covered(beacons[1], machine), true,
                    "shared placed beacon covers both machines at direction " .. tostring(dir))
            end
        end
    end)

    H.test(shape .. " B3 a beacon just out of range covers neither machine", function()
        local placed = {entities = {
            {kind = "beacon", x = 3, y = 0, w = 3, h = 3, supply_w = 3, supply_h = 3},
            {kind = "machine", x = 0, y = 4, w = 3, h = 3},
            {kind = "machine", x = 4, y = 4, w = 3, h = 3},
        }}
        local beacon = entities_of_kind(placed, "beacon")[1]
        for _, machine in ipairs(entities_of_kind(placed, "machine")) do
            H.equal(independently_covered(beacon, machine), false, "out-of-range beacon covers neither")
        end
    end)
end

H.done("test_beacon_coverage")

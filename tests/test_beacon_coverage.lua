-- Beacon coverage is checked on the placed rectangles, independently of the grouping predicate.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Geometry = require "logic.bp.geometry"

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

-- This is deliberately separate from Groups' source-frame predicate.  It uses the same shared physical
-- conversion as the validator, with the prototype box supplied explicitly by the test.
local function independently_covered(beacon, machine, machine_spec)
    local beacon_x, beacon_y = Geometry.center(beacon)
    return Geometry.box_in_supply(machine, machine_spec, beacon_x, beacon_y, beacon.supply_w, beacon.supply_h)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B1 one beacon covers its machine in all four placed directions", function()
        local block = finish({plan = plan(1, "one"), catalog = catalog(3)})
        --One configured beacon means one physical beacon. This asserted 2 while placement put a row on each
        --side of the machine strip whether or not the near side already satisfied the requirement, so the
        --expectation recorded that waste instead of catching it.
        H.equal(#block.beacons, 1, "one configured beacon is served by exactly one physical beacon")
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = dir})
            local beacon = entities_of_kind(placed, "beacon")[1]
            local machine = entities_of_kind(placed, "machine")[1]
            H.equal(independently_covered(beacon, machine, {}), true,
                "placed beacon covers the machine at direction " .. tostring(dir))
            H.equal(#block.beacon_coverage[block.machines[1].id], 1,
                "source block records the one physical beacon that serves the machine")
        end
    end)

    H.test(shape .. " B2 one placed beacon covers both machines that request its group", function()
        local block = finish({plan = plan(2, "shared"), catalog = catalog(4)})
        --Sharing is the point: one beacon whose supply area reaches both machines serves both requirements,
        --so the block needs one beacon, never one per row.
        H.equal(#block.beacons, 1, "sharing serves both machines from one physical beacon")
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = dir})
            local beacons = entities_of_kind(placed, "beacon")
            local machines = entities_of_kind(placed, "machine")
            for _, machine in ipairs(machines) do
                H.equal(independently_covered(beacons[1], machine, {}), true,
                    "shared placed beacon covers both machines at direction " .. tostring(dir))
            end
        end
    end)

    H.test(shape .. " B3 a tile fallback is covered but a smaller collision box is not", function()
        local placed = {entities = {
            {kind = "beacon", x = 3, y = 0, w = 3, h = 3, supply_w = 3, supply_h = 3},
            {kind = "machine", x = 0, y = 4, w = 3, h = 3},
            {kind = "machine", x = 4, y = 4, w = 3, h = 3,
                collision_box = {left_top = {x = -0.7, y = -0.7}, right_bottom = {x = 0.7, y = 0.7}}},
        }}
        local beacon = entities_of_kind(placed, "beacon")[1]
        local machines = entities_of_kind(placed, "machine")
        H.equal(independently_covered(beacon, machines[1], {}), true,
            "the tile-footprint fallback overlaps the supply area")
        H.equal(independently_covered(beacon, machines[2], {collision_box = machines[2].collision_box}), false,
            "the declared smaller collision box does not")
    end)
end

H.done("test_beacon_coverage")

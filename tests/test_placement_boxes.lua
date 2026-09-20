-- Placed entity rectangles must remain disjoint after every quarter-turn of a block.
-- Keep this predicate local: the test must not trust the producer's occupancy helper.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

local function catalog()
    return {
        entity = {
            assembler = {name = "assembler", tile_w = 3, tile_h = 3},
            beacon = {name = "beacon", tile_w = 3, tile_h = 3,
                beacon = {supply_w = 3, supply_h = 3}},
            inserter = {name = "inserter", tile_w = 2, tile_h = 1},
        },
        beacon = {beacon = {supply_w = 3, supply_h = 3}},
        inserter = {name = "inserter", tile_w = 2, tile_h = 1},
    }
end

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w
        and a.y < b.y + b.h and b.y < a.y + a.h
end

local collision_boxes = {
    assembler = {left = -1.45, top = -1.45, right = 1.45, bottom = 1.45},
    beacon = {left = -1.45, top = -1.45, right = 1.45, bottom = 1.45},
    inserter = {left = -0.95, top = -0.45, right = 0.95, bottom = 0.45},
    splitter = {left = -0.95, top = -0.45, right = 0.95, bottom = 0.45},
}

local function collision_rect(entity)
    local source = collision_boxes[entity.name]
    H.equal(source ~= nil, true, "the test has an independently specified collision box")
    local points = {
        {x = source.left, y = source.top}, {x = source.left, y = source.bottom},
        {x = source.right, y = source.top}, {x = source.right, y = source.bottom},
    }
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, point in ipairs(points) do
        local x, y = Grid.rotate_vector(point.x, point.y, entity.dir)
        left, top = math.min(left, x), math.min(top, y)
        right, bottom = math.max(right, x), math.max(bottom, y)
    end
    return {
        x = entity.position.x + left, y = entity.position.y + top,
        w = right - left, h = bottom - top,
    }
end

local function plan()
    return {
        steps = {
            {step_id = "left", machine = "assembler", machine_count = 1,
                beacon_groups = {{signature = "strip", name = "beacon", count_per_machine = 1,
                    has_speed_module = false}},
                inputs = {{flow_id = "item/ore"}}, outputs = {{flow_id = "item/plate"}}},
            {step_id = "right", machine = "assembler", machine_count = 1,
                beacon_groups = {{signature = "strip", name = "beacon", count_per_machine = 1,
                    has_speed_module = false}},
                inputs = {{flow_id = "item/ore"}}, outputs = {{flow_id = "item/plate"}}},
        },
    }
end

local function first_candidate()
    local state = Groups.begin({plan = plan(), catalog = catalog(), limits = {max_candidates = 1}})
    for _ = 1, 20 do
        if state.done then break end
        Groups.step(state, {ops = 1})
    end
    H.equal(state.done, true, "grouping finishes")
    H.equal(state.result ~= nil and #state.result.candidates > 0, true, "a placement-box candidate exists")
    local block = state.result.candidates[1].blocks[1]
    local has_nonsquare = false
    local beacon_above_machine = false
    for _, member in ipairs(block.members) do
        has_nonsquare = has_nonsquare or member.w ~= member.h
        if member.kind == "beacon" then
            for _, machine in ipairs(block.machines) do
                beacon_above_machine = beacon_above_machine or member.y + member.h <= machine.y
            end
        end
    end
    H.equal(has_nonsquare, true, "the block contains a non-square member")
    H.equal(beacon_above_machine, true, "the beacon row is above the machines")
    return block
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " placed boxes do not overlap in any direction", function()
        local block = first_candidate()
        for _, direction in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = direction})
            local by_kind = {}
            for _, entity in ipairs(placed.entities) do
                by_kind[entity.kind] = by_kind[entity.kind] or {}
                by_kind[entity.kind][#by_kind[entity.kind] + 1] = entity
                H.equal(entity.x >= placed.envelope.x and entity.y >= placed.envelope.y
                    and entity.x + entity.w <= placed.envelope.x + placed.envelope.w
                    and entity.y + entity.h <= placed.envelope.y + placed.envelope.h, true,
                    "placed " .. tostring(entity.kind) .. " stays in the envelope")
            end

            -- A two-wide route entity can be put immediately outside any side of the block. Its exact box
            -- reaches back across the tile boundary, so a member touching that boundary is a real collision.
            -- The member inset is the contract under test; the route entity is deliberately not produced by
            -- Groups, keeping this check independent of its occupancy bookkeeping.
            local boundary
            for _, entity in ipairs(placed.entities) do
                if boundary == nil or entity.x + entity.w > boundary.x + boundary.w then
                    boundary = entity
                end
            end
            H.equal(boundary ~= nil, true, "the placed block has a rightmost member")
            local splitter = {
                name = "splitter", kind = "transport", dir = Grid.NORTH,
                position = {x = placed.envelope.x + placed.envelope.w + 0.5, y = boundary.position.y},
            }
            local splitter_box = collision_rect(splitter)
            for _, entity in ipairs(placed.entities) do
                H.equal(overlap(collision_rect(entity), splitter_box), false,
                    "direction " .. tostring(direction) .. " keeps a route box off placed members")
            end

            H.equal(#(by_kind.machine or {}) > 0, true, "the placed block has machines")
            H.equal(#(by_kind.inserter or {}) > 0, true, "the placed block has inserters")
            H.equal(#(by_kind.beacon or {}) > 0, true, "the placed block has beacons")
            if direction == Grid.EAST then
                local beside = false
                for _, machine in ipairs(by_kind.machine) do
                    for _, inserter in ipairs(by_kind.inserter) do
                        beside = beside or inserter.x >= machine.x + machine.w
                            or inserter.x + inserter.w <= machine.x
                    end
                end
                H.equal(beside, true, "the east placement puts an inserter beside a machine")
            end
            local boxes = {}
            for index, entity in ipairs(placed.entities) do boxes[index] = collision_rect(entity) end
            for index, entity in ipairs(placed.entities) do
                for other_index = index + 1, #placed.entities do
                    H.equal(overlap(boxes[index], boxes[other_index]), false,
                        "direction " .. tostring(direction) .. " has no placed box overlap")
                end
            end
        end
    end)
end

H.done("test_placement_boxes")

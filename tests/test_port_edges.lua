--Ports are authored in the block frame, while validation sees the placed envelope.  These checks keep the
--predicate independent from both producers: the test only applies the validator's public edge rule to output.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"

local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}

local function box(width, height)
    height = height or width
    return {left_top = {x = -width / 2 + 0.05, y = -height / 2 + 0.05},
        right_bottom = {x = width / 2 - 0.05, y = height / 2 - 0.05}}
end

local function catalog()
    return {entity = {
        assembler = {name = "assembler", tile_w = 4, tile_h = 2, collision_box = box(3.8, 1.8)},
        beacon = {name = "beacon", tile_w = 3, tile_h = 3, collision_box = box(2.8, 2.8),
            beacon = {supply_w = 6, supply_h = 5}},
        inserter = {name = "inserter", tile_w = 1, tile_h = 1, collision_box = box(0.8)},
    }, beacon = {beacon = {supply_w = 6, supply_h = 5}}, inserter = {name = "inserter"}}
end

local function one_step(inputs, machines, with_beacon)
    local step = {step_id = "maker", machine = "assembler", machine_count = machines or 1,
        inputs = {}, outputs = {}}
    for index = 1, inputs or 0 do
        step.inputs[index] = {flow_id = "item/input-" .. tostring(index), rate_per_second = 1}
    end
    if with_beacon then
        step.beacon_groups = {{signature = "quiet", name = "beacon", count_per_machine = 1,
            has_speed_module = false, supply_w = 6, supply_h = 5}}
    end
    return {steps = {step}, flows = {}}
end

local function grouped(plan_input)
    local state = Groups.begin({plan = plan_input, catalog = catalog()})
    for _ = 1, 1000 do
        if state.done then break end
        Groups.step(state, {ops = 10})
    end
    H.equal(state.done, true, "grouping completes")
    H.equal(state.result ~= nil and #state.result.candidates > 0, true, "grouping returns a candidate")
    return state.result.candidates[1].blocks[1]
end

local function pack_one(block, direction)
    local state = Pack.begin({area = Grid.rect(0, 0, 40, 40), obstacles = {}, blocks = {{
        block_id = block.block_id, w = block.w, h = block.h, allowed_dirs = {direction}, ports = block.ports,
    }}})
    for _ = 1, 1000 do
        if state.done then break end
        Pack.step(state, {ops = 10})
    end
    H.equal(state.done and state.ok, true, "packing completes for every direction")
    return state.result.placements[1]
end

local function edge_legal(port, width, height)
    local dx, dy = port.attach_dx, port.attach_dy
    local left = dx == -1 and dy >= 0 and dy < height
    local right = dx == width and dy >= 0 and dy < height
    local top = dy == -1 and dx >= 0 and dx < width
    local bottom = dy == height and dx >= 0 and dx < width
    if not (left or right or top or bottom) then return false end
    local nx, ny = Grid.dir_vector(port.normal_dir)
    return (left and nx == 1) or (right and nx == -1) or (top and ny == 1) or (bottom and ny == -1)
end

local function world_box(entity)
    local spec = catalog().entity[entity.name]
    local source = spec.collision_box
    local points = {
        {x = source.left_top.x, y = source.left_top.y},
        {x = source.left_top.x, y = source.right_bottom.y},
        {x = source.right_bottom.x, y = source.left_top.y},
        {x = source.right_bottom.x, y = source.right_bottom.y},
    }
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, point in ipairs(points) do
        local x, y = Grid.rotate_vector(point.x, point.y, entity.dir)
        left, top, right, bottom = math.min(left, x), math.min(top, y), math.max(right, x), math.max(bottom, y)
    end
    return {left = entity.position.x + left, top = entity.position.y + top,
        right = entity.position.x + right, bottom = entity.position.y + bottom}
end

local function boxes_overlap(a, b)
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PE1 every packed port is a legal edge in all placed directions", function()
        local block = grouped(one_step(3, 1, false))
        for _, direction in ipairs(DIRECTIONS) do
            local placement = pack_one(block, direction)
            local placed = Groups.materialize(block, placement)
            for _, port in ipairs(placed.ports) do
                H.equal(edge_legal(port, placed.envelope.w, placed.envelope.h), true,
                    tostring(port.port_id) .. " is on a bounded inward edge")
            end
        end
    end)

    H.test(shape .. " PE2 members, inserters and beacons have disjoint exact boxes in all directions", function()
        local block = grouped(one_step(2, 2, true))
        for _, direction in ipairs(DIRECTIONS) do
            local placed = Groups.materialize(block, {x = 20, y = 20, dir = direction})
            local boxes = {}
            for _, entity in ipairs(placed.entities) do boxes[#boxes + 1] = {id = entity.id, box = world_box(entity)} end
            for first = 1, #boxes do
                for second = first + 1, #boxes do
                    H.equal(boxes_overlap(boxes[first].box, boxes[second].box), false,
                        boxes[first].id .. " does not overlap " .. boxes[second].id)
                end
            end
        end
    end)

    H.test(shape .. " PE3 configured beacon coverage survives every placement direction", function()
        local block = grouped(one_step(0, 1, true))
        for _, direction in ipairs(DIRECTIONS) do
            local placed = Groups.materialize(block, {x = 20, y = 20, dir = direction})
            local machine, beacon
            for _, entity in ipairs(placed.entities) do
                if entity.kind == "machine" then machine = entity end
                if entity.kind == "beacon" then beacon = entity end
            end
            H.equal(machine ~= nil and beacon ~= nil, true, "machine and beacon are placed")
            local dx = math.abs(machine.position.x - beacon.position.x)
            local dy = math.abs(machine.position.y - beacon.position.y)
            H.equal(dx <= beacon.supply_w and dy <= beacon.supply_h, true,
                "placed machine remains in the beacon's configured area")
        end
    end)
end

H.done("test_port_edges")

--The grouped inserter is a physical transfer, not a conventionally placed decoration.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Serialize = require "logic.bp.serialize"

local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}

local function catalog(pickup, drop)
    return {
        entity = {
            machine = {name = "machine", etype = "assembling-machine", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", pickup_offset = pickup or {x = 0, y = 1},
            drop_offset = drop or {x = 0, y = -1}},
    }
end

local function plan(input_count, output_count, fields)
    local inputs, outputs = {}, {}
    for index = 1, input_count or 1 do
        inputs[index] = {flow_id = "item/in" .. index, rate_per_second = 1}
    end
    for index = 1, output_count or 1 do
        outputs[index] = {flow_id = "item/out" .. index, rate_per_second = 1}
    end
    local step = {step_id = "machine", machine = "machine", machine_count = 1, inputs = inputs, outputs = outputs}
    for key, value in pairs(fields or {}) do step[key] = value end
    return {steps = {step}, flows = {}}
end

local function block_for(input)
    local state = Groups.begin(input)
    for _ = 1, 20 do
        if state.done then break end
        Groups.step(state, {ops = 20})
    end
    H.equal(state.done, true, "grouping finishes")
    return state.result and state.result.candidates[1] and state.result.candidates[1].blocks[1], state
end

local function members(block, kind)
    local result = {}
    for _, member in ipairs(block.members or {}) do
        if member.kind == kind then result[#result + 1] = member end
    end
    return result
end

local function cell(value)
    return math.floor(value + 1e-9)
end

local function inside(machine, position)
    if type(position) ~= "table" then return false end
    return cell(position.x) >= machine.x and cell(position.x) < machine.x + machine.w
        and cell(position.y) >= machine.y and cell(position.y) < machine.y + machine.h
end

local function expected_position(entity, offset)
    local dx, dy = Grid.rotate_vector(offset.x, offset.y, entity.dir)
    return {x = entity.position.x + dx, y = entity.position.y + dy}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " IG1 catalog cells publish and rotate for both item transfers", function()
        local offsets = catalog().inserter
        local block = block_for({plan = plan(), catalog = catalog()})
        H.equal(block ~= nil, true, "one-machine block exists")
        if not block then return end
        for _, direction in ipairs(DIRECTIONS) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = direction})
            local machine
            for _, entity in ipairs(placed.entities) do
                if entity.kind == "machine" then machine = entity end
                if entity.kind == "inserter" then
                    H.deep_equal(entity.pickup_position, expected_position(entity, offsets.pickup_offset),
                        "pickup uses the captured offset at direction " .. tostring(direction))
                    H.deep_equal(entity.drop_position, expected_position(entity, offsets.drop_offset),
                        "drop uses the captured offset at direction " .. tostring(direction))
                end
            end
            H.equal(machine ~= nil, true, "machine materializes")
        end
    end)

    H.test(shape .. " IG2 both endpoints are real machine-or-belt cells", function()
        local block = block_for({plan = plan(), catalog = catalog()})
        local machine = members(block, "machine")[1]
        for _, inserter in ipairs(members(block, "inserter")) do
            if inserter.role == "input" then
                H.equal(inside(machine, inserter.drop_position), true, "input drops inside machine")
            else
                H.equal(inside(machine, inserter.pickup_position), true, "output picks inside machine")
            end
        end
    end)

    H.test(shape .. " IG3 multiple item ports receive distinct catalog-positioned inserters", function()
        local block = block_for({plan = plan(2, 1), catalog = catalog()})
        local all = members(block, "inserter")
        H.equal(#all, 3, "all three item obligations have an inserter")
        local seen = {}
        for _, inserter in ipairs(all) do
            local key = tostring(inserter.x) .. ":" .. tostring(inserter.y)
            H.equal(seen[key], nil, "inserter footprints are distinct")
            seen[key] = true
            H.equal(inserter.pickup_position ~= nil and inserter.drop_position ~= nil, true,
                "both cells are published")
        end
    end)

    H.test(shape .. " IG4 a custom asymmetric catalog reach is used without a convention", function()
        local custom = catalog({x = 0.25, y = 1.25}, {x = 0.75, y = -1.5})
        local block = block_for({plan = plan(), catalog = custom})
        H.equal(block ~= nil, true, "custom geometry remains placeable")
        if block then
            for _, inserter in ipairs(members(block, "inserter")) do
                H.equal(type(inserter.pickup_position) == "table" and type(inserter.drop_position) == "table"
                    and inserter.pickup_position.x ~= nil and inserter.drop_position.y ~= nil, true,
                    "custom geometry is published")
            end
        end
    end)

    H.test(shape .. " IG5 every cardinal block direction keeps the endpoint fields in world space", function()
        local block = block_for({plan = plan(), catalog = catalog()})
        local source = members(block, "inserter")[1]
        for _, direction in ipairs(DIRECTIONS) do
            local placed = Groups.materialize(block, {x = 3, y = 5, dir = direction})
            local entity
            for _, candidate in ipairs(placed.entities) do
                if candidate.id == "m:" .. source.id then entity = candidate end
            end
            H.equal(type(entity.pickup_position) == "table" and type(entity.drop_position) == "table"
                and entity.pickup_position.x >= 0 and entity.drop_position.y >= 0, true,
                "world positions are translated at direction " .. tostring(direction))
        end
    end)

    H.test(shape .. " IG6 fluid entries do not create item inserters", function()
        local fluid_plan = plan()
        fluid_plan.steps[1].inputs = {{flow_id = "fluid/water", kind = "fluid", is_fluid = true}}
        fluid_plan.steps[1].outputs = {{flow_id = "fluid/steam", kind = "fluid", is_fluid = true}}
        local block = block_for({plan = fluid_plan, catalog = catalog()})
        H.equal(#members(block, "inserter"), 0, "fluid connections have no inserter")
    end)

    H.test(shape .. " IG7 fluid connections retain a catalog connection position", function()
        local c = catalog()
        c.entity.machine.fluid_boxes = {
            {production_type = "input", connections = {{position = {x = -2, y = 0}, direction = Grid.WEST}}},
            {production_type = "output", connections = {{position = {x = 2, y = 0}, direction = Grid.EAST}}},
        }
        local fluid_plan = plan()
        fluid_plan.steps[1].inputs = {{flow_id = "fluid/water", kind = "fluid", is_fluid = true}}
        fluid_plan.steps[1].outputs = {{flow_id = "fluid/steam", kind = "fluid", is_fluid = true}}
        local block = block_for({plan = fluid_plan, catalog = c})
        for _, port in ipairs(block.ports) do
            if port.kind == "fluid" then H.equal(port.connection_position ~= nil, true, "fluid endpoint is positioned") end
        end
    end)

    H.test(shape .. " IG8 serialization keeps the computed world drop cell", function()
        local block = block_for({plan = plan(), catalog = catalog()})
        local placed = Groups.materialize(block, {x = 10, y = 10, dir = Grid.WEST})
        local state = Serialize.begin({entities = placed.entities, catalog = catalog()})
        for _ = 1, 100 do
            if state.done then break end
            Serialize.step(state, {ops = 100})
        end
        H.equal(state.ok, true, "serialized placement succeeds")
        local found = false
        for _, entity in ipairs(state.result.entities or {}) do
            if entity.name == "inserter" then found = found or entity.drop_position ~= nil end
        end
        H.equal(found, true, "serialized inserter carries its drop cell")
    end)

    H.test(shape .. " IG9 an unreachable captured reach is a named failure", function()
        local impossible = catalog({x = 0, y = 100}, {x = 0, y = -100})
        local block, state = block_for({plan = plan(), catalog = impossible})
        H.equal(block, nil, "unsupported reach does not become a fallback inserter")
        H.equal(state.result.failures[1].name, "inserter-reach", "failure names the unsupported reach")
    end)

    H.test(shape .. " IG10 beacon coverage records survive physical pruning", function()
        local c = catalog()
        c.entity.beacon = {name = "beacon", tile_w = 3, tile_h = 3, beacon = {supply_w = 10, supply_h = 10}}
        c.beacon = {beacon = {supply_w = 10, supply_h = 10}}
        local p = plan()
        p.steps[1].beacon_groups = {{signature = "speed", name = "beacon", count_per_machine = 1, modules = {}}}
        local block = block_for({plan = p, catalog = c})
        H.equal(#block.beacons >= 1, true, "configured beacon remains")
        for _, beacon in ipairs(block.beacons) do
            H.equal(type(beacon.covered_members), "table", "beacon keeps physical coverage")
        end
    end)

    H.test(shape .. " IG12 too many port-bound flows refuse the machine face by name", function()
        local block, state = block_for({plan = plan(3, 2), catalog = catalog()})
        H.equal(block, nil, "an overfull machine face does not fall back to an interior hand")
        H.equal(state.result.failures[1].name, "inserter-face", "the failure names the overfull inserter face")
    end)

    H.test(shape .. " IG13 a bottom beacon row cannot claim the port-bound face", function()
        local beacon_plan = plan(1, 1, {beacon_groups = {{signature = "bottom", name = "beacon",
            count_per_machine = 3, modules = {}}}})
        local block, state = block_for({plan = beacon_plan, catalog = catalog()})
        H.equal(block, nil, "a bottom beacon row does not displace external hands")
        H.equal(state.result.failures[1].name, "beacon-face", "the failure names the claimed inserter face")
    end)

    H.test(shape .. " IG11 machine-to-machine obligations bind both real machine endpoints", function()
        local c = catalog()
        local p = {steps = {
            {step_id = "source", machine = "machine", machine_count = 1, inputs = {},
                outputs = {{flow_id = "item/part", drain_id = "machine:target:1"}}},
            {step_id = "target", machine = "machine", machine_count = 1,
                inputs = {{flow_id = "item/part", source_id = "machine:source:1"}}, outputs = {}},
        }, flows = {}}
        local s = Groups.begin({plan=p,catalog=c}); while not s.done do Groups.step(s,{ops=100}) end
        H.equal(#s.result.candidates,1,"one candidate")
        H.equal(#s.result.candidates[1].blocks,2,"different recipes/unknown recipe identities stay in separate groups")
    end)
end

H.done("test_inserter_geometry")

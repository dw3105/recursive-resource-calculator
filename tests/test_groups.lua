--Grouping lays out machines, their beacon strips, inserters and bounded ports before a block is placed.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Geometry = require "logic.bp.geometry"

local function corners(left, top, right, bottom)
    return {left_top = {x = left, y = top}, right_bottom = {x = right, y = bottom}}
end

local function catalog()
    return {
        entity = {
            assembler = {name = "assembler", tile_w = 3, tile_h = 3},
            beacon = {name = "beacon", tile_w = 3, tile_h = 3, beacon = {supply_w = 10, supply_h = 10}},
            inserter = {name = "inserter", tile_w = 1, tile_h = 1},
        },
        beacon = {beacon = {supply_w = 10, supply_h = 10}},
        inserter = {name = "inserter"},
    }
end

local function speed_group()
    return {signature = "speed-strip", name = "beacon", count_per_machine = 1, has_speed_module = true,
        modules = {{name = "speed-module", quality = "normal"}}}
end

local function quiet_group()
    return {signature = "quality-strip", name = "beacon", count_per_machine = 1, has_speed_module = false,
        modules = {{name = "quality-module", quality = "normal"}}}
end

local function plan(quality)
    local first_group = quality and quiet_group() or speed_group()
    return {
        steps = {
            {step_id = "alpha", recipe = "alpha", machine = "assembler", machine_count = 1,
                modules = quality and {{name = "quality-module", quality = "normal"}} or {},
                beacon_groups = {first_group}, forbids_speed_beacon = quality == true,
                inputs = {{flow_id = "item/ore", rate_per_second = 1}},
                outputs = {{flow_id = "item/plate", rate_per_second = 1}}},
            {step_id = "beta", recipe = "beta", machine = "assembler", machine_count = 1,
                modules = {}, beacon_groups = {speed_group()},
                forbids_speed_beacon = false,
                inputs = {{flow_id = "item/ore", rate_per_second = 1}},
                outputs = {{flow_id = "item/plate", rate_per_second = 1}}},
        },
        flows = {
            {flow_id = "item/ore", producers = {{step_id = "$external", share_per_second = 2}},
                consumers = {{step_id = "alpha", share_per_second = 1}, {step_id = "beta", share_per_second = 1}}},
            {flow_id = "item/plate", producers = {{step_id = "alpha", share_per_second = 1},
                {step_id = "beta", share_per_second = 1}}, consumers = {{step_id = "$external", share_per_second = 2}}},
        },
        ports = {
            {port_id = "in:item/ore", role = "in", kind = "item", flow_id = "item/ore", rate_per_second = 2},
            {port_id = "out:item/plate", role = "out", kind = "item", flow_id = "item/plate", rate_per_second = 2},
        },
    }
end

local function real_one_step_plan()
    return {
        steps = {{step_id = "gear", recipe = "gear", machine = "assembler", machine_count = 1,
            inputs = {{flow_id = "item/raw", rate_per_second = 0.1}},
            outputs = {{flow_id = "item/gear", rate_per_second = 0.1}}}},
        flows = {
            {flow_id = "item/raw", producers = {{step_id = "$external", share_per_second = 0.1}},
                consumers = {{step_id = "gear", share_per_second = 0.1}}},
            {flow_id = "item/gear", producers = {{step_id = "gear", share_per_second = 0.1}},
                consumers = {{step_id = "$external", share_per_second = 0.1}}},
        },
        ports = {
            {port_id = "in:item/raw", role = "in", full_name = "item/raw", is_fluid = false,
                rate_per_second = 0.1, kind = "item", min_lanes = 1},
            {port_id = "out:item/gear", role = "out", full_name = "item/gear", is_fluid = false,
                rate_per_second = 0.1, kind = "item", min_lanes = 1},
        },
    }
end

local function fluid_catalog()
    local result = catalog()
    result.entity.assembler.etype = "assembling-machine"
    result.entity.assembler.fluid_boxes = {
        {production_type = "input", index = 1,
            pipe_connections = {{position = {x = -2, y = 0}, direction = Grid.WEST}}},
        {production_type = "output", index = 2,
            pipe_connections = {{position = {x = 2, y = 0}, direction = Grid.EAST}}},
    }
    return result
end

local function fluid_mixed_plan()
    return {
        steps = {{step_id = "fluid-mix", machine = "assembler", machine_count = 1,
            recipe = "mixed-recipe", recipe_quality = "rare",
            inputs = {{flow_id = "fluid/water", kind = "fluid", is_fluid = true, rate_per_second = 10},
                {flow_id = "item/ore", kind = "item", is_fluid = false, rate_per_second = 1}},
            outputs = {{flow_id = "fluid/steam", kind = "fluid", is_fluid = true, rate_per_second = 5},
                {flow_id = "item/product", kind = "item", is_fluid = false, rate_per_second = 1}}}},
        flows = {
            {flow_id = "fluid/water", kind = "fluid", is_fluid = true},
            {flow_id = "fluid/steam", kind = "fluid", is_fluid = true},
            {flow_id = "item/ore", kind = "item"}, {flow_id = "item/product", kind = "item"},
        },
    }
end

local function three_beacon_plan()
    return {
        steps = {{step_id = "three", machine = "assembler", machine_count = 3,
            beacon_groups = {{signature = "three", name = "beacon", count_per_machine = 3,
                has_speed_module = false, modules = {}}}}},
        flows = {}, ports = {},
    }
end

local function differing_machine_plan()
    local specs = {
        {id = "small", machine = "small", count = 1},
        {id = "medium", machine = "medium", count = 2},
        {id = "wide", machine = "wide", count = 3},
        {id = "tall", machine = "tall", count = 1},
        {id = "square", machine = "square", count = 4},
    }
    local steps = {}
    for _, spec in ipairs(specs) do
        steps[#steps + 1] = {step_id = spec.id, machine = spec.machine, machine_count = 1,
            beacon_groups = {{signature = "differing", name = "beacon", count_per_machine = spec.count,
                has_speed_module = false, modules = {}}}}
    end
    return {steps = steps, flows = {}, ports = {}, specs = specs}
end

local function differing_machine_catalog()
    local result = catalog()
    result.entity.beacon.beacon.supply_w, result.entity.beacon.beacon.supply_h = 10, 10
    result.beacon.beacon.supply_w, result.beacon.beacon.supply_h = 10, 10
    result.entity.small = {name = "small", tile_w = 2, tile_h = 2}
    result.entity.medium = {name = "medium", tile_w = 3, tile_h = 2}
    result.entity.wide = {name = "wide", tile_w = 5, tile_h = 3}
    result.entity.tall = {name = "tall", tile_w = 2, tile_h = 5}
    result.entity.square = {name = "square", tile_w = 4, tile_h = 4}
    return result
end

local function finish(input, ops)
    local state = Groups.begin(input)
    for _ = 1, 600 do
        if state.done then return state end
        Groups.step(state, {ops = ops or 1})
    end
    H.equal(state.done, true, "grouping finishes within 600 iterations; stopped in phase "
        .. tostring(state.progress and state.progress.phase))
    return state
end

local function candidates(state)
    H.equal(state.result ~= nil, true, "grouping publishes a result")
    H.equal(state.result.candidates ~= nil, true, "grouping result has candidates")
    return state.result.candidates
end

local function find_by_blocks(all, count)
    for _, candidate in ipairs(all) do if #candidate.blocks == count then return candidate end end
    return nil
end

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function assert_block_invariants(block)
    local seen = {}
    for _, machine in ipairs(block.machines) do
        H.equal(seen[machine.id], nil, "machine ids are unique")
        seen[machine.id] = true
        local coverage = block.beacon_coverage[machine.id]
        H.equal(#coverage >= 1, true, "the configured one-beacon minimum is met")
    end
    for index, member in ipairs(block.members) do
        for other_index = index + 1, #block.members do
            H.equal(overlaps(member, block.members[other_index]), false, "block members do not overlap")
        end
        H.equal(member.x >= 0 and member.y >= 0, true, "member starts inside the block")
        H.equal(member.x + member.w <= block.w and member.y + member.h <= block.h, true,
            "member ends inside the block")
    end
    for _, port in ipairs(block.ports) do
        local bounded = (port.attach_dx == -1 or port.attach_dx == block.w)
            and port.attach_dy >= 0 and port.attach_dy < block.h
            or (port.attach_dy == -1 or port.attach_dy == block.h)
            and port.attach_dx >= 0 and port.attach_dx < block.w
        H.equal(bounded, true, "port attaches on a bounded outside tile")
        local dx, dy = Grid.dir_vector(port.normal_dir)
        local inward = (port.attach_dx < 0 and dx == 1) or (port.attach_dx >= block.w and dx == -1)
            or (port.attach_dy < 0 and dy == 1) or (port.attach_dy >= block.h and dy == -1)
        H.equal(inward, true, "port normal points into the block")
        if port.role == "out" then
            H.equal(port.travel_dir, Grid.dir_opposite(port.normal_dir), "output travel points outward")
        end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " G1 sharing two machines offers one physical beacon before two separate blocks", function()
        local state = finish({plan = plan(false), catalog = catalog()})
        local all = candidates(state)
        local grouped = find_by_blocks(all, 1)
        local separate = find_by_blocks(all, 2)
        H.equal(grouped ~= nil, true, "a shared grouping candidate exists")
        H.equal(separate ~= nil, true, "a separate grouping candidate exists")
        H.equal(grouped.physical_beacon_count < separate.physical_beacon_count, true,
            "shared strip has fewer physical beacons")
    end)

    H.test(shape .. " G2 every requested machine appears exactly once in every candidate", function()
        local all = candidates(finish({plan = plan(false), catalog = catalog()}))
        for _, candidate in ipairs(all) do
            local counts = {alpha = 0, beta = 0}
            for _, block in ipairs(candidate.blocks) do
                for _, machine in ipairs(block.machines) do counts[machine.step_id] = counts[machine.step_id] + 1 end
            end
            H.equal(counts.alpha, 1, "alpha appears once")
            H.equal(counts.beta, 1, "beta appears once")
        end
    end)

    H.test(shape .. " G3 a machine receives its configured minimum beacon coverage", function()
        local all = candidates(finish({plan = plan(false), catalog = catalog()}))
        for _, candidate in ipairs(all) do
            for _, block in ipairs(candidate.blocks) do assert_block_invariants(block) end
        end
    end)

    H.test(shape .. " G4 quality machines are isolated from speed beacons in all four orientations", function()
        local all = candidates(finish({plan = plan(true), catalog = catalog()}))
        H.equal(#all > 0, true, "a valid mixed quality and speed plan still has candidates")
        for _, candidate in ipairs(all) do
            for _, block in ipairs(candidate.blocks) do
                for _, beacon in ipairs(block.beacons) do
                    for _, machine in ipairs(block.machines) do
                        if beacon.has_speed_module and machine.forbids_speed_beacon then
                            H.equal(false, true, "quality machine is not covered by a speed beacon")
                        end
                    end
                end
                for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
                    local placed = Groups.materialize(block, {x = 10, y = 20, dir = dir})
                    for _, beacon in ipairs(placed.entities) do
                        if beacon.kind == "beacon" and beacon.has_speed_module then
                            for _, machine in ipairs(placed.entities) do
                                if machine.kind == "machine" and machine.forbids_speed_beacon then
                                    H.equal(false, true, "rotated quality machine is not speed-covered")
                                end
                            end
                        end
                    end
                end
            end
        end
        local impossible = {
            steps = {{step_id = "quality", machine = "assembler", machine_count = 1,
                modules = {{name = "quality-module", quality = "normal"}},
                beacon_groups = {speed_group()}, forbids_speed_beacon = true}},
        }
        H.equal(#candidates(finish({plan = impossible, catalog = catalog()})), 0,
            "a quality machine cannot satisfy a speed-beacon minimum")
    end)

    H.test(shape .. " G5 ports are outside and bounded, with inward normals and outward output travel", function()
        local grouped = find_by_blocks(candidates(finish({plan = plan(false), catalog = catalog()})), 1)
        H.equal(grouped ~= nil, true, "grouped block exists")
        assert_block_invariants(grouped.blocks[1])
    end)

    H.test(shape .. " G6 members do not overlap and materialize inside every placed envelope", function()
        local grouped = find_by_blocks(candidates(finish({plan = plan(false), catalog = catalog()})), 1)
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local block = grouped.blocks[1]
            local placed = Groups.materialize(block, {x = 50, y = 70, dir = dir})
            for _, entity in ipairs(placed.entities) do
                H.equal(entity.x >= placed.envelope.x and entity.y >= placed.envelope.y, true,
                    "placed member begins inside envelope")
                H.equal(entity.x + entity.w <= placed.envelope.x + placed.envelope.w
                    and entity.y + entity.h <= placed.envelope.y + placed.envelope.h, true,
                    "placed member ends inside envelope")
                H.equal(entity.id:sub(1, 2), "m:", "materialized member id is namespaced")
            end
            for _, port in ipairs(placed.ports) do
                H.equal(port.normal_dir ~= nil and port.travel_dir ~= nil, true, "port rotates with block")
            end
        end
    end)

    H.test(shape .. " G7 the same plan produces byte-for-byte equal grouping candidates twice", function()
        local first = candidates(finish({plan = plan(false), catalog = catalog()}))
        local second = candidates(finish({plan = plan(false), catalog = catalog()}))
        H.deep_equal(first, second, "grouping is deterministic")
    end)

    H.test(shape .. " G8 candidates are sorted by physical beacon count then id", function()
        local all = candidates(finish({plan = plan(false), catalog = catalog()}))
        for index = 2, #all do
            local previous, current = all[index - 1], all[index]
            H.equal(previous.physical_beacon_count < current.physical_beacon_count
                or (previous.physical_beacon_count == current.physical_beacon_count and previous.id <= current.id), true,
                "candidate order is deterministic and beacon-first")
        end
    end)

    H.test(shape .. " G9 real plan ports stay on the perimeter while block ports name their step", function()
        local grouped = find_by_blocks(candidates(finish({plan = real_one_step_plan(), catalog = catalog()})), 1)
        H.equal(grouped ~= nil, true, "real one-step block exists")
        if grouped then
            local block = grouped.blocks[1]
            H.equal(#block.ports, 2, "the block has one port for each step connection")
            for _, port in ipairs(block.ports) do
                H.equal(port.step_id, "gear", "block port names the step it serves")
                H.equal(tostring(port.step_id):sub(1, 6) == "block:", false,
                    "block port does not use the synthetic block id")
            end
        end
    end)

    H.test(shape .. " G10 mixed item and fluid connections keep only item inserters and oriented fluid boxes", function()
        local all = candidates(finish({plan = fluid_mixed_plan(), catalog = fluid_catalog()}))
        H.equal(#all > 0, true, "mixed fluid block exists")
        local block = all[1] and all[1].blocks[1]
        H.equal(block ~= nil, true, "mixed fluid block is present")
        if not block then return end
        local item_inserters, fluid_inserters = 0, 0
        local fluid_ports = {}
        for _, member in ipairs(block.members) do
            if member.kind == "inserter" then
                if tostring(member.flow_id):sub(1, 6) == "fluid/" then fluid_inserters = fluid_inserters + 1
                else item_inserters = item_inserters + 1 end
            end
        end
        for _, port in ipairs(block.ports) do
            if port.kind == "fluid" then fluid_ports[#fluid_ports + 1] = port end
        end
        H.equal(fluid_inserters, 0, "fluid connections never receive item inserters")
        H.equal(item_inserters, 2, "both item connections retain their inserter")
        H.equal(#fluid_ports, 2, "both fluid connections retain a port")
        for _, port in ipairs(fluid_ports) do
            H.equal(port.connection ~= nil, true, "fluid port carries a real fluid-box connection")
            H.equal(port.machine, "assembler", "fluid port names its machine prototype")
        end
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 10, y = 20, dir = dir})
            local machine
            for _, entity in ipairs(placed.entities) do
                if entity.kind == "machine" then machine = entity end
                if entity.kind == "inserter" then
                    H.equal(tostring(entity.flow_id):sub(1, 6) == "fluid/", false,
                        "rotated materialization has no fluid inserter")
                end
            end
            H.equal(machine.recipe, "mixed-recipe", "rotated machine keeps recipe")
            H.equal(machine.recipe_quality, "rare", "rotated machine keeps recipe quality")
            for _, port in ipairs(placed.ports) do
                if port.kind == "fluid" then
                    local expected = port.role == "in" and Grid.WEST or Grid.EAST
                    H.equal(Grid.rotate_dir(port.connection.direction, dir), Grid.rotate_dir(expected, dir),
                        "pipe connection rotates with its machine")
                end
            end
        end
    end)
    --A port list wider than its block used to spill onto an unbounded side column.  Both edge families are legal,
    --and the left edge gives output routes a second side to leave the block.
    H.test(shape .. " G12 every attach tile stays on a bounded edge", function()
        H.new_world(shape)
        local plan_input = real_one_step_plan()
        for index = 1, 6 do
            plan_input.steps[1].inputs[#plan_input.steps[1].inputs + 1] =
                {flow_id = "item/extra" .. index, rate_per_second = 0.1}
            plan_input.flows[#plan_input.flows + 1] = {flow_id = "item/extra" .. index,
                producers = {{step_id = "$external", share_per_second = 0.1}},
                consumers = {{step_id = "gear", share_per_second = 0.1}}}
        end
        plan_input.catalog = catalog()
        local state = finish(plan_input)
        local block = candidates(state)[1].blocks[1]
        for _, port in ipairs(block.ports) do
            local on_horizontal = (port.attach_dy == -1 or port.attach_dy == block.h)
                and port.attach_dx >= 0 and port.attach_dx < block.w
            local on_vertical = (port.attach_dx == -1 or port.attach_dx == block.w)
                and port.attach_dy >= 0 and port.attach_dy < block.h
            H.equal(on_horizontal or on_vertical, true, tostring(port.port_id) .. " attaches on a bounded edge")
        end
        H.equal(type(block.port_sides), "table", "the block names the sides its ports use")
    end)

    H.test(shape .. " BG1 a machine covered by its collision box is covered, and by its tile footprint alone is not", function()
        local beacon = {x = -2, y = 1.5, w = 3, h = 3}
        local beacon_x, beacon_y = Geometry.center(beacon)
        local machine = {x = 3, y = 4, w = 3, h = 3}
        local supply = Geometry.supply_box(beacon_x, beacon_y, 3, 3)
        local footprint = Geometry.world_box(machine, {})
        local collision = Geometry.world_box(machine, {collision_box = corners(-2.5, -0.7, -1.5, 0.7)})
        H.equal(Geometry.box_overlaps_supply(footprint, supply), false,
            "the tile footprint misses the explicit supply edge")
        H.equal(Geometry.box_overlaps_supply(collision, supply), true,
            "the declared collision box is the geometry that is covered")
    end)

    H.test(shape .. " BG2 an asymmetric collision box survives all four placed directions", function()
        local beacon = {x = 3, y = 0, w = 3, h = 3, supply_w = 3, supply_h = 3}
        local spec = {collision_box = corners(-1.5, -0.25, 0.5, 0.25)}
        local beacon_x, beacon_y = Geometry.center(beacon)
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local machine = {x = 3, y = 3, w = 3, h = 3, dir = dir}
            H.equal(Geometry.box_in_supply(machine, spec, beacon_x, beacon_y, 3, 3), true,
                "the asymmetric box overlaps in direction " .. tostring(dir))
        end
    end)

    H.test(shape .. " BG3 a machine configured for three beacons overlaps three supply areas", function()
        local tight = catalog()
        tight.entity.beacon.beacon.supply_w, tight.entity.beacon.beacon.supply_h = 3, 3
        tight.beacon.beacon.supply_w, tight.beacon.beacon.supply_h = 3, 3
        local all = candidates(finish({plan = three_beacon_plan(), catalog = tight}))
        H.equal(#all > 0, true, "three configured beacons produce a candidate")
        if #all > 0 then
            local block = all[1].blocks[1]
            for _, machine in ipairs(block.machines) do
                H.equal(#block.beacon_coverage[machine.id] >= 3, true,
                    "machine " .. tostring(machine.id) .. " overlaps three physical supply areas")
            end
        end
    end)

    H.test(shape .. " BG4 a block of five machines of differing sizes each gets its configured count", function()
        local input = differing_machine_plan()
        local all = candidates(finish({plan = input, catalog = differing_machine_catalog(), limits = {max_candidates = 1}}))
        local grouped = find_by_blocks(all, 1)
        H.equal(grouped ~= nil, true, "the five differing machines share a block")
        if grouped then
            local requested = {}
            for _, spec in ipairs(input.specs) do requested[spec.id] = spec.count end
            for _, machine in ipairs(grouped.blocks[1].machines) do
                H.equal(#grouped.blocks[1].beacon_coverage[machine.id] >= requested[machine.step_id], true,
                    "machine " .. tostring(machine.step_id) .. " gets its configured count")
            end
        end
    end)

    H.test(shape .. " BG5 count_per_machine is never assigned to a physical beacon count", function()
        local input = three_beacon_plan()
        input.steps[1].machine_count = 1
        local all = candidates(finish({plan = input, catalog = catalog()}))
        H.equal(#all > 0, true, "the three-beacon block exists")
        if #all > 0 then
            local block = all[1].blocks[1]
            H.equal(block.physical_beacon_count, #block.beacons,
                "the block reports the physical placement count")
            H.equal(block.beacon_count, block.physical_beacon_count,
                "the compatibility beacon count is physical")
            H.equal(block.physical_beacon_count >= 3, true,
                "the physical count meets the per-machine requirement")
            H.equal(#block.beacon_coverage[block.machines[1].id] >= 3, true,
                "the configured requirement remains three")
        end
    end)
end

H.done("test_groups")

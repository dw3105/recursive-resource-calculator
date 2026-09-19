--Grouping lays out machines, their beacon strips, inserters and bounded ports before a block is placed.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

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
        H.equal(#coverage, 1, "the configured one-beacon minimum is met")
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
end

H.done("test_groups")

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

local function finish(input, ops)
    local state = Groups.begin(input)
    for _ = 1, 100 do
        if state.done then return state end
        Groups.step(state, {ops = ops or 1})
    end
    H.equal(state.done, true, "grouping completes within the test budget")
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
        if port.role == "out" then H.equal(port.travel_dir, Grid.SOUTH, "output travel points outward") end
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
end

H.done("test_groups")

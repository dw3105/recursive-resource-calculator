--Validator-only splitter guard.  These are hand-built candidates: the route is already published, so every row
--asks Validate to judge the splitter footprint, directed outputs, and the real transport obligations again.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Validate = require "logic.bp.validate"

local function box(radius)
    return {left_top = {x = -radius, y = -radius}, right_bottom = {x = radius, y = radius}}
end

local function catalog()
    return {
        entity = {
            machine = {name = "machine", etype = "assembling-machine", tile_w = 5, tile_h = 3,
                collision_box = box(0.4), collision_mask = {"machine-layer"}, needs_power = false},
            ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"belt-layer"}, needs_power = false},
            splitter = {name = "splitter", etype = "splitter", tile_w = 2, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"splitter-layer"}, needs_power = false},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"inserter-layer"}, needs_power = false,
                items_per_second = 5},
        },
        inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        belt = {items_per_second = 10, lane_items_per_second = 5},
    }
end

local function ent(t)
    t.w = t.w or 1
    t.h = t.h or 1
    return t
end

local function plan(outputs)
    return {steps = {{step_id = "maker", machine = "machine", machine_count = 1,
        inputs = {{flow_id = "item/input", rate_per_second = 1}}, outputs = outputs}}}
end

local function splitter_geometry(facing, branch)
    local anchor, second
    if facing == Grid.EAST then
        anchor, second = {x = 9, y = 4}, {x = 9, y = 5}
    elseif facing == Grid.SOUTH then
        anchor, second = {x = 8, y = 5}, {x = 9, y = 5}
    else
        anchor, second = {x = 8, y = 5}, {x = 9, y = 5}
    end
    local selected = branch == "second" and second or anchor
    local dx, dy = Grid.dir_vector(facing)
    return {
        facing = facing, anchor = anchor, second = second, selected = selected,
        position = {x = (anchor.x + second.x) / 2 + 0.5, y = (anchor.y + second.y) / 2 + 0.5},
        approach = {x = selected.x - dx, y = selected.y - dy},
        output = {x = selected.x + dx, y = selected.y + dy},
    }
end

local function report_row(row, geometry)
    print(string.format("%s splitter position=(%.1f,%.1f) facing=%d covers tiles (%d,%d),(%d,%d)",
        row, geometry.position.x, geometry.position.y, geometry.facing,
        geometry.anchor.x, geometry.anchor.y, geometry.second.x, geometry.second.y))
end

local function belt(id, x, y, dir, flow_ids)
    local result = ent{id = id, name = "transport-belt", kind = "belt", type = "belt", x = x, y = y, dir = dir}
    if type(flow_ids) == "table" then
        result.flow_ids = flow_ids
    else
        result.flow_id = flow_ids
    end
    return result
end

local function splitter_entity(geometry, flow_ids)
    return {
        id = "splitter", name = "splitter", kind = "belt", type = "splitter", splitter = true,
        position = geometry.position, dir = geometry.facing, direction = geometry.facing, flow_ids = flow_ids,
    }
end

local function output_hand(id, x, y, flow_id, machine_port_id, belt_id)
    return ent{id = id, name = "inserter", kind = "inserter", type = "inserter", x = x, y = y, dir = Grid.EAST,
        rate_per_second = 1, flow_id = flow_id, role = "output", machine_id = "machine",
        pickup_target = "machine", drop_target = belt_id,
        pickup_position = {x = x - 0.5, y = y + 0.5}, drop_position = {x = x + 1.5, y = y + 0.5},
        port_id = machine_port_id}
end

local function input_side()
    return {
        belt("in-0", 0, 5, Grid.EAST, "item/input"),
        belt("in-1", 1, 5, Grid.EAST, "item/input"),
        belt("in-2", 2, 5, Grid.EAST, "item/input"),
        ent{id = "input-hand", name = "inserter", kind = "inserter", type = "inserter", x = 3, y = 5,
            dir = Grid.EAST, rate_per_second = 1, flow_id = "item/input", role = "input", machine_id = "machine",
            pickup_target = "in-2", drop_target = "machine",
            pickup_position = {x = 2.5, y = 5.5}, drop_position = {x = 4.5, y = 5.5}},
    }
end

local function output_port(flow_id, port_id, x, y)
    return {port_id = port_id, flow_id = flow_id, role = "out", x = x, y = y,
        rate_per_second = 1, travel_dir = Grid.EAST}
end

local function candidate(row, facing, branch, negative)
    local geometry = splitter_geometry(facing, branch)
    local flows = {"item/output"}
    local outputs = {{flow_id = "item/output", rate_per_second = 1}}
    local output_specs = {{flow_id = "item/output", port_id = "output-port", suffix = "a"}}
    if row == "VS5" then
        flows = {"item/output-a", "item/output-b"}
        outputs = {
            {flow_id = "item/output-a", rate_per_second = 1},
            {flow_id = "item/output-b", rate_per_second = 1},
        }
        output_specs = {
            {flow_id = "item/output-a", port_id = "output-port-a", suffix = "a"},
            {flow_id = "item/output-b", port_id = "output-port-b", suffix = "b"},
        }
    end

    local entities = {
        ent{id = "machine", name = "machine", kind = "machine", type = "machine", x = 4, y = 4, w = 5, h = 3,
            step_id = "maker", quality = "normal"},
    }
    for _, item in ipairs(input_side()) do entities[#entities + 1] = item end

    local ports = {
        {port_id = "input-port", flow_id = "item/input", role = "in", x = 0, y = 5,
            rate_per_second = 1, travel_dir = Grid.EAST},
        {port_id = "machine-input", flow_id = "item/input", role = "in", x = 3, y = 5,
            rate_per_second = 1, step_id = "maker", travel_dir = Grid.EAST},
    }
    local segments = {{id = "s-input", segment_id = "s-input", kind = "belt", flow_id = "item/input",
        capacity_per_second = 10, length = 3, allocations = {{flow_id = "item/input", sink = "step:maker", rate_per_second = 1}}}}
    local bindings = {{source_port_id = "input-port", sink_port_id = "machine-input", sink = "step:maker",
        flow_id = "item/input", segment_id = "s-input", rate_per_second = 1}}

    --Each row has a genuine machine output hand and a port/binding obligation.  In VS5 the two hands use the
    --two splitter lanes independently; the splitter itself explicitly carries both flows.
    for index, spec in ipairs(output_specs) do
        local output_y = row == "VS5" and (3 + index) or geometry.approach.y
        local hand_x = geometry.approach.x - 1
        local hand_id = "output-hand-" .. spec.suffix
        local first_belt_id = "out-pre-" .. spec.suffix
        local output_port_id = spec.port_id
        entities[#entities + 1] = output_hand(hand_id, hand_x, output_y, spec.flow_id, output_port_id, first_belt_id)
        entities[#entities + 1] = belt(first_belt_id, geometry.approach.x, output_y, facing, spec.flow_id)
        if index == 1 then entities[#entities + 1] = splitter_entity(geometry, flows) end

        local output_x, output_y_after = geometry.output.x, geometry.output.y
        if row == "VS5" then output_y_after = output_y end
        local output_belt_id = "out-1-" .. spec.suffix
        entities[#entities + 1] = belt(output_belt_id, output_x, output_y_after, facing, spec.flow_id)
        local final_belt_id = "out-2-" .. spec.suffix
        local next_x, next_y = Grid.dir_vector(facing)
        local final_x, final_y = output_x + next_x, output_y_after + next_y
        --The final tile is the external port's tile.  VS6 deliberately omits the first output tile, so the
        --same real hand now reaches a splitter whose directed continuation ends at the footprint.
        if not negative then
            entities[#entities + 1] = belt(final_belt_id, final_x, final_y, facing, spec.flow_id)
        end
        ports[#ports + 1] = output_port(spec.flow_id, output_port_id, final_x, final_y)
        local segment_id = "s-output-" .. spec.suffix
        segments[#segments + 1] = {id = segment_id, segment_id = segment_id, kind = "belt", flow_id = spec.flow_id,
            capacity_per_second = 10, length = negative and 2 or 3,
            allocations = {{flow_id = spec.flow_id, sink = "port:" .. output_port_id, rate_per_second = 1}}}
        local machine_port_id = "machine-output-" .. spec.suffix
        ports[#ports + 1] = {port_id = machine_port_id, flow_id = spec.flow_id, role = "out",
            x = hand_x, y = output_y, rate_per_second = 1, step_id = "maker", travel_dir = Grid.EAST}
        bindings[#bindings + 1] = {source_port_id = machine_port_id, sink_port_id = output_port_id,
            sink = "port:" .. output_port_id, flow_id = spec.flow_id, segment_id = segment_id, rate_per_second = 1}
    end

    local flow_records = {{flow_id = "item/input", producers = {{step_id = "$external", share_per_second = 1}},
        consumers = {{step_id = "maker", share_per_second = 1}}}}
    for _, spec in ipairs(output_specs) do
        flow_records[#flow_records + 1] = {flow_id = spec.flow_id,
            producers = {{step_id = "maker", share_per_second = 1}},
            consumers = {{step_id = "$external", port_id = spec.port_id, share_per_second = 1}}}
    end

    return {
        grid_w = 20, grid_h = 12, wires = {}, entities = entities, flows = flow_records,
        ports = ports, segments = segments, bindings = bindings,
    }, plan(outputs), geometry
end

local function finish(input, built_plan, no_splitter_spec)
    local cat = catalog()
    --The player's captured catalog lists machines only: no `splitter` entity spec (green science sheet,
    --2026-09-24). A splitter is still two tiles wide.
    if no_splitter_spec then cat.entity.splitter = nil end
    local state = Validate.begin({candidate = input, plan = built_plan, catalog = cat})
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        H.equal(ticks < 1000, true, "validator finishes")
        Validate.step(state, {ops = 1000})
    end
    return state
end

local function codes(state)
    local result = {}
    for _, record in ipairs(state.errors or {}) do result[#result + 1] = record.code end
    return result
end

local function has_code(state, wanted)
    for _, code in ipairs(codes(state)) do if code == wanted then return true end end
    return false
end

local function named(state, wanted)
    for _, record in ipairs(state.errors or {}) do
        if record.code == wanted then
            for _, id in ipairs(record.ids or {}) do if id ~= nil and id ~= "" then return true end end
        end
    end
    return false
end

local function rejects(state, code, label)
    H.equal(state.ok, false, label .. ": the candidate is rejected")
    H.equal(has_code(state, code), true,
        label .. ": rejected as " .. code .. ", got " .. table.concat(codes(state), ","))
    H.equal(named(state, code), true, label .. ": the rejection names the entity or port at fault")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " VS1 anchor output accepts a NORTH splitter run", function()
        local input, built_plan, geometry = candidate("VS1", Grid.NORTH, "anchor", false)
        report_row("VS1", geometry)
        local state = finish(input, built_plan)
        H.equal(state.ok, true, "the belt run leaves the splitter by its anchor output: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS2 second-tile output accepts the same NORTH splitter run", function()
        local input, built_plan, geometry = candidate("VS2", Grid.NORTH, "second", false)
        report_row("VS2", geometry)
        local state = finish(input, built_plan)
        H.equal(state.ok, true, "the belt run leaves the splitter by its second-tile output: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS3 EAST splitter footprint follows its position", function()
        local input, built_plan, geometry = candidate("VS3", Grid.EAST, "anchor", false)
        report_row("VS3", geometry)
        local state = finish(input, built_plan)
        H.equal(state.ok, true, "the EAST splitter run uses its implied north-south footprint: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS4 SOUTH splitter keeps the already-correct north-south registration", function()
        local input, built_plan, geometry = candidate("VS4", Grid.SOUTH, "anchor", false)
        report_row("VS4", geometry)
        local state = finish(input, built_plan)
        H.equal(state.ok, true, "the SOUTH splitter run validates: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS5 two declared flows are witnessed through one splitter", function()
        local input, built_plan, geometry = candidate("VS5", Grid.EAST, "anchor", false)
        report_row("VS5", geometry)
        local state = finish(input, built_plan)
        H.equal(state.ok, true, "both flows leave their splitter lanes: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS6 a missing splitter continuation is named as route discontinuous", function()
        local input, built_plan, geometry = candidate("VS6", Grid.NORTH, "anchor", true)
        report_row("VS6", geometry)
        local state = finish(input, built_plan)
        rejects(state, "BP_V_ROUTE_DISCONTINUOUS", "VS6 missing splitter continuation")
    end)

    H.test(shape .. " VS7 second-tile output is walked when the catalog has no splitter spec", function()
        local input, built_plan, geometry = candidate("VS7", Grid.NORTH, "second", false)
        report_row("VS7", geometry)
        local state = finish(input, built_plan, true)
        H.equal(state.ok, true, "a splitter is two tiles wide without a catalog spec: " .. table.concat(codes(state), ","))
    end)

    H.test(shape .. " VS8 EAST splitter footprint without a catalog spec", function()
        local input, built_plan, geometry = candidate("VS8", Grid.EAST, "anchor", false)
        report_row("VS8", geometry)
        local state = finish(input, built_plan, true)
        H.equal(state.ok, true, "the EAST splitter covers its north-south pair without a catalog spec: " .. table.concat(codes(state), ","))
    end)
end

H.done("test_validate_splitter")

--The validator's physical result is useful evidence, not only a boolean.  Keep one small independent factory
--here so a broken transfer names the first illegal transport step and a valid transfer publishes its order.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[copy(key)] = copy(child) end
    return result
end

local function ent(value)
    value.w, value.h = value.w or 1, value.h or 1
    value.position = {x = value.x + value.w / 2, y = value.y + value.h / 2}
    return value
end

local function catalog()
    return {inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        entity = {
            machine = {name = "machine", etype = "assembling-machine", tile_w = 3, tile_h = 3,
                needs_power = true, energy_usage_w = 1, module_slots = 0},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
                needs_power = true, energy_usage_w = 1, items_per_second = 5},
            belt = {name = "belt", etype = "transport-belt", tile_w = 1, tile_h = 1},
            pole = {name = "pole", etype = "electric-pole", tile_w = 1, tile_h = 1,
                supply_w = 8, supply_h = 8, wire_reach = 8},
        }}
end

local function plan()
    return {steps = {{step_id = "step", machine = "machine", machine_quality = "normal", machine_count = 1,
        recipe = "recipe", recipe_quality = "normal", modules = {},
        inputs = {{full_name = "item/in", rate_per_second = 1}},
        outputs = {{full_name = "item/out", rate_per_second = 1}}}}}
end

local function candidate()
    return {grid_w = 12, grid_h = 10, wires = {},
        entities = {
            ent{id = "machine", name = "machine", kind = "machine", type = "machine", x = 3, y = 3, w = 3, h = 3,
                step_id = "step", quality = "normal", recipe = "recipe", recipe_quality = "normal", modules = {}},
            ent{id = "in-belt", name = "belt", kind = "belt", type = "belt", x = 0, y = 4, dir = 4,
                flow_id = "item/in"},
            ent{id = "in-belt2", name = "belt", kind = "belt", type = "belt", x = 1, y = 4, dir = 4,
                flow_id = "item/in"},
            ent{id = "inserter-in", name = "inserter", kind = "inserter", type = "inserter", x = 2, y = 4, dir = 4,
                flow_id = "item/in", role = "input", machine_id = "machine", pickup_target = "external-in",
                drop_target = "machine", rate_per_second = 1},
            ent{id = "inserter-out", name = "inserter", kind = "inserter", type = "inserter", x = 6, y = 4, dir = 4,
                flow_id = "item/out", role = "output", machine_id = "machine", pickup_target = "machine",
                drop_target = "external-out", rate_per_second = 1},
            ent{id = "out-belt", name = "belt", kind = "belt", type = "belt", x = 7, y = 4, dir = 4,
                flow_id = "item/out"},
            ent{id = "out-belt2", name = "belt", kind = "belt", type = "belt", x = 8, y = 4, dir = 4,
                flow_id = "item/out"},
            ent{id = "out-belt3", name = "belt", kind = "belt", type = "belt", x = 9, y = 4, dir = 4,
                flow_id = "item/out"},
            ent{id = "out-belt4", name = "belt", kind = "belt", type = "belt", x = 10, y = 4, dir = 4,
                flow_id = "item/out"},
            ent{id = "out-belt5", name = "belt", kind = "belt", type = "belt", x = 11, y = 4, dir = 4,
                flow_id = "item/out"},
            ent{id = "pole", name = "pole", kind = "pole", type = "pole", x = 4, y = 7},
        },
        flows = {{flow_id = "item/in"}, {flow_id = "item/out"}},
        ports = {
            {port_id = "external-in", flow_id = "item/in", role = "in", x = 0, y = 4, rate_per_second = 1},
            {port_id = "machine-in", flow_id = "item/in", role = "in", step_id = "step", x = 2, y = 4, rate_per_second = 1},
            {port_id = "machine-out", flow_id = "item/out", role = "out", step_id = "step", x = 6, y = 4, rate_per_second = 1},
            {port_id = "external-out", flow_id = "item/out", role = "out", x = 11, y = 4, rate_per_second = 1},
        },
        segments = {
            {id = "input", segment_id = "input", kind = "belt", flow_id = "item/in", capacity_per_second = 5, length = 2,
                allocations = {{flow_id = "item/in", sink = "step:step", rate_per_second = 1}}},
            {id = "output", segment_id = "output", kind = "belt", flow_id = "item/out", capacity_per_second = 5, length = 5,
                allocations = {{flow_id = "item/out", sink = "port:external-out", rate_per_second = 1}}},
        },
        bindings = {
            {source_port_id = "external-in", sink_port_id = "machine-in", flow_id = "item/in", sink = "step:step",
                segment_id = "input", rate_per_second = 1},
            {source_port_id = "machine-out", sink_port_id = "external-out", flow_id = "item/out",
                sink = "port:external-out", segment_id = "output", rate_per_second = 1},
        }}
end

local function run(input)
    local state = Validate.begin({candidate = input, plan = plan(), catalog = catalog()})
    while not state.done do Validate.step(state, {ops = 100000}) end
    return state
end

local function error_with_code(state, code)
    for _, record in ipairs(state.errors or {}) do if record.code == code then return record end end
    return nil
end

local function codes(state)
    local result = {}
    for _, record in ipairs(state.errors or {}) do result[#result + 1] = record.code end
    return table.concat(result, ",")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " WI1 a valid transfer publishes an ordered connection witness", function()
        local state = run(candidate())
        H.equal(state.ok, true, "the witness control is independently valid: " .. codes(state))
        local witnesses = ((state.result or {}).metrics or {}).connection_witnesses or {}
        H.equal(#witnesses, 2, "both required transfers publish a witness")
        local output
        for _, witness in ipairs(witnesses) do if witness.role == "output" then output = witness break end end
        H.equal(output ~= nil, true, "the output transfer has a witness")
        H.deep_equal(output and output.ids, {"machine", "inserter-out", "out-belt", "out-belt2", "out-belt3", "out-belt4", "out-belt5", "external-out"},
            "the witness preserves source-to-sink order")
    end)

    H.test(shape .. " WI2 a broken directed step names the first illegal entity", function()
        local control = run(candidate())
        H.equal(control.ok, true, "the broken-transfer mutation starts from a valid candidate")
        local broken = copy(candidate())
        for _, entity in ipairs(broken.entities) do if entity.id == "inserter-out" then entity.dir = 12 end end
        local state = run(broken)
        local failure = error_with_code(state, "BP_V_TRANSFER_BROKEN")
        H.equal(state.ok, false, "the broken transfer is rejected")
        H.equal(failure ~= nil, true, "the directed witness rejection has the transfer reason: " .. codes(state))
        H.equal(failure and failure.detail and failure.detail.first_illegal_step, "inserter-out",
            "the rejection names the first illegal step")
        H.equal(failure and failure.detail and failure.detail.reason, "belt is missing at the inserter outward tile",
            "the rejection says that the belt is missing")
    end)

    H.test(shape .. " WI3 a missing inserter is named separately from a broken belt", function()
        local control = run(candidate())
        H.equal(control.ok, true, "the missing-inserter mutation starts from a valid candidate")
        local broken = copy(candidate())
        for index, entity in ipairs(broken.entities) do
            if entity.id == "inserter-out" then table.remove(broken.entities, index) break end
        end
        local state = run(broken)
        local failure = error_with_code(state, "BP_V_TRANSFER_BROKEN")
        H.equal(state.ok, false, "the missing inserter is rejected")
        H.equal(failure and failure.detail and failure.detail.reason, "inserter is missing for the required transfer",
            "the rejection says that the inserter is missing")
    end)

    H.test(shape .. " WI4 a candidate with no transport names that whole-candidate cause", function()
        local control = run(candidate())
        H.equal(control.ok, true, "the no-transport mutation starts from a valid candidate")
        local broken = copy(candidate())
        local kept = {}
        for _, entity in ipairs(broken.entities) do
            if entity.kind ~= "belt" then kept[#kept + 1] = entity end
        end
        broken.entities = kept
        local state = run(broken)
        local failure = error_with_code(state, "BP_V_ROUTE_DISCONTINUOUS")
        H.equal(state.ok, false, "the candidate with no transport is rejected")
        H.equal(failure and failure.detail and failure.detail.reason, "candidate has no transport",
            "the rejection says that the candidate has no transport")
    end)
end

H.done("test_physical_witness")

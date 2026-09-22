--Every code the census counts must still be reachable.  Spine owns this file; no lane may edit it.
--
--Why it exists.  The lane gate is monotone: a lane must drive its named codes DOWN and raise none.  That
--contract has exactly one cheap way to satisfy it dishonestly -- delete the check that emits the code.  The
--census then reads zero and the gate reports an improvement, which is the same class of mistake round 14
--made when logic/bp/validate.lua:1217 returned before any physical check ran and the generator reported
--ok=true on a factory that produced nothing.
--
--So for each counted code this file builds a candidate that MUST provoke it and asserts the validator still
--emits it.  A lane that removes an emitter zeroes its census and turns this file red in the same run.
--
--It cannot live beside the lane-owned suites: docs/tasks/120.manifest handed tests/test_validate.lua to the
--same lane that owned logic/bp/validate.lua, so a lane could weaken the test that guards it.  This file is
--PRESERVE-listed in every round 15 task and appears in no lane manifest.
--
--CL0 runs first and must PASS.  A control that rejects everything would make every mutation below pass for the
--wrong reason, which is exactly the trap tests/test_blueprint_physical_contract.lua documents at its head.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local function ent(t)
    t.w = t.w or 1
    t.h = t.h or 1
    t.position = {x = t.x + t.w / 2, y = t.y + t.h / 2}
    return t
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
    return result
end

local function catalog()
    return {
        --A base inserter reaches BEHIND itself to pick up and drops in the direction it faces, so in the
        --north frame the pickup offset is +y and the drop offset is -y (contract 26.3).
        inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        entity = {
            ["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine",
                tile_w = 3, tile_h = 3, module_slots = 4, needs_power = true, energy_usage_w = 375000,
                crafting_speed = 1.25},
            ["inserter"] = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
                needs_power = true, energy_usage_w = 13000, items_per_second = 5,
                pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
            ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1},
            ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole",
                tile_w = 1, tile_h = 1, supply_w = 7, supply_h = 7, wire_w = 9, wire_h = 9},
        },
    }
end

local function plan()
    return {steps = {{
        step_id = "gear", machine = "assembling-machine-3", machine_quality = "normal", machine_count = 1,
        recipe = "iron-gear-wheel", recipe_quality = "normal", modules = {},
        inputs = {{full_name = "item/iron-plate", rate_per_second = 2}},
        outputs = {{full_name = "item/iron-gear-wheel", rate_per_second = 1}},
    }}}
end

--belt x=0,1 -> inserter x=2 -> machine x=3..5 -> inserter x=6 -> belt x=7..11.  Every published pickup and
--drop cell genuinely touches what it claims to serve.  Block port ids are step-qualified, which is the shape
--contract 26.9.4 freezes and the shape the physical contract already asserts.
local function candidate()
    return {
        grid_w = 12, grid_h = 12, wires = {},
        entities = {
            ent{id = "m1", name = "assembling-machine-3", kind = "machine", type = "machine",
                x = 3, y = 3, w = 3, h = 3, step_id = "gear", quality = "normal",
                recipe = "iron-gear-wheel", recipe_quality = "normal", modules = {}},
            ent{id = "in-belt", name = "transport-belt", kind = "belt", type = "belt", x = 0, y = 4, dir = 4},
            ent{id = "in-belt2", name = "transport-belt", kind = "belt", type = "belt", x = 1, y = 4, dir = 4},
            ent{id = "in-ins", name = "inserter", kind = "inserter", type = "inserter", x = 2, y = 4, dir = 4,
                rate_per_second = 2, flow_id = "item/iron-plate",
                pickup_target = "in-belt2", drop_target = "m1",
                pickup_position = {x = 1.5, y = 4.5}, drop_position = {x = 3.5, y = 4.5}},
            ent{id = "out-ins", name = "inserter", kind = "inserter", type = "inserter", x = 6, y = 4, dir = 4,
                rate_per_second = 1, flow_id = "item/iron-gear-wheel",
                pickup_target = "m1", drop_target = "out-belt",
                pickup_position = {x = 5.5, y = 4.5}, drop_position = {x = 7.5, y = 4.5}},
            ent{id = "out-belt", name = "transport-belt", kind = "belt", type = "belt", x = 7, y = 4, dir = 4},
            ent{id = "out-belt2", name = "transport-belt", kind = "belt", type = "belt", x = 8, y = 4, dir = 4},
            ent{id = "out-belt3", name = "transport-belt", kind = "belt", type = "belt", x = 9, y = 4, dir = 4},
            ent{id = "out-belt4", name = "transport-belt", kind = "belt", type = "belt", x = 10, y = 4, dir = 4},
            ent{id = "out-belt5", name = "transport-belt", kind = "belt", type = "belt", x = 11, y = 4, dir = 4},
            ent{id = "pole", name = "medium-electric-pole", kind = "pole", type = "pole", x = 4, y = 7},
        },
        flows = {{flow_id = "item/iron-plate"}, {flow_id = "item/iron-gear-wheel"}},
        ports = {
            {port_id = "in:item/iron-plate", flow_id = "item/iron-plate", role = "in", x = 0, y = 4,
             rate_per_second = 2},
            {port_id = "out:item/iron-gear-wheel", flow_id = "item/iron-gear-wheel", role = "out",
             x = 11, y = 4, rate_per_second = 1},
            {port_id = "gear:in:item/iron-plate", flow_id = "item/iron-plate", role = "in", x = 2, y = 4,
             step_id = "gear", rate_per_second = 2},
            {port_id = "gear:out:item/iron-gear-wheel", flow_id = "item/iron-gear-wheel", role = "out",
             x = 6, y = 4, step_id = "gear", rate_per_second = 1},
        },
        segments = {
            {id = "s-in", segment_id = "s-in", kind = "belt", flow_id = "item/iron-plate",
             capacity_per_second = 15, length = 3,
             allocations = {{flow_id = "item/iron-plate", sink = "step:gear", rate_per_second = 2}}},
            {id = "s-out", segment_id = "s-out", kind = "belt", flow_id = "item/iron-gear-wheel",
             capacity_per_second = 15, length = 5,
             allocations = {{flow_id = "item/iron-gear-wheel", sink = "port:out:item/iron-gear-wheel",
                             rate_per_second = 1}}},
        },
        bindings = {
            {source_port_id = "in:item/iron-plate", sink_port_id = "gear:in:item/iron-plate",
             sink = "step:gear", flow_id = "item/iron-plate", segment_id = "s-in", rate_per_second = 2},
            {source_port_id = "gear:out:item/iron-gear-wheel", sink_port_id = "out:item/iron-gear-wheel",
             sink = "port:out:item/iron-gear-wheel", flow_id = "item/iron-gear-wheel",
             segment_id = "s-out", rate_per_second = 1},
        },
    }
end

local function validate(built)
    local state = Validate.begin({candidate = built, plan = plan(), catalog = catalog()})
    local guard = 0
    while not state.done do
        guard = guard + 1
        if guard > 1000 then error("validation did not finish") end
        Validate.step(state, {ops = 100000})
    end
    return state
end

local function has_code(state, wanted)
    for _, record in ipairs(state.errors or {}) do
        if record.code == wanted then return true end
    end
    return false
end

local function all_codes(state)
    local seen = {}
    for _, record in ipairs(state.errors or {}) do seen[#seen + 1] = tostring(record.code) end
    return table.concat(seen, ",")
end

local function entity_named(built, id)
    for _, entity in ipairs(built.entities) do
        if entity.id == id then return entity end
    end
    error("no entity named " .. tostring(id))
end

local function mutate(change)
    local built = copy(candidate())
    change(built)
    return built
end

H.test("CL0 the control factory is accepted, so every mutation below means something", function()
    local state = validate(candidate())
    H.equal(state.ok, true, "the control must pass first: " .. all_codes(state))
end)

H.test("CL1 BP_V_INSERTER_GEOMETRY is still emitted when a drop cell is empty ground", function()
    local state = validate(mutate(function(built)
        --The drop cell leaves the machine and lands on bare ground two tiles above it.
        local inserter = entity_named(built, "in-ins")
        inserter.drop_position = {x = 3.5, y = 1.5}
    end))
    H.equal(has_code(state, "BP_V_INSERTER_GEOMETRY"), true,
        "a drop cell on empty ground must still reject: " .. all_codes(state))
end)

H.test("CL2 BP_V_TRANSFER_BROKEN is still emitted when no belt reaches the pickup cell", function()
    local state = validate(mutate(function(built)
        --The inserter, its target and the obligation all survive; only the belt under the pickup cell goes.
        for index, entity in ipairs(built.entities) do
            if entity.id == "in-belt2" then table.remove(built.entities, index) break end
        end
    end))
    H.equal(has_code(state, "BP_V_TRANSFER_BROKEN") or has_code(state, "BP_V_ROUTE_DISCONTINUOUS"), true,
        "a starved inserter must still reject: " .. all_codes(state))
end)

H.test("CL3 BP_V_TRANSPORT_UNUSED is still emitted for a belt that serves no obligation", function()
    local state = validate(mutate(function(built)
        built.entities[#built.entities + 1] =
            ent{id = "stray", name = "transport-belt", kind = "belt", type = "belt", x = 1, y = 9, dir = 4}
    end))
    H.equal(has_code(state, "BP_V_TRANSPORT_UNUSED"), true,
        "a belt serving nothing must still reject: " .. all_codes(state))
end)

H.test("CL4 BP_V_ROUTE_DISCONTINUOUS is still emitted when no transport exists at all", function()
    local state = validate(mutate(function(built)
        local kept = {}
        for _, entity in ipairs(built.entities) do
            if entity.kind ~= "belt" then kept[#kept + 1] = entity end
        end
        built.entities = kept
    end))
    H.equal(has_code(state, "BP_V_ROUTE_DISCONTINUOUS") or has_code(state, "BP_V_TRANSFER_BROKEN"), true,
        "a factory with no transport must still reject: " .. all_codes(state))
end)

--CL5 is the round 16 addition.  BP_V_TARGET_SHORTFALL counts 3 on the player's sheet, one per candidate, far
--under the census sensitivity floor of 50, so the rate gate cannot judge it and only a direct test can.  It
--carries its OWN control, because the code needs a flow that declares producers and consumers and the shared
--control candidate declares neither: without the first half, the second half could pass because the flow was
--given consumers rather than because the allocation fell short.
local function with_declared_flow(reached)
    return mutate(function(built)
        for _, flow in ipairs(built.flows) do
            if flow.flow_id == "item/iron-gear-wheel" then
                --Produced must equal consumed or BP_V_FLOW_IMBALANCE fires first and CL5 proves nothing.
                flow.producers = {{step_id = "gear", share_per_second = 1}}
                flow.consumers = {{step_id = "$external", share_per_second = 1}}
            end
        end
        for _, segment in ipairs(built.segments) do
            if segment.segment_id == "s-out" then
                for _, allocation in ipairs(segment.allocations) do allocation.rate_per_second = reached end
            end
        end
    end)
end

H.test("CL5a the declared-flow control reaches its sink, so the shortfall below means something", function()
    local state = validate(with_declared_flow(1))
    H.equal(has_code(state, "BP_V_TARGET_SHORTFALL"), false,
        "a sink that receives its whole share must not report a shortfall: " .. all_codes(state))
end)

H.test("CL5b BP_V_TARGET_SHORTFALL is still emitted when a sink receives less than it requires", function()
    --One quarter of the required rate arrives at the external sink, logic/bp/validate.lua:996-999.
    local state = validate(with_declared_flow(0.25))
    H.equal(has_code(state, "BP_V_TARGET_SHORTFALL"), true,
        "a sink short of its required share must still reject: " .. all_codes(state))
end)

H.done("census_codes_live")

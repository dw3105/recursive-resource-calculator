--The contract a delivered blueprint must meet to physically produce. Spine owns this file; no lane may edit it.
--
--Round 12 delivered a blueprint the generator called valid and the player pasted into a blank factory. Measured
--on that exact candidate against its real seven-step plan: removing every belt left 76 entities and still
--validated; so did removing every pipe, every inserter, and setting every machine to legendary quality against
--a normal-quality plan. A validator that accepts a factory with no transport at all is not validating
--production, and no amount of rearranging entities fixes that.
--
--So each case here starts from an INDEPENDENTLY VALID positive control -- a hand-built belt -> inserter ->
--machine -> inserter -> belt factory, not something the generator produced -- proves that control passes, then
--applies ONE mutation and requires a SPECIFIC failure naming the affected entity or port. A base that rejects
--everything proves nothing, which is why PC1 runs first and every mutation asserts its own code.
--
--The public API only: Groups, Pack, Route, Validate, Serialize. Never debug.getupvalue -- round 12 reached
--build_block through an upvalue and the seam broke the moment grouping was refactored.
local H = require "tests.harness"

local Validate = require "logic.bp.validate"
local Groups = require "logic.bp.groups"
local Serialize = require "logic.bp.serialize"

--Every construction path is bounded. A contract test that hangs reports nothing.
local INSTRUCTION_BOUND = 20000000

local function bounded(fn, ...)
    local ticks = 0
    debug.sethook(function()
        ticks = ticks + 1
        if ticks > INSTRUCTION_BOUND / 10000 then error("instruction bound reached", 2) end
    end, "", 10000)
    local ok, result = pcall(fn, ...)
    debug.sethook()
    if not ok then error(result, 2) end
    return result
end

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

-- ---------------------------------------------------------------------------------------------------------
-- The positive control: a small factory that really works.
-- ---------------------------------------------------------------------------------------------------------

local function catalog()
    return {
        inserter = {items_per_second = 5},
        entity = {
            ["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine",
                tile_w = 3, tile_h = 3, module_slots = 4, needs_power = true, energy_usage_w = 375000,
                crafting_speed = 1.25},
            ["electric-furnace"] = {name = "electric-furnace", etype = "furnace", tile_w = 3, tile_h = 3,
                module_slots = 2, needs_power = true, energy_usage_w = 180000, crafting_speed = 2},
            ["inserter"] = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
                needs_power = true, energy_usage_w = 13000, items_per_second = 5},
            ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1},
            ["underground-belt"] = {name = "underground-belt", etype = "underground-belt", tile_w = 1, tile_h = 1},
            ["pipe"] = {name = "pipe", etype = "pipe", tile_w = 1, tile_h = 1},
            ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole",
                tile_w = 1, tile_h = 1, supply_w = 7, supply_h = 7, wire_w = 9, wire_h = 9},
            ["beacon"] = {name = "beacon", etype = "beacon", tile_w = 3, tile_h = 3, module_slots = 2,
                needs_power = true, energy_usage_w = 480000, beacon = {supply_w = 9, supply_h = 9}},
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

--Belt at x=0,1 -> inserter at x=2 -> machine at x=3..5 -> inserter at x=6 -> belt at x=7..11.
--The inserter pickup and drop cells genuinely touch what they claim to serve, which is the whole point.
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
                rate_per_second = 2, pickup_target = "in-belt2", drop_target = "m1"},
            ent{id = "out-ins", name = "inserter", kind = "inserter", type = "inserter", x = 6, y = 4, dir = 4,
                rate_per_second = 1, pickup_target = "m1", drop_target = "out-belt"},
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
            {port_id = "out:item/iron-gear-wheel", flow_id = "item/iron-gear-wheel", role = "out", x = 11, y = 4,
             rate_per_second = 1},
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

local function validate(built, built_plan)
    return bounded(function()
        local state = Validate.begin({candidate = built, plan = built_plan or plan(), catalog = catalog()})
        local guard = 0
        while not state.done do
            guard = guard + 1
            if guard > 1000 then error("validation did not finish") end
            Validate.step(state, {ops = 100000})
        end
        return state
    end)
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

--One mutation, applied to a fresh copy of the control. Returns the mutated candidate.
local function mutate(change)
    local built = copy(candidate())
    change(built)
    return built
end

local function drop_entities(built, predicate)
    local kept = {}
    for _, entity in ipairs(built.entities) do
        if not predicate(entity) then kept[#kept + 1] = entity end
    end
    built.entities = kept
end

local function entity_named(built, id)
    for _, entity in ipairs(built.entities) do if entity.id == id then return entity end end
    return nil
end

--A rejection must name its own failure class AND the entity or port at fault. "Something failed" cannot be
--repaired by the person reading it, and it cannot distinguish a real catch from a base that was already broken.
local function rejects(state, code, label)
    H.equal(state.ok, false, label .. ": the mutated factory is rejected")
    H.equal(has_code(state, code), true,
        label .. ": rejected as " .. code .. ", got " .. table.concat(codes(state), ","))
    H.equal(named(state, code), true, label .. ": the rejection names the entity or port at fault")
end

for _, shape in ipairs(H.shapes()) do

    -- -----------------------------------------------------------------------------------------------------
    -- The control itself. Everything below is worthless if this does not pass.
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " PC1 the hand-built working factory is accepted", function()
        local state = validate(candidate())
        H.equal(state.ok, true, "the positive control validates: " .. table.concat(codes(state), ","))
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- 25.1 Recipe and machine identity
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " ID1 a machine with its recipe deleted is rejected", function()
        local state = validate(mutate(function(built) entity_named(built, "m1").recipe = nil end))
        rejects(state, "BP_V_MACHINE_IDENTITY", "recipe deleted")
    end)

    H.test(shape .. " ID2 a machine carrying a different recipe is rejected", function()
        local state = validate(mutate(function(built)
            entity_named(built, "m1").recipe = "copper-cable"
        end))
        rejects(state, "BP_V_MACHINE_IDENTITY", "recipe replaced")
    end)

    H.test(shape .. " ID3 a recipe written onto a furnace is rejected", function()
        local state = validate(mutate(function(built)
            local machine = entity_named(built, "m1")
            machine.name = "electric-furnace"
            machine.recipe = "iron-gear-wheel"
        end), (function()
            local p = plan()
            p.steps[1].machine = "electric-furnace"
            return p
        end)())
        rejects(state, "BP_V_MACHINE_IDENTITY", "recipe on a furnace")
    end)

    H.test(shape .. " ID4 a different machine prototype is rejected", function()
        local state = validate(mutate(function(built)
            entity_named(built, "m1").name = "electric-furnace"
        end))
        rejects(state, "BP_V_MACHINE_IDENTITY", "machine prototype changed")
    end)

    H.test(shape .. " ID5 a different machine quality is rejected", function()
        local state = validate(mutate(function(built)
            entity_named(built, "m1").quality = "legendary"
        end))
        rejects(state, "BP_V_MACHINE_IDENTITY", "machine quality changed")
    end)

    H.test(shape .. " ID6 a lost module is rejected", function()
        local wanted = plan()
        wanted.steps[1].modules = {{name = "speed-module-3", quality = "normal", count = 4}}
        local built = copy(candidate())
        entity_named(built, "m1").modules = {}
        rejects(validate(built, wanted), "BP_V_MODULE_MISMATCH", "module removed")
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- 25.2 Physical transfer, both directions and end to end
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " TR1 removing the input inserter breaks the input path", function()
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.id == "in-ins" end)
        end))
        rejects(state, "BP_V_TRANSFER_BROKEN", "input inserter removed")
    end)

    H.test(shape .. " TR2 removing the output inserter breaks the output path", function()
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.id == "out-ins" end)
        end))
        rejects(state, "BP_V_TRANSFER_BROKEN", "output inserter removed")
    end)

    H.test(shape .. " TR3 an input inserter moved off its machine breaks the input path", function()
        local state = validate(mutate(function(built)
            local inserter = entity_named(built, "in-ins")
            inserter.y = 9
            inserter.position = {x = inserter.x + 0.5, y = 9.5}
        end))
        rejects(state, "BP_V_TRANSFER_BROKEN", "input inserter moved off target")
    end)

    H.test(shape .. " TR4 a reversed output inserter breaks the output path", function()
        local state = validate(mutate(function(built)
            local inserter = entity_named(built, "out-ins")
            inserter.dir = 12
            inserter.pickup_target, inserter.drop_target = "out-belt", "m1"
        end))
        rejects(state, "BP_V_TRANSFER_BROKEN", "output inserter reversed")
    end)

    H.test(shape .. " TR5 removing a middle belt makes the route discontinuous", function()
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.id == "out-belt3" end)
        end))
        rejects(state, "BP_V_ROUTE_DISCONTINUOUS", "middle belt removed")
    end)

    H.test(shape .. " TR6 a reversed middle belt makes the route discontinuous", function()
        local state = validate(mutate(function(built)
            entity_named(built, "out-belt3").dir = 12
        end))
        rejects(state, "BP_V_ROUTE_DISCONTINUOUS", "middle belt reversed")
    end)

    H.test(shape .. " TR7 removing EVERY belt is rejected, not accepted with 76 entities", function()
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.name == "transport-belt" end)
        end))
        rejects(state, "BP_V_ROUTE_DISCONTINUOUS", "every belt removed")
    end)

    H.test(shape .. " TR8 removing EVERY inserter is rejected", function()
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.name == "inserter" end)
        end))
        rejects(state, "BP_V_TRANSFER_BROKEN", "every inserter removed")
    end)

    H.test(shape .. " TR9 a disconnected stub at the pickup cell is not a source structure", function()
        --The belt the inserter picks from no longer reaches the external supply port: its only neighbour is
        --gone, so items never arrive, although every declared allocation still reads correctly.
        local state = validate(mutate(function(built)
            drop_entities(built, function(entity) return entity.id == "in-belt" end)
        end))
        rejects(state, "BP_V_ROUTE_DISCONTINUOUS", "input belt no longer reaches its supply port")
    end)

    H.test(shape .. " TR10 a branch loaded past its physical path is rejected", function()
        local state = validate(mutate(function(built)
            built.segments[2].capacity_per_second = 0.25
        end))
        rejects(state, "BP_V_TRANSFER_CAPACITY", "output branch over capacity")
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- 25.3 Beacons: extra influence is legal, a speed beacon over a quality machine is not
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " BE1 influence above the configured count is accepted", function()
        local wanted = plan()
        wanted.steps[1].beacon_groups = {{signature = "b", name = "beacon", count_per_machine = 1,
            has_speed_module = true, modules = {{name = "speed-module-3", quality = "normal"}}}}
        local built = copy(candidate())
        for index = 1, 2 do
            built.entities[#built.entities + 1] = ent{
                id = "b" .. index, name = "beacon", kind = "beacon", type = "beacon",
                x = index == 1 and 3 or 3, y = index == 1 and 0 or 7, w = 3, h = 3,
                signature = "b", has_speed_module = true,
                modules = {{name = "speed-module-3", quality = "normal"}},
            }
        end
        local state = validate(built, wanted)
        H.equal(has_code(state, "BP_V_BEACON_COVERAGE_SHORT"), false,
            "two beacons never report a shortage against a requirement of one")
    end)

    H.test(shape .. " BE2 a speed beacon reaching a quality machine is rejected", function()
        local wanted = plan()
        wanted.steps[1].has_quality_module = true
        wanted.steps[1].forbids_speed_beacon = true
        local built = copy(candidate())
        local machine = entity_named(built, "m1")
        machine.has_quality_module = true
        machine.forbids_speed_beacon = true
        built.entities[#built.entities + 1] = ent{
            id = "b1", name = "beacon", kind = "beacon", type = "beacon", x = 3, y = 0, w = 3, h = 3,
            signature = "b", has_speed_module = true,
            modules = {{name = "speed-module-3", quality = "normal"}},
        }
        rejects(validate(built, wanted), "BP_V_SPEED_BEACON_ON_QUALITY", "speed beacon over a quality machine")
    end)

    H.test(shape .. " BE3 two machines of one step keep their own influence records", function()
        local wanted = plan()
        wanted.steps[1].machine_count = 2
        local built = copy(candidate())
        local second = copy(entity_named(built, "m1"))
        second.id = "m2"
        second.x, second.y = 3, 8
        second.position = {x = 4.5, y = 9.5}
        built.entities[#built.entities + 1] = second
        built.entities[#built.entities + 1] = ent{
            id = "b1", name = "beacon", kind = "beacon", type = "beacon", x = 3, y = 0, w = 3, h = 3,
            signature = "b", modules = {{name = "speed-module-3", quality = "normal"}},
        }
        local state = validate(built, wanted)
        local metrics = (state.result or {}).metrics or {}
        local per_instance = metrics.beacon_effects_by_entity_id or metrics.beacon_effects_by_instance
        H.equal(per_instance ~= nil, true,
            "effects are keyed per machine instance; keyed by step, m2 overwrites m1's evidence")
        if per_instance then
            H.equal(per_instance["m1"] ~= nil and per_instance["m2"] ~= nil, true,
                "both machine instances of one step keep a record")
        end
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- 25.4 Metrics
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " MT1 a nonempty transport path never measures zero cost", function()
        local state = validate(candidate())
        H.equal(state.ok, true, "the control validates before its score is read")
        local score = (state.result or {}).score or {}
        H.equal(type(score.transport_cost) == "number" and score.transport_cost > 0, true,
            "transport_cost is measured from placed geometry, never defaulted to zero")
        H.equal(type(score.production_area) == "number" and score.production_area > 0, true,
            "production_area is measured and excludes the roboport envelope")
    end)

    H.test(shape .. " MT2 an unmeasurable metric is reported, never treated as zero", function()
        local state = validate(mutate(function(built)
            for _, segment in ipairs(built.segments) do segment.length = nil end
        end))
        rejects(state, "BP_V_METRIC_MISSING", "segment length absent")
    end)

    H.test(shape .. " MT3 the comparator ranks by the published order", function()
        local cheap = {beacon_count = 1, production_area = 100, transport_cost = 50, pole_count = 1,
            transport_entities = 10, coord_key = "a"}
        local roomy = {beacon_count = 1, production_area = 400, transport_cost = 10, pole_count = 1,
            transport_entities = 10, coord_key = "a"}
        H.equal(Validate.compare(cheap, roomy), -1,
            "production_area outranks transport_cost, so the smaller factory wins")
        local fewer = {beacon_count = 1, production_area = 400, transport_cost = 99, pole_count = 9,
            transport_entities = 99, coord_key = "z"}
        local more = {beacon_count = 2, production_area = 10, transport_cost = 1, pole_count = 1,
            transport_entities = 1, coord_key = "a"}
        H.equal(Validate.compare(fewer, more), -1, "beacon_count still ranks first")
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- 25.1 / 25.5 The producer carries identity, and the serialized artifact is reconciled
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " SR1 grouping carries the recipe onto the machine member", function()
        local built = bounded(function()
            local state = Groups.begin({plan = plan(), catalog = catalog()})
            local guard = 0
            while not state.done do
                guard = guard + 1
                if guard > 2000 then error("grouping did not finish") end
                Groups.step(state, {ops = 5000})
            end
            return state
        end)
        H.equal(built.done and built.result ~= nil, true, "grouping produced a result")
        local machines = 0
        local carried = 0
        for _, group in ipairs((built.result or {}).candidates or {}) do
            for _, block in ipairs(group.blocks or {}) do
                for _, machine in ipairs(block.machines or {}) do
                    machines = machines + 1
                    if machine.recipe == "iron-gear-wheel" and machine.recipe_quality == "normal" then
                        carried = carried + 1
                    end
                end
            end
        end
        H.equal(machines > 0, true, "grouping placed a machine at all")
        H.equal(carried, machines, "every machine member carries its step's recipe and recipe quality")
    end)

    H.test(shape .. " SR2 a furnace member never receives a recipe field", function()
        local wanted = plan()
        wanted.steps[1].machine = "electric-furnace"
        local built = bounded(function()
            local state = Groups.begin({plan = wanted, catalog = catalog()})
            local guard = 0
            while not state.done do
                guard = guard + 1
                if guard > 2000 then error("grouping did not finish") end
                Groups.step(state, {ops = 5000})
            end
            return state
        end)
        local checked = 0
        for _, group in ipairs((built.result or {}).candidates or {}) do
            for _, block in ipairs(group.blocks or {}) do
                for _, machine in ipairs(block.machines or {}) do
                    checked = checked + 1
                    H.equal(machine.recipe, nil, "a furnace takes its recipe from its input item, never a field")
                end
            end
        end
        H.equal(checked > 0, true, "a furnace member was actually inspected")
    end)

    H.test(shape .. " SR3 serialization preserves the recipe and its quality", function()
        local state = bounded(function()
            local serialized = Serialize.begin({candidate = candidate(), catalog = catalog()})
            local guard = 0
            while not serialized.done do
                guard = guard + 1
                if guard > 2000 then error("serialization did not finish") end
                Serialize.step(serialized, {ops = 5000})
            end
            return serialized
        end)
        local machines = 0
        for _, entity in ipairs(((state.result or {}).entities) or {}) do
            if entity.name == "assembling-machine-3" then
                machines = machines + 1
                H.equal(entity.recipe, "iron-gear-wheel", "the serialized machine carries its recipe")
                H.equal(entity.recipe_quality, "normal", "the serialized machine carries its recipe quality")
            end
        end
        H.equal(machines, 1, "exactly one machine reached the serialized artifact")
    end)

    H.test(shape .. " SR4 a mutation applied only at serialization is detected", function()
        --The internal candidate stays valid; only the exported artifact is wrong. A digest recomputed over
        --that artifact identifies it faithfully and still proves nothing about whether it matches the plan.
        local artifact = bounded(function()
            local serialized = Serialize.begin({candidate = candidate(), catalog = catalog()})
            local guard = 0
            while not serialized.done do
                guard = guard + 1
                if guard > 2000 then error("serialization did not finish") end
                Serialize.step(serialized, {ops = 5000})
            end
            return serialized.result
        end)
        for _, entity in ipairs((artifact or {}).entities or {}) do
            if entity.name == "assembling-machine-3" then entity.recipe = "copper-cable" end
        end
        H.equal(type(Validate.reconcile_artifact), "function",
            "Validate exposes the artifact reconciliation entry point the production path calls")
        if type(Validate.reconcile_artifact) == "function" then
            local outcome = Validate.reconcile_artifact({artifact = artifact, plan = plan(), catalog = catalog()})
            H.equal(outcome ~= nil and outcome.ok, false, "a serializer-only recipe change is rejected")
        end
    end)
end

H.done("test_blueprint_physical_contract")

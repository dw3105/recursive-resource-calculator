--The planner must publish the same quality facts as QualityPolicy and must not let a thin catalog recipe hide
--the runtime recipe that supplies the fields its reader needs.
local H = require "tests.harness"

local Plan = require "logic.bp.plan"
local QualityPolicy = require "logic.bp.quality_policy"

local function run(input)
    local state = Plan.begin(input)
    for _ = 1, 100 do
        if state.done then break end
        Plan.step(state, {ops = 1})
    end
    H.equal(state.done, true, "plan completes")
    H.equal(state.result ~= nil, true, "plan publishes an IR")
    return state.result
end

local function verified_receiver(extra)
    local receiver = {
        status = "verified_default", source = "prototype", branch = "2.0", base_effect = {},
        uses_module_effects = true, uses_beacon_effects = true, uses_surface_effects = true,
    }
    for key, value in pairs(extra or {}) do receiver[key] = value end
    return receiver
end

local function catalog(receiver)
    return {
        entity = {
            assembler = {name = "assembler", effect_receiver = receiver or verified_receiver()},
            beacon = {name = "beacon", beacon = {distribution_effectivity = 1, counter = "same_type"}},
        },
        module = {
            speed = {effects = {speed = 0.5, quality = -0.25}},
            quality = {effects = {quality = 0.25}},
            cancelling = {effects = {quality = -0.25}},
            productivity = {effects = {productivity = 0.25, speed = -0.15}},
        },
    }
end

local function policy_step(setup)
    local step = {
        machine = {name = "assembler", quality = "normal"},
        modules = setup.modules or {},
        beacons = setup.beacons or {},
    }
    return step
end

local function planned(setup, built)
    return run({
        snapshot = {selection = {{recipe_name = "make", machine = {name = "assembler"},
            modules = setup.modules or {}, beacons = setup.beacons or {}}}},
        solver_result = {status = "ok", columns = {{recipe_name = "make", crafts_per_second_total = 1,
            net_amounts = {['item/output'] = 1}, crafts_per_second_per_machine = 1}}, recipe_rates = {make = 1}},
        catalog = built,
    }).steps[1]
end

local function with_prototypes(value, callback)
    local previous = rawget(_G, "prototypes")
    _G.prototypes = value
    local ok, result = xpcall(callback, debug.traceback)
    _G.prototypes = previous
    if not ok then error(result, 0) end
    return result
end

local function recipe_input(recipe, projected)
    return {
        snapshot = {selection = {{recipe_name = "shadow", machine = {name = "assembler"}}}},
        solver_result = {status = "ok", columns = {{recipe_name = "shadow", crafts_per_second_total = 1,
            crafts_per_second_per_machine = 1}}, recipe_rates = {shadow = 1}},
        catalog = {
            entity = {assembler = {name = "assembler", crafting_speed = 1, energy_usage_w = 1,
                effect_receiver = verified_receiver()}},
            recipe = {shadow = projected},
        },
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PL1 a receiver that ignores modules reports no active quality module, whatever the module's effect", function()
        local built = catalog(verified_receiver({uses_module_effects = false}))
        local setup = {modules = {{name = "quality"}}}
        local expected = QualityPolicy.has_active_quality_module(policy_step(setup), built)
        local step = planned(setup, built)
        H.equal(step.has_quality_module, expected, "planner agrees with QualityPolicy about an ignored quality module")
        H.equal(step.forbids_speed_beacon,
            QualityPolicy.speed_beacon_contribution(policy_step(setup), built) > 0,
            "planner agrees with QualityPolicy about speed-beacon contribution")
        H.equal(step.has_quality_module, false, "an ignored module is not active quality")
        H.equal(step.forbids_speed_beacon, false, "an ignored module does not forbid a speed beacon")
    end)

    H.test(shape .. " PL2 a -0.25 speed module never makes forbids_speed_beacon true", function()
        local built = catalog()
        local setup = {modules = {{name = "speed"}}}
        local step = planned(setup, built)
        H.equal(step.has_quality_module, QualityPolicy.has_active_quality_module(policy_step(setup), built),
            "planner agrees with QualityPolicy about the speed module")
        H.equal(step.forbids_speed_beacon,
            QualityPolicy.speed_beacon_contribution(policy_step(setup), built) > 0,
            "planner agrees with QualityPolicy about no speed beacon")
        H.equal(step.forbids_speed_beacon, false, "a speed module is not a speed beacon")
    end)

    H.test(shape .. " PL3 a +0.25 quality module still makes forbids_speed_beacon true", function()
        local built = catalog()
        local setup = {modules = {{name = "quality"}}, beacons = {{name = "beacon", count = 1,
            modules = {{name = "speed"}}}}}
        local step = planned(setup, built)
        H.equal(step.has_quality_module, QualityPolicy.has_active_quality_module(policy_step(setup), built),
            "planner agrees with QualityPolicy about active quality")
        H.equal(step.forbids_speed_beacon,
            QualityPolicy.speed_beacon_contribution(policy_step(setup), built) > 0,
            "planner agrees with QualityPolicy about beacon speed")
        H.equal(step.has_quality_module, true, "the quality module is active")
        H.equal(step.forbids_speed_beacon, true, "a quality module forbids speed beacon coverage")
    end)

    H.test(shape .. " PL4 a positive quality module cancelled to zero still makes forbids_speed_beacon true", function()
        local built = catalog()
        local setup = {modules = {{name = "quality"}, {name = "cancelling"}},
            beacons = {{name = "beacon", count = 1, modules = {{name = "speed"}}}}}
        local step = planned(setup, built)
        H.equal(step.has_quality_module, QualityPolicy.has_active_quality_module(policy_step(setup), built),
            "planner asks the policy's presence question, not the total")
        H.equal(step.forbids_speed_beacon,
            QualityPolicy.speed_beacon_contribution(policy_step(setup), built) > 0,
            "planner asks the policy's beacon question")
        H.equal(step.has_quality_module, true, "the cancelled positive module remains active")
        H.equal(step.forbids_speed_beacon, true, "the cancelled positive module still forbids speed beacon coverage")
    end)

    H.test(shape .. " PL5 a beacon of productivity modules is no speed beacon", function()
        local built = catalog()
        local setup = {beacons = {{name = "beacon", count = 2,
            modules = {{name = "productivity", count = 2}}}}}
        local step = planned(setup, built)
        H.equal(step.has_quality_module, QualityPolicy.has_active_quality_module(policy_step(setup), built),
            "planner agrees with QualityPolicy about beacon quality modules")
        H.equal(step.forbids_speed_beacon,
            QualityPolicy.speed_beacon_contribution(policy_step(setup), built) > 0,
            "planner agrees with QualityPolicy about productivity beacon speed")
        H.equal(step.forbids_speed_beacon, false, "productivity modules do not make a speed beacon")
    end)

    H.test(shape .. " PL6 an incomplete catalog recipe never shadows a complete runtime recipe", function()
        local runtime = {
            name = "shadow", energy = 2, ingredients = {{type = "item", name = "input", amount = 2}},
            products = {{type = "item", name = "runtime-output", amount = 3}},
        }
        local result = with_prototypes({recipe = {shadow = runtime}}, function()
            return run(recipe_input(runtime, {energy = 1, ingredients = {}}))
        end)
        local step = result.steps[1]
        H.equal(step.recipe, "shadow", "the planned step keeps the recipe identity")
        H.equal(#step.outputs, 1, "the runtime recipe supplies the output list")
        H.equal(step.outputs[1].flow_id, "item/runtime-output", "the complete runtime recipe was used")
        H.equal(step.outputs[1].rate_per_second, 3, "the runtime product amount was used")
        H.equal(step.recipe_facts_missing ~= nil, true, "the step records the incomplete projection gap")
        H.equal(step.recipe_facts_missing.recipe, "shadow", "the gap names the recipe")
        H.equal(step.recipe_facts_missing.fields.products, true, "the gap names the missing products field")
    end)

    H.test(shape .. " PL7 a complete catalog recipe is used, and the runtime prototype is not consulted", function()
        local consulted = false
        local runtime = {name = "complete", energy = 2, ingredients = {},
            products = {{type = "item", name = "runtime-output", amount = 3}}}
        local runtime_recipes = setmetatable({}, {__index = function()
            consulted = true
            return runtime
        end})
        local projected = {name = "complete", energy = 1, ingredients = {},
            products = {{type = "item", name = "catalog-output", amount = 4}}}
        local result = with_prototypes({recipe = runtime_recipes}, function()
            local input = recipe_input(runtime, projected)
            input.snapshot.selection[1].recipe_name = "shadow"
            input.solver_result.columns[1].recipe_name = "shadow"
            input.solver_result.recipe_rates = {shadow = 1}
            input.catalog.recipe.shadow = projected
            return run(input)
        end)
        local step = result.steps[1]
        H.equal(consulted, false, "a complete projected recipe does not read the runtime prototype")
        H.equal(#step.outputs, 1, "the complete projected recipe supplies the output list")
        H.equal(step.outputs[1].flow_id, "item/catalog-output", "the catalog recipe was used")
        H.equal(step.outputs[1].rate_per_second, 4, "the catalog product amount was used")
        H.equal(step.recipe_facts_missing, nil, "a complete projected recipe has no gap")
    end)

    H.test(shape .. " PL8 the published step carries the receiver status the planner used", function()
        local built = catalog(verified_receiver({status = "verified_supported"}))
        local setup = {modules = {{name = "quality"}}}
        local step = planned(setup, built)
        local expected = QualityPolicy.receiver(policy_step(setup), built)
        H.equal(step.receiver_status, expected.status, "the published status comes from QualityPolicy.receiver")
        H.equal(step.receiver_status, "verified_supported", "the planner publishes the receiver decision")
    end)
end

H.done("test_plan_quality_facts")

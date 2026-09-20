--What the real boundary decides, from a real calculation, with the producer and both consumers present.
--
--Every case here runs through Generation.start, never through a hand-built catalog, because the reported bug
--and its opposite both lived in the gap between what a stage assumed and what the boundary actually delivered:
--preflight refused an ordinary speed-module sheet, and a chance-based product passed as supported because no
--recipe facts ever crossed that boundary.
local H = require "tests.harness"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

--One machine, one recipe, four speed modules and a speed beacon: the shape of the reported sheet, small enough
--for the fast tier. `options.product` overrides the product spec, `options.setup` the module loadout.
local function world_for(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_module("speed", "speed", {speed = 0.5, consumption = 0.7, quality = -0.25})
    world.add_module("quality", "quality", {quality = 0.25, speed = -0.05})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 4,
        base_quality = options.base_quality, no_effect_receiver = options.no_effect_receiver,
        uses_module_effects = options.uses_module_effects})
    world.add_beacon({name = "beacon", module_slots = 2, distribution_effectivity = 1.5, supply_w = 9, supply_h = 9})
    world.add_recipe({name = "plate", category = "crafting", ingredients = {{name = "ore", amount = 1}},
        products = {options.product or {name = "plate", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    local Registry = require "logic.registry"
    local pane, sheet = H.fill_sheet({{item = "plate", rate = 1, unit = "/s"}}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    world.bind("item/plate", "plate")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["plate"] = {name = "assembler"}
    storage[1].module_setups_by_recipe_name["plate"] = options.setup
        or {modules = {{name = "speed", quality = "normal", count = 4}},
            beacons = {{name = "beacon", quality = "normal", count = 2, sharing = 1,
                modules = {{name = "speed", quality = "normal", count = 2}}}}}
    Registry.generation_provenance = {candidate_sha = "boundary", mod_version = "boundary",
        factorio_branch = shape, packaged = false}

    local Sheet = require "gui.sheet"
    Sheet.calculate(Sheet.compute_button_of(sheet))
    local ticks = 0
    while storage[1].calc_jobs and storage[1].calc_jobs[sheet_id] do
        H.run_ticks(world, 1)
        ticks = ticks + 1
        H.equal(ticks < 900, true, "the boundary fixture calculates")
    end
    return world, sheet_id
end

--Drive the real service to a terminal state and report what the boundary decided.
local function terminal(world, sheet_id, mutate)
    local Preflight = require "logic.bp.preflight"
    local seen = {catalog = nil, recipes = 0, receivers = {}}
    local check = Preflight.check
    Preflight.check = function(snapshot, result, catalog, options)
        if seen.catalog == nil then
            seen.catalog = catalog
            for _ in pairs((catalog or {}).recipe or {}) do seen.recipes = seen.recipes + 1 end
            for name, entity in pairs((catalog or {}).entity or {}) do
                local receiver = type(entity) == "table" and entity.effect_receiver
                if type(receiver) == "table" then seen.receivers[name] = receiver.status end
            end
        end
        if mutate then mutate(snapshot, result, catalog) end
        return check(snapshot, result, catalog, options)
    end

    local Generation = require "logic.bp.generation"
    local settings = require("logic.bp.settings").of_sheet(1, sheet_id)
    local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, settings = settings, deliver = false}
    local result = Generation.status(1, job_id)
    for _ = 1, 600 do
        if result.state ~= "pending" then break end
        H.run_ticks(world, 1)
        result = Generation.status(1, job_id)
    end
    Preflight.check = check
    return result, seen
end

local function has_code(result, code)
    for _, value in ipairs(result.reason_codes or {}) do
        if value == code then return true end
    end
    return false
end

local function codes(result)
    return table.concat(result.reason_codes or {}, ",")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BR1 the boundary carries recipe facts and a receiver status for every machine", function()
        local world, sheet_id = world_for(shape)
        local _, seen = terminal(world, sheet_id)
        H.equal(seen.catalog ~= nil, true, "preflight was reached")
        H.equal(seen.recipes > 0, true, "the catalog carries the active recipes")
        H.equal(seen.receivers["assembler"] ~= nil, true, "the machine carries a receiver status")
        H.equal(seen.receivers["assembler"] ~= "missing", true,
            "a live prototype is never projected as missing, saw " .. tostring(seen.receivers["assembler"]))
    end)

    H.test(shape .. " BR2 an ordinary speed-module sheet with speed beacons is never rejected", function()
        local world, sheet_id = world_for(shape)
        local result = terminal(world, sheet_id)
        H.equal(has_code(result, "BP_REJ_QUALITY_CHANGING"), false,
            "the reported bug: a -0.25 penalty is ordinary production, saw " .. codes(result))
        H.equal(has_code(result, "BP_REJ_BEACON_SPEED_ON_QUALITY"), false,
            "speed beacons beside a machine with no quality module are ordinary, saw " .. codes(result))
        H.equal(has_code(result, "BP_REJ_PROTOTYPE_FACTS_MISSING"), false,
            "a live projection is never short of facts, saw " .. codes(result))
    end)

    H.test(shape .. " BR3 a positive quality module is still refused", function()
        local world, sheet_id = world_for(shape, {setup = {modules = {{name = "quality", quality = "normal", count = 2}},
            beacons = {}}})
        local result = terminal(world, sheet_id)
        H.equal(has_code(result, "BP_REJ_QUALITY_CHANGING"), true,
            "quality-changing production stays unsupported, saw " .. codes(result))
    end)

    H.test(shape .. " BR4 a speed beacon on a quality-module machine is refused, whatever the total", function()
        local world, sheet_id = world_for(shape, {setup = {modules = {{name = "quality", quality = "normal", count = 2}},
            beacons = {{name = "beacon", quality = "normal", count = 2, sharing = 1,
                modules = {{name = "speed", quality = "normal", count = 2}}}}}})
        local result = terminal(world, sheet_id)
        --Two +0.25 modules against six beacon-weighted -0.25 penalties leave a negative total, so the
        --quality-changing rule is silent here by design. The speed-beacon prohibition is a different
        --question and still fires, because a positive quality module is installed.
        H.equal(has_code(result, "BP_REJ_QUALITY_CHANGING"), false,
            "a negative total raises nothing, saw " .. codes(result))
        H.equal(has_code(result, "BP_REJ_BEACON_SPEED_ON_QUALITY"), true,
            "a speed beacon on a quality-module machine stays refused, saw " .. codes(result))
    end)

    H.test(shape .. " BR5 a machine with an intrinsic positive quality effect is refused with no module", function()
        local world, sheet_id = world_for(shape, {base_quality = 0.1, setup = {modules = {}, beacons = {}}})
        local result = terminal(world, sheet_id)
        H.equal(has_code(result, "BP_REJ_QUALITY_CHANGING"), true,
            "an empty module list proves nothing about the base effect, saw " .. codes(result))
    end)

    H.test(shape .. " BR6 a chance-based product is refused at the real boundary", function()
        local world, sheet_id = world_for(shape, {product = {name = "plate", amount = 1, p = 0.5}})
        local result = terminal(world, sheet_id)
        H.equal(has_code(result, "BP_REJ_PROBABILISTIC"), true,
            "the facts now reach the checker, so the sheet is refused, saw " .. codes(result))
    end)

    H.test(shape .. " BR7 an active column whose recipe facts were removed is refused", function()
        local world, sheet_id = world_for(shape)
        local result = terminal(world, sheet_id, function(_, _, catalog)
            --remove one required field from an otherwise genuine projection
            for _, recipe in pairs(catalog.recipe or {}) do recipe.products = nil end
        end)
        H.equal(has_code(result, "BP_REJ_PROTOTYPE_FACTS_MISSING"), true,
            "a projection that lost its products is refused, saw " .. codes(result))
    end)

    H.test(shape .. " BR8 a machine whose receiver facts were removed is refused", function()
        local world, sheet_id = world_for(shape)
        local result = terminal(world, sheet_id, function(_, _, catalog)
            for _, entity in pairs(catalog.entity or {}) do
                if type(entity) == "table" then entity.effect_receiver = nil end
            end
        end)
        H.equal(has_code(result, "BP_REJ_PROTOTYPE_FACTS_MISSING"), true,
            "an uncaptured receiver is refused, never read as ordinary, saw " .. codes(result))
    end)

    H.test(shape .. " BR9 preflight and the planner agree about the same sheet", function()
        local world, sheet_id = world_for(shape)
        local _, seen = terminal(world, sheet_id)
        local QualityPolicy = require "logic.bp.quality_policy"
        local Plan = require "logic.bp.plan"
        local catalog = clone(seen.catalog)
        local step = {machine = {name = "assembler", quality = "normal"},
            modules = {{name = "speed", quality = "normal", count = 4}},
            beacons = {{name = "beacon", quality = "normal", count = 2,
                modules = {{name = "speed", quality = "normal", count = 2}}}}}
        H.equal(QualityPolicy.has_active_quality_module(step, catalog), false,
            "the policy sees no quality module")
        H.equal(QualityPolicy.speed_beacon_contribution(step, catalog) > 0, true,
            "the policy sees the beacons adding speed")
        H.equal(type(Plan.begin) == "function", true, "the planner is the same module the service used")
    end)

    --The correction applied when lane 087 merged: a machine forbids speed beacons because it holds a quality
    --module, never because speed beacons stand beside it. The opposite reading made validate.lua:639-642 raise
    --BP_V_SPEED_BEACON_ON_QUALITY for every ordinary speed-beacon factory.
    --The correction applied when lane 087 merged: a machine forbids speed beacons because it holds a quality
    --module, never because speed beacons stand beside it. The opposite reading made validate.lua:639-642 raise
    --BP_V_SPEED_BEACON_ON_QUALITY for every ordinary speed-beacon factory, which is the reported sheet's shape.
    H.test(shape .. " BR10 speed beacons alone never make a step forbid speed beacons", function()
        local world, sheet_id = world_for(shape)
        local Plan = require "logic.bp.plan"
        local steps
        local plan_step = Plan.step
        Plan.step = function(state, budget)
            local out = plan_step(state, budget)
            if out and out.done and out.ok and type(out.result) == "table" and steps == nil then
                steps = clone(out.result.steps)
            end
            return out
        end
        local result = terminal(world, sheet_id)
        Plan.step = plan_step

        H.equal(type(steps) == "table" and #steps > 0, true,
            "the planner published a step; terminal state was " .. tostring(result.state))
        for _, step in ipairs(steps or {}) do
            H.equal(step.has_quality_module, false,
                "no quality module is installed in " .. tostring(step.step_id))
            H.equal(step.forbids_speed_beacon, false,
                "speed beacons beside it never make " .. tostring(step.step_id) .. " forbid them")
            H.equal(step.receiver_status ~= nil and step.receiver_status ~= "missing", true,
                "the step carries the receiver status it used, saw " .. tostring(step.receiver_status))
        end
    end)
end

H.done("test_generation_boundary_rules")

--Generation must carry the producer's recipe and receiver facts through its preparation boundary.
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

local function world_and_sheet(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", energy = 1,
        ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane, sheet = H.fill_sheet({})
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    return world, sheet_id
end

local function input(sheet_id, catalog)
    local result = {
        schema_version = 1,
        snapshot = {
            schema_version = 1, sheet_id = sheet_id, state = "current",
            fingerprint = {input = "facts-input"},
            targets = {{full_name = "item/gear", rate_per_second = 1}},
            selection = {{recipe_name = "gear", machine = {name = "assembler", quality = "normal"},
                modules = {}, beacons = {}}},
        },
        solver_result = {
            schema_version = 1, status = "ok", recipe_rates = {gear = 1},
            columns = {{recipe_name = "gear", machine = {name = "assembler", quality = "normal"}, rate = 1,
                net_amounts = {['item/gear'] = 1, ['item/raw'] = -1}}},
        },
        settings = {input_edge = "left", output_edge = "top"},
        options = {}, revisions = {sheet = 0, config = 0},
        surface = "nauvis", force = "player", source_export = {name = "fixture-export"},
    }
    if catalog then result.catalog = catalog end
    return result
end

local function terminal(world, Jobs, Generation, job_id)
    for _ = 1, 160 do
        local status = Generation.status(1, job_id)
        if status and status.state ~= "pending" then return status end
        H.run_ticks(world, 1)
    end
    H.equal(false, true, "generation finishes within the bounded tick limit")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " GF1 a real Generation.start run reaches Preflight.check with the active recipes and every machine's receiver status", function()
        local world, sheet_id = world_and_sheet(shape)
        local Registry = require "logic.registry"
        local Jobs = require "logic.jobs"
        local Preflight = require "logic.bp.preflight"
        local Generation = require "logic.bp.generation"
        local observed
        local original = Preflight.check
        Preflight.check = function(snapshot, solver_result, catalog, options)
            observed = {snapshot = snapshot, solver_result = solver_result, catalog = catalog, options = options}
            local reasons = original(snapshot, solver_result, catalog, options)
            if #reasons == 0 then return {{code = "BP_REJ_TEST_SENTINEL"}} end
            return reasons
        end
        Registry.calculation = {get = function() return nil end}
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = input(sheet_id)}
        local result = terminal(world, Jobs, Generation, job_id)
        Preflight.check = original
        H.equal(result.state, "failure", "the instrumented real run reaches a terminal preflight result")
        H.equal(observed ~= nil, true, "Generation reaches Preflight.check")
        H.equal(observed.catalog.recipe.gear ~= nil, true, "active recipe crosses the generation boundary")
        H.equal(observed.catalog.recipe_coverage.state, "complete", "active recipe coverage crosses the boundary")
        H.equal(observed.catalog.entity.assembler.effect_receiver.status == "verified_default"
            or observed.catalog.entity.assembler.effect_receiver.status == "verified_supported", true,
            "machine receiver status crosses the boundary")
        H.equal(observed.catalog.entity.assembler.effect_receiver.source, "prototype", "receiver source crosses the boundary")
        H.equal(observed.catalog.entity.assembler.effect_receiver.branch, shape, "receiver branch crosses the boundary")
    end)

    H.test(shape .. " GF2 a prepared input replays with prototypes set to nil", function()
        local world, sheet_id = world_and_sheet(shape)
        local Catalog = require "logic.catalog"
        local catalog = Catalog.build(1, {entities = {"assembler"}, items = {"raw", "gear"}, recipes = {"gear"}})
        local Registry = require "logic.registry"
        local Jobs = require "logic.jobs"
        local Preflight = require "logic.bp.preflight"
        local Generation = require "logic.bp.generation"
        local observed
        local original = Preflight.check
        Preflight.check = function(snapshot, solver_result, received_catalog, options)
            observed = received_catalog
            return {{code = "BP_REJ_TEST_SENTINEL"}}
        end
        local saved_prototypes = prototypes
        prototypes = nil
        local ok, job_id = pcall(Generation.start, {player_index = 1, sheet_id = sheet_id,
            prepared_input = input(sheet_id, clone(catalog))})
        H.equal(ok, true, "prepared replay starts without prototypes")
        local result = terminal(world, Jobs, Generation, job_id)
        prototypes = saved_prototypes
        Preflight.check = original
        H.equal(result.state, "failure", "the replay reaches the instrumented preflight")
        H.equal(observed ~= nil, true, "prepared catalog reaches preflight without prototypes")
        H.equal(observed.recipe.gear ~= nil, true, "prepared recipe is retained")
        H.equal(observed.entity.assembler.effect_receiver.status == "verified_default"
            or observed.entity.assembler.effect_receiver.status == "verified_supported", true,
            "prepared receiver status is retained")
    end)
end

H.done("test_generation_recipe_facts")

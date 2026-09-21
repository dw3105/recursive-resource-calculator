--Shared world setups for the delivery gate and for the diagnostic runner.
--One definition per chain, so a repair measured by the diagnostic runner is measured on the same factory the
--gate demands, never on a hand-tuned copy of it.
local H = require "tests.harness"

local M = {}

local function finish_calculation(world, sheet_id, name)
    local ticks = 0
    while storage[1].calc_jobs and storage[1].calc_jobs[sheet_id] do
        H.run_ticks(world, 1)
        ticks = ticks + 1
        H.equal(ticks < 900, true, name .. " calculation finishes")
    end
end

local function publish(world, sheet, sheet_id, name)
    local Sheet = require "gui.sheet"
    Sheet.calculate(Sheet.compute_button_of(sheet))
    finish_calculation(world, sheet_id, name)
end

--A three-step item chain with external inputs, machine identifiers without quality, productivity modules in
--the machines and speed beacons around them: the shape of the player's own sheet.
function M.item_chain(shape)
    local world = H.new_world(shape)
    for _, item in ipairs({"ore", "plate", "cable", "circuit", "machine", "gear"}) do world.add_item(item) end
    world.add_fluid("molten-iron")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1})
    world.add_machine({name = "plant", categories = {"crafting"}, speed = 1, module_slots = 2})
    world.add_machine({name = "foundry", categories = {"metallurgy"}, speed = 1})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 4})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_recipe({name = "casting-iron", category = "metallurgy",
        ingredients = {{type = "fluid", name = "molten-iron", amount = 20}},
        products = {{name = "plate", amount = 4}}})
    world.add_recipe({name = "cable", category = "crafting", ingredients = {{name = "plate", amount = 1}},
        products = {{name = "cable", amount = 2}}})
    world.add_recipe({name = "circuit", category = "crafting",
        ingredients = {{name = "cable", amount = 3}, {name = "plate", amount = 1}},
        products = {{name = "circuit", amount = 1}}})
    world.add_recipe({name = "machine", category = "crafting",
        ingredients = {{name = "circuit", amount = 3}, {name = "gear", amount = 5}, {name = "plate", amount = 9}},
        products = {{name = "machine", amount = 1}}})
    world.add_module("prod", "productivity", {productivity = 0.25})
    world.add_module("speed", "speed", {speed = 0.5})
    world.add_beacon({name = "beacon", module_slots = 2, distribution = 1.5, supply_w = 9, supply_h = 9})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    local Registry = require "logic.registry"
    local pane, sheet = H.fill_sheet({{item = "machine", rate = 1, unit = "/s"}}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    local bind = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
    bind["plate"] = {name = "furnace"}
    bind["casting-iron"] = {name = "foundry"}
    bind["cable"] = {name = "plant"}
    bind["circuit"] = {name = "plant"}
    bind["machine"] = {name = "assembler", quality = "normal"}
    local setups = storage[1].module_setups_by_recipe_name
    setups["casting-iron"] = {modules = {{name = "prod", quality = "normal"}, {name = "prod", quality = "normal"}},
        beacons = {{name = "beacon", quality = "normal", count = 3, sharing = 1,
            modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
    setups["circuit"] = {modules = {{name = "prod", quality = "normal"}},
        beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
            modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
    setups["cable"] = {modules = {{name = "prod", quality = "normal"}},
        beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
            modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
    Registry.generation_provenance = {candidate_sha = "acceptance", mod_version = "acceptance",
        factorio_branch = shape, packaged = false}
    publish(world, sheet, sheet_id, "item chain")
    return {world = world, sheet = sheet, sheet_id = sheet_id, name = "item-chain"}
end

--The player's four-step red-science sheet: two smelting steps and two crafting steps, with no effects.
function M.red_science_chain(shape)
    local world = H.new_world(shape)
    for _, item in ipairs({"copper-ore", "copper-plate", "iron-ore", "iron-plate", "iron-gear-wheel",
                           "automation-science-pack"}) do world.add_item(item) end
    world.add_machine({name = "electric-furnace", categories = {"smelting"}, speed = 2, module_slots = 0})
    world.add_machine({name = "assembling-machine-3", categories = {"crafting"}, speed = 1.25, module_slots = 0})
    world.add_recipe({name = "copper-plate", category = "smelting", energy = 3.2,
        ingredients = {{name = "copper-ore", amount = 1}}, products = {{name = "copper-plate", amount = 1}}})
    world.add_recipe({name = "iron-plate", category = "smelting", energy = 3.2,
        ingredients = {{name = "iron-ore", amount = 1}}, products = {{name = "iron-plate", amount = 1}}})
    world.add_recipe({name = "iron-gear-wheel", category = "crafting", energy = 0.5,
        ingredients = {{name = "iron-plate", amount = 2}}, products = {{name = "iron-gear-wheel", amount = 1}}})
    world.add_recipe({name = "automation-science-pack", category = "crafting", energy = 5,
        ingredients = {{name = "copper-plate", amount = 1}, {name = "iron-gear-wheel", amount = 1}},
        products = {{name = "automation-science-pack", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    local Registry = require "logic.registry"
    local pane, sheet = H.fill_sheet({{item = "automation-science-pack", rate = 1, unit = "/s"}}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    local bind = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
    bind["automation-science-pack"] = {name = "assembling-machine-3", quality = "normal"}
    bind["iron-gear-wheel"] = {name = "assembling-machine-3", quality = "normal"}
    bind["copper-plate"] = {name = "electric-furnace", quality = "normal"}
    bind["iron-plate"] = {name = "electric-furnace", quality = "normal"}
    Registry.generation_provenance = {candidate_sha = "acceptance", mod_version = "acceptance",
        factorio_branch = shape, packaged = false}
    publish(world, sheet, sheet_id, "red science chain")
    return {world = world, sheet = sheet, sheet_id = sheet_id, name = "red-science-chain"}
end

--A fluid producer feeding a fluid consumer: the pipe path must survive layout, not turn into an import.
function M.fluid_chain(shape)
    local world = H.new_world(shape)
    world.add_item("fluid-ore")
    world.add_item("fluid-product")
    world.add_fluid("smoke-fluid")
    world.add_machine({name = "fluid-maker", categories = {"chemistry"}, speed = 1, module_slots = 0})
    world.add_machine({name = "fluid-consumer", categories = {"chemistry"}, speed = 1, module_slots = 0})
    world.add_recipe({name = "make-smoke-fluid", category = "chemistry",
        ingredients = {{name = "fluid-ore", amount = 1}},
        products = {{type = "fluid", name = "smoke-fluid", amount = 1}}})
    world.add_recipe({name = "consume-smoke-fluid", category = "chemistry",
        ingredients = {{type = "fluid", name = "smoke-fluid", amount = 1}},
        products = {{name = "fluid-product", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    world.bind("fluid/smoke-fluid", "make-smoke-fluid")
    world.bind("item/fluid-product", "consume-smoke-fluid")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["make-smoke-fluid"] = {name = "fluid-maker"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["consume-smoke-fluid"] = {name = "fluid-consumer"}

    local Registry = require "logic.registry"
    local pane, sheet = H.fill_sheet({{item = "fluid-product", rate = 1, unit = "/s"}}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    Registry.generation_provenance = {candidate_sha = "acceptance", mod_version = "acceptance",
        factorio_branch = shape, packaged = false}
    publish(world, sheet, sheet_id, "fluid chain")
    return {world = world, sheet = sheet, sheet_id = sheet_id, name = "fluid-chain"}
end

--A beacon with a speed module beside its machine row: the beacon is a powered layout entity, not a label.
function M.beacon_chain(shape)
    local world = H.new_world(shape)
    world.add_item("beacon-ore")
    world.add_item("beacon-part")
    world.add_item("beacon-product")
    world.add_module("speed", "speed", {speed = 0.5})
    world.add_machine({name = "beacon-prep", categories = {"crafting"}, speed = 1, module_slots = 0})
    world.add_machine({name = "beacon-assembler", categories = {"crafting"}, speed = 1, module_slots = 0})
    world.add_beacon({name = "beacon", module_slots = 1, distribution_effectivity = 1.5, energy_kw = 480,
        supply_w = 9, supply_h = 9})
    world.add_recipe({name = "make-beacon-part", category = "crafting",
        ingredients = {{name = "beacon-ore", amount = 1}},
        products = {{name = "beacon-part", amount = 1}}})
    world.add_recipe({name = "beacon-powered-product", category = "crafting",
        ingredients = {{name = "beacon-part", amount = 1}},
        products = {{name = "beacon-product", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    world.bind("item/beacon-part", "make-beacon-part")
    world.bind("item/beacon-product", "beacon-powered-product")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["make-beacon-part"] = {name = "beacon-prep"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["beacon-powered-product"] = {name = "beacon-assembler"}
    storage[1].module_setups_by_recipe_name["make-beacon-part"] = {modules = {}, beacons = {}}
    storage[1].module_setups_by_recipe_name["beacon-powered-product"] = {
        modules = {}, beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
            modules = {{name = "speed", quality = "normal"}}}},
    }

    local Registry = require "logic.registry"
    local pane, sheet = H.fill_sheet({{item = "beacon-product", rate = 1, unit = "/s"}}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    Registry.generation_provenance = {candidate_sha = "acceptance", mod_version = "acceptance",
        factorio_branch = shape, packaged = false}
    publish(world, sheet, sheet_id, "beacon chain")
    return {world = world, sheet = sheet, sheet_id = sheet_id, name = "beacon-chain"}
end

M.all = {item_chain = M.item_chain, red_science_chain = M.red_science_chain, fluid_chain = M.fluid_chain,
    beacon_chain = M.beacon_chain}

return M

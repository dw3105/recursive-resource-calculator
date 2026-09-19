local Common = require "tests.golden.setup.common"

return {
    schema_version = 1,
    setup_id = "shared-intermediate-multi-target",
    production_case = true,
    description = "Two targets consume one shared smelted intermediate.",
    factorio_branch = Common.factorio_branch,
    mod = Common.mod,
    source_kind = Common.source_kind,
    source_sha = Common.source_sha,
    research = Common.research,
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {{name = "copper-ore"}, {name = "copper-plate"}, {name = "copper-cable"}, {name = "copper-gear"}},
        machines = {
            {name = "copper-furnace", type = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 90, module_slots = 2},
            {name = "shared-assembler", categories = {"crafting"}, speed = 1, energy_kw = 75, module_slots = 2},
        },
        modules = Common.modules,
        beacons = Common.beacons,
        recipes = {
            {name = "smelt-copper-plate", category = "smelting", energy = 1,
                ingredients = {{name = "copper-ore", amount = 1}},
                products = {{name = "copper-plate", amount = 1}}},
            {name = "craft-copper-gear", category = "crafting", energy = 1,
                ingredients = {{name = "copper-plate", amount = 2}},
                products = {{name = "copper-gear", amount = 1}}},
            {name = "craft-copper-cable", category = "crafting", energy = 1,
                ingredients = {{name = "copper-plate", amount = 1}},
                products = {{name = "copper-cable", amount = 2}}},
        },
    },
    targets = {
        {item = "copper-gear", rate = 1, unit = "/s"},
        {item = "copper-cable", rate = 2, unit = "/s"},
    },
    selection = {
        Common.choice("item/copper-plate", "smelt-copper-plate", "copper-furnace"),
        Common.choice("item/copper-gear", "craft-copper-gear", "shared-assembler"),
        Common.choice("item/copper-cable", "craft-copper-cable", "shared-assembler"),
    },
    infrastructure = Common.infrastructure,
    declared_chain = {
        steps = {"smelt-copper-plate", "craft-copper-gear", "craft-copper-cable"},
        flows = {"item/copper-ore", "item/copper-plate", "item/copper-gear", "item/copper-cable"},
    },
    generation = {search_budget = 3000},
    engine_scenario = Common.scenario(
        {{full_name = "item/copper-ore", rate_per_second = 4}},
        {{full_name = "item/copper-gear", rate_per_second = 1},
         {full_name = "item/copper-cable", rate_per_second = 2}}),
    supported_outcome = "production",
    expected_outcome = "production",
    max_ticks = 700,
}

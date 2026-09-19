local Common = require "tests.golden.setup.common"

return {
    schema_version = 1,
    setup_id = "base-only-crafting-smelting",
    production_case = true,
    description = "Base-only smelting feeds a base-only assembler recipe.",
    factorio_branch = Common.factorio_branch,
    mod = Common.mod,
    source_kind = Common.source_kind,
    source_sha = Common.source_sha,
    research = Common.research,
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {{name = "iron-ore"}, {name = "iron-plate"}, {name = "iron-gear"}},
        machines = {
            {name = "stone-furnace", type = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 90, module_slots = 2},
            {name = "assembling-machine-1", categories = {"crafting"}, speed = 1, energy_kw = 75, module_slots = 2},
        },
        modules = Common.modules,
        beacons = Common.beacons,
        recipes = {
            {name = "smelt-iron-plate", category = "smelting", energy = 1,
                ingredients = {{name = "iron-ore", amount = 1}},
                products = {{name = "iron-plate", amount = 1}}},
            {name = "craft-iron-gear", category = "crafting", energy = 1,
                ingredients = {{name = "iron-plate", amount = 2}},
                products = {{name = "iron-gear", amount = 1}}},
        },
    },
    targets = {{item = "iron-gear", rate = 1, unit = "/s"}},
    selection = {
        Common.choice("item/iron-plate", "smelt-iron-plate", "stone-furnace"),
        Common.choice("item/iron-gear", "craft-iron-gear", "assembling-machine-1"),
    },
    infrastructure = Common.infrastructure,
    declared_chain = {
        steps = {"smelt-iron-plate", "craft-iron-gear"},
        flows = {"item/iron-ore", "item/iron-plate", "item/iron-gear"},
    },
    generation = {search_budget = 2500},
    engine_scenario = Common.scenario(
        {{full_name = "item/iron-ore", rate_per_second = 2}},
        {{full_name = "item/iron-gear", rate_per_second = 1}}),
    supported_outcome = "production",
    expected_outcome = "production",
    max_ticks = 600,
}

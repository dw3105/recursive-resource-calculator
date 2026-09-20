local Common = require "tests.golden.setup.common"

return {
    schema_version = 1,
    setup_id = "repeatability",
    production_case = true,
    description = "The same two-step production graph is captured twice for stable replay input.",
    factorio_branch = Common.factorio_branch,
    mod = Common.mod,
    source_kind = Common.source_kind,
    source_sha = Common.source_sha,
    research = Common.research,
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {{name = "repeatable-ore"}, {name = "repeatable-part"}, {name = "repeatable-product"}},
        machines = {
            {name = "repeatable-assembler", categories = {"crafting"}, speed = 1, energy_kw = 75, module_slots = 2},
        },
        modules = Common.modules,
        beacons = Common.beacons,
        recipes = {
            {name = "make-repeatable-part", category = "crafting", energy = 1,
                ingredients = {{name = "repeatable-ore", amount = 2}},
                products = {{name = "repeatable-part", amount = 1}}},
            {name = "make-repeatable-product", category = "crafting", energy = 1,
                ingredients = {{name = "repeatable-part", amount = 1}, {name = "repeatable-ore", amount = 1}},
                products = {{name = "repeatable-product", amount = 1}}},
        },
    },
    targets = {{item = "repeatable-product", rate = 1, unit = "/s"}},
    selection = {
        Common.choice("item/repeatable-part", "make-repeatable-part", "repeatable-assembler"),
        Common.choice("item/repeatable-product", "make-repeatable-product", "repeatable-assembler"),
    },
    infrastructure = Common.infrastructure,
    declared_chain = {
        steps = {"make-repeatable-part", "make-repeatable-product"},
        flows = {"item/repeatable-ore", "item/repeatable-part", "item/repeatable-product"},
    },
    engine_scenario = Common.scenario(
        {{full_name = "item/repeatable-ore", rate_per_second = 3}},
        {{full_name = "item/repeatable-product", rate_per_second = 1}}),
    supported_outcome = "production",
    expected_outcome = "production",
    max_ticks = 600,
}

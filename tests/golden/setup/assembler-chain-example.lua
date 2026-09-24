local Common = require "tests.golden.setup.common"

return {
    schema_version = 1,
    setup_id = "assembler-chain-example",
    production_case = true,
    description = "A compact all-assembler chain turns imported parts into a machine.",
    factorio_branch = Common.factorio_branch,
    mod = Common.mod,
    source_kind = Common.source_kind,
    source_sha = Common.source_sha,
    research = Common.research,
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {{name = "steel-plate"}, {name = "electronic-circuit"}, {name = "machine-gear"}, {name = "example-machine"}},
        machines = {
            {name = "example-assembler", categories = {"crafting"}, speed = 1, energy_kw = 75, module_slots = 2},
        },
        modules = Common.modules,
        beacons = Common.beacons,
        recipes = {
            {name = "assemble-machine-gear", category = "crafting", energy = 1,
                ingredients = {{name = "steel-plate", amount = 2}},
                products = {{name = "machine-gear", amount = 1}}},
            {name = "assemble-example-machine", category = "crafting", energy = 1,
                ingredients = {{name = "machine-gear", amount = 2}, {name = "electronic-circuit", amount = 3}},
                products = {{name = "example-machine", amount = 1}}},
        },
    },
    targets = {{item = "example-machine", rate = 1, unit = "/s"}},
    selection = {
        Common.choice("item/machine-gear", "assemble-machine-gear", "example-assembler"),
        Common.choice("item/example-machine", "assemble-example-machine", "example-assembler"),
    },
    infrastructure = Common.infrastructure,
    declared_chain = {
        steps = {"assemble-machine-gear", "assemble-example-machine"},
        flows = {"item/steel-plate", "item/electronic-circuit", "item/machine-gear", "item/example-machine"},
    },
    engine_scenario = Common.scenario(
        {{full_name = "item/steel-plate", rate_per_second = 4},
         {full_name = "item/electronic-circuit", rate_per_second = 3}},
        {{full_name = "item/example-machine", rate_per_second = 1}}),
    supported_outcome = "production",
    expected_outcome = "production",
    --Round 30: stages charge honest ~8 us ops, so one generation spans more, shorter ticks.
    max_ticks = 3000,
}

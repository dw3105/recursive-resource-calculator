local Common = require "tests.golden.setup.common"

return {
    schema_version = 1,
    setup_id = "fluid-byproduct-chain",
    production_case = true,
    description = "A chemistry wash consumes water and returns a fluid byproduct before smelting.",
    factorio_branch = Common.factorio_branch,
    mod = Common.mod,
    source_kind = Common.source_kind,
    source_sha = Common.source_sha,
    research = Common.research,
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {{name = "sulfuric-ore"}, {name = "washed-ore"}, {name = "refined-plate"}},
        fluids = {{name = "water"}, {name = "dirty-water"}},
        machines = {
            {
                name = "ore-washer",
                categories = {"chemistry"}, speed = 1, energy_kw = 120, module_slots = 2,
                fluid_boxes = {
                    {index = 1, production_type = "input", filter = "water", connections = {
                        {offset = {x = 0, y = -1}, direction = 0, flow_direction = "input"},
                    }},
                    {index = 2, production_type = "output", connections = {
                        {offset = {x = 0, y = 1}, direction = 8, flow_direction = "output"},
                    }},
                },
            },
            {name = "plate-furnace", type = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 90, module_slots = 2},
        },
        modules = Common.modules,
        beacons = Common.beacons,
        recipes = {
            {name = "wash-sulfuric-ore", category = "chemistry", energy = 1,
                ingredients = {{type = "item", name = "sulfuric-ore", amount = 1},
                    {type = "fluid", name = "water", amount = 10}},
                products = {{type = "item", name = "washed-ore", amount = 1},
                    {type = "fluid", name = "dirty-water", amount = 10}}},
            {name = "smelt-refined-plate", category = "smelting", energy = 1,
                ingredients = {{name = "washed-ore", amount = 1}},
                products = {{name = "refined-plate", amount = 1}}},
        },
    },
    targets = {{item = "refined-plate", rate = 1, unit = "/s"}},
    selection = {
        Common.choice("item/washed-ore", "wash-sulfuric-ore", "ore-washer"),
        Common.choice("item/refined-plate", "smelt-refined-plate", "plate-furnace"),
    },
    infrastructure = Common.infrastructure,
    declared_chain = {
        steps = {"wash-sulfuric-ore", "smelt-refined-plate"},
        flows = {"item/sulfuric-ore", "item/washed-ore", "item/refined-plate",
            "fluid/water", "fluid/dirty-water"},
    },
    engine_scenario = Common.scenario(
        {{full_name = "item/sulfuric-ore", rate_per_second = 1},
         {full_name = "fluid/water", rate_per_second = 10}},
        {{full_name = "item/refined-plate", rate_per_second = 1},
         {full_name = "fluid/dirty-water", rate_per_second = 10}}),
    supported_outcome = "production",
    expected_outcome = "production",
    max_ticks = 700,
}

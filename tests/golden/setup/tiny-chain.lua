--A deliberately small, fully described harness setup.
--The generation search budget is zero on purpose: preparation is real and
--complete, then the real search stops in its bounded search phase before a
--layout can appear.  The supported outcome remains production until review.
return {
    schema_version = 1,
    setup_id = "tiny-chain",
    description = "One raw item feeds one assembled item with a selected machine setup.",
    factorio_branch = "2.0",
    prototype_facts = {
        source = "tests.harness",
        mocked = true,
        items = {
            {name = "raw"},
            {name = "gear"},
        },
        machines = {
            {name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4},
        },
        modules = {
            {name = "speed-module", category = "speed", effects = {speed = 0.2}},
        },
        beacons = {
            {name = "beacon", module_slots = 2, distribution_effectivity = 1.5},
        },
        recipes = {
            {name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}},
                products = {{name = "gear", amount = 1}}},
        },
    },
    targets = {
        {item = "gear", rate = 1, unit = "/s"},
    },
    selection = {
        {
            product_full_name = "item/gear",
            recipe_name = "gear",
            machine = {name = "assembler", quality = "normal"},
            setup = {
                modules = {{name = "speed-module", quality = "normal"}},
                beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
                    modules = {{name = "speed-module", quality = "normal"}}}},
            },
        },
    },
    infrastructure = {
        default_infrastructure = true,
        roboport = {name = "roboport", quality = "normal"},
        pole = {name = "medium-electric-pole", quality = "normal"},
        belt = {name = "transport-belt", quality = "normal"},
        inserter = {name = "inserter", quality = "normal"},
        pipe = {name = "pipe", quality = "normal"},
        underground_pipe = {name = "pipe-to-ground", quality = "normal"},
        input_edge = "left",
        output_edge = "top",
    },
    generation = {
        search_budget = 0,
    },
    engine_scenario = {
        initial_state = {description = "empty surface with one player"},
        supply = {},
        drain = {},
        warm_up_ticks = 0,
        sampling_window_ticks = 0,
        expected_rates = {},
        allowed_discrete_error = 0,
        timeout_seconds = 60,
        note = "Harness capture only; runtime evidence needs a packaged candidate and engine scenario.",
    },
    supported_outcome = "production",
    max_ticks = 900,
}

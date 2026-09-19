--Shared, deliberately boring harness facts for the five positive corpus cases.
--The case files still own their recipes, targets and declared graph; this file
--only keeps their Factorio/mod/research/infrastructure vocabulary consistent.
local Common = {}

Common.mod = {name = "RRC-Fork", version = "1.1.10"}
Common.factorio_branch = "2.0"
Common.source_kind = "harness"
--The offline producer's stable source identity is the harness sentinel.  It is
--not a runtime candidate SHA and must never be presented as engine evidence.
Common.source_sha = "harness"

Common.research = {
    technologies = {"automation", "steel-processing"},
    recipe_bonuses = {},
}

Common.infrastructure = {
    default_infrastructure = true,
    roboport = {name = "roboport", quality = "normal"},
    pole = {name = "medium-electric-pole", quality = "normal"},
    belt = {name = "transport-belt", quality = "normal"},
    inserter = {name = "inserter", quality = "normal"},
    pipe = {name = "pipe", quality = "normal"},
    underground_pipe = {name = "pipe-to-ground", quality = "normal"},
    input_edge = "left",
    output_edge = "top",
}

Common.modules = {
    {name = "speed-module", category = "speed", effects = {speed = 0.2}},
}

Common.beacons = {
    {name = "beacon", module_slots = 2, distribution_effectivity = 1.5},
}

function Common.choice(product_full_name, recipe_name, machine_name)
    return {
        product_full_name = product_full_name,
        recipe_name = recipe_name,
        machine = {name = machine_name, quality = "normal"},
        setup = {
            modules = {{name = "speed-module", quality = "normal"}},
            beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
                modules = {{name = "speed-module", quality = "normal"}}}},
        },
    }
end

function Common.scenario(supply, drain)
    return {
        initial_state = {
            research = {"automation", "steel-processing"},
            surface = "nauvis",
            game_speed = 1,
        },
        supply = supply,
        drain = drain,
        warm_up_ticks = 60,
        sampling_window_ticks = 600,
        expected_rates = {},
        allowed_discrete_error = 0.02,
        timeout_seconds = 30,
    }
end

return Common

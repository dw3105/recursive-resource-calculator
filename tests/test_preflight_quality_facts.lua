--Preflight's quality and prototype-facts boundary. The prepared fixture mirrors the migrated
--tests/test_bp_preflight.lua plain-data catalog: verified receiver facts and a complete inline recipe.
local H = require "tests.harness"

local Preflight = require "logic.bp.preflight"

local function codes(reasons)
    local result = {}
    for _, reason in ipairs(reasons) do result[reason.code] = (result[reason.code] or 0) + 1 end
    return result
end

local function has(reasons, code)
    return codes(reasons)[code] ~= nil
end

local function complete_fixture(change)
    --Fixture provenance: this is the ordinary preflight fixture shape, with the receiver and recipe
    --facts made explicit so each PQ missing-facts case can remove only its named required field.
    local column = {
        recipe_name = "make",
        machine = {name = "assembler"},
        rate = 1,
        recipe = {
            name = "make",
            category = "crafting",
            energy = 1,
            ingredients = {},
            products = {{type = "item", name = "plate", full_name = "item/plate", amount = 1}},
        },
        setup = {modules = {}, beacons = {}},
    }
    local catalog = {
        entity = {
            assembler = {
                name = "assembler",
                type = "assembling-machine",
                module_slots = 4,
                energy_source_type = "electric",
                effect_receiver = {
                    status = "verified_default",
                    source = "prototype",
                    branch = "2.0",
                    base_effect = {},
                    uses_module_effects = true,
                    uses_beacon_effects = true,
                    uses_surface_effects = true,
                },
            },
            beacon = {
                name = "beacon",
                type = "beacon",
                module_slots = 2,
                beacon = {distribution_effectivity = 1.5, counter = "same_type"},
            },
        },
        item = {plate = {name = "plate", type = "item"}},
        module = {
            ["speed-module-3"] = {name = "speed-module-3", effects = {speed = 0.5, quality = -0.25}},
            ["quality-module-3"] = {name = "quality-module-3", effects = {quality = 0.25, speed = -0.05}},
        },
        quality = {normal = {unlocked = true}},
    }
    local snapshot = {
        sheet_id = "sheet",
        state = "current",
        targets = {{full_name = "item/plate", quality = "normal", rate_per_second = 1}},
        selection = {{recipe_name = "make", machine = {name = "assembler"}, modules = {}, beacons = {}}},
    }
    local result = {status = "ok", columns = {column}, recipe_rates = {make = 1}}
    local options = {input_edge = "left", output_edge = "right"}
    if change then change(snapshot, result, catalog, options, column) end
    return snapshot, result, catalog, options
end

local function run(change)
    local snapshot, result, catalog, options = complete_fixture(change)
    return Preflight.check(snapshot, result, catalog, options)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PQ1 four speed modules are ordinary production", function()
        local reasons = run(function(_, _, _, _, column)
            column.setup.modules = {{name = "speed-module-3", count = 4}}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_CHANGING"), false, "speed penalties do not change product quality")
    end)

    H.test(shape .. " PQ2 speed beacons beside speed modules are ordinary production", function()
        local reasons = run(function(_, _, _, _, column)
            column.setup.modules = {{name = "speed-module-3", count = 4}}
            column.setup.beacons = {{name = "beacon", count = 2,
                modules = {{name = "speed-module-3", count = 2}}}}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_CHANGING"), false, "speed penalties and speed beacons do not change quality")
        H.equal(has(reasons, "BP_REJ_BEACON_SPEED_ON_QUALITY"), false, "there is no active quality module")
    end)

    H.test(shape .. " PQ3 a positive quality module changes quality", function()
        local reasons = run(function(_, _, _, _, column)
            column.setup.modules = {{name = "quality-module-3"}}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_CHANGING"), true, "positive quality effect is rejected")
    end)

    H.test(shape .. " PQ4 quality plus a speed beacon is rejected", function()
        local reasons = run(function(_, _, _, _, column)
            column.setup.modules = {{name = "quality-module-3"}}
            column.setup.beacons = {{name = "beacon", count = 1,
                modules = {{name = "speed-module-3"}}}}
        end)
        H.equal(has(reasons, "BP_REJ_BEACON_SPEED_ON_QUALITY"), true, "positive quality plus positive beacon speed is rejected")
    end)

    H.test(shape .. " PQ5 an empty recipe is missing prototype facts", function()
        --Fixture provenance: remove the prepared recipe's required fields, leaving recipe = {} as the requested thin fact.
        local reasons = run(function(_, _, _, _, column) column.recipe = {} end)
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), true, "recipe facts are required")
        H.equal(reasons[1].subject.name, "make", "the missing recipe is named")
    end)

    H.test(shape .. " PQ6 a recipe without products is missing prototype facts", function()
        --Fixture provenance: remove only the prepared recipe's required products field.
        local reasons = run(function(_, _, _, _, column) column.recipe.products = nil end)
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), true, "product facts are required")
    end)

    H.test(shape .. " PQ7 an explicitly empty ingredient list is valid", function()
        local reasons = run(function(_, _, _, _, column) column.recipe.ingredients = {} end)
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), false, "known empty ingredients are complete")
    end)

    H.test(shape .. " PQ8 an inactive thin recipe is ignored", function()
        local reasons = run(function(_, result, _, _, column)
            local inactive = {}
            for key, value in pairs(column) do inactive[key] = value end
            inactive.recipe = {}
            inactive.active = false
            inactive.recipe_name = "inactive"
            inactive.rate = 0
            result.columns[#result.columns + 1] = inactive
            result.recipe_rates.inactive = 0
        end)
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), false, "inactive recipe facts do not block")
    end)

    H.test(shape .. " PQ9 a missing receiver is missing prototype facts", function()
        local reasons = run(function(_, _, catalog, _, column)
            column.setup.modules = {}
            catalog.entity.assembler.effect_receiver = {status = "missing", reason = "receiver capture unavailable"}
        end)
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), true, "missing receiver facts are rejected")
        H.equal(reasons[1].subject.name, "assembler", "the missing receiver machine is named")
        H.equal(reasons[1].detail:find("receiver capture unavailable", 1, true) ~= nil, true, "the receiver reason is named")
    end)

    H.test(shape .. " PQ10 a positive receiver base effect changes quality", function()
        local reasons = run(function(_, _, catalog, _, column)
            column.setup.modules = {}
            catalog.entity.assembler.effect_receiver.base_effect = {quality = 0.25}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_CHANGING"), true, "positive base quality effect is rejected")
    end)

    H.test(shape .. " PQ11 a complete probabilistic product is rejected as probabilistic", function()
        local reasons = run(function(_, _, _, _, column)
            column.recipe.products[1].probability = 0.5
        end)
        H.equal(has(reasons, "BP_REJ_PROBABILISTIC"), true, "probability remains a product rejection")
        H.equal(has(reasons, "BP_REJ_PROTOTYPE_FACTS_MISSING"), false, "optional probability is not a missing fact")
    end)
end

H.done("test_preflight_quality_facts")

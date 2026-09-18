--Blueprint preflight rejects every active unsupported fact together, while ignoring zero-rate unsupported choices.
local H = require "tests.harness"

local Preflight = require "logic.bp.preflight"
local ReasonCodes = require "logic.bp.reason_codes"

local function fixture(change)
    local column = {
        recipe_name = "make",
        machine = {name = "assembler"},
        rate = 1,
        recipe = {name = "make", ingredients = {}, products = {{type = "item", name = "plate", amount = 1}}},
    }
    local catalog = {
        entity = {assembler = {name = "assembler", type = "assembling-machine", module_slots = 2,
            energy_source_type = "electric"}},
        item = {plate = {name = "plate", type = "item"}},
        module = {},
        quality = {normal = {unlocked = true}},
    }
    local snapshot = {sheet_id = "sheet", state = "current", targets = {{full_name = "item/plate", quality = "normal", rate_per_second = 1}},
        selection = {{recipe_name = "make", machine = {name = "assembler", quality = "normal"}, modules = {}, beacons = {}}}}
    local result = {status = "ok", columns = {column}, recipe_rates = {make = 1}}
    local options = {input_edge = "left", output_edge = "right"}
    if change then change(snapshot, result, catalog, options, column) end
    return snapshot, result, catalog, options
end

local function codes(reasons)
    local result = {}
    for _, reason in ipairs(reasons) do result[reason.code] = (result[reason.code] or 0) + 1 end
    return result
end

local function has(reasons, code)
    return codes(reasons)[code] ~= nil
end

local function run(change)
    local snapshot, result, catalog, options = fixture(change)
    return Preflight.check(snapshot, result, catalog, options)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP_REJ_CYCLE reports a solver dependency cycle", function()
        local reasons = run(function(_, result) result.reasons_by_column = {make = "cycle"} end)
        H.equal(has(reasons, "BP_REJ_CYCLE"), true, "cycle rejection")
    end)

    H.test(shape .. " BP_REJ_QUALITY_LOOP reads the solver quality-loop reason", function()
        local reasons = run(function(_, result, _, _, column)
            column.quality_loop = {item = "plate", reason = "quality_loop_nonconvergent"}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_LOOP"), true, "quality loop rejection")
    end)

    H.test(shape .. " BP_REJ_QUALITY_CHANGING identifies module effects rather than names", function()
        local reasons = run(function(_, _, catalog, _, column)
            column.setup = {modules = {{name = "mystery-module"}}, beacons = {}}
            catalog.module["mystery-module"] = {effects = {quality = 0.25}}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_CHANGING"), true, "quality changing rejection")
        --The quality effect is a production fact, not a module-name convention.
        H.equal(has(reasons, "BP_REJ_BEACON_SPEED_ON_QUALITY"), false, "no speed beacon")
    end)

    H.test(shape .. " BP_REJ_SPOILAGE reports a spoiling ingredient", function()
        local reasons = run(function(_, _, catalog, _, column)
            column.recipe.ingredients = {{type = "item", name = "raw", amount = 1}}
            catalog.item.raw = {name = "raw", type = "item", spoil_result = "spoiled"}
        end)
        H.equal(has(reasons, "BP_REJ_SPOILAGE"), true, "spoilage rejection")
    end)

    H.test(shape .. " BP_REJ_PROBABILISTIC reports a chance product", function()
        local reasons = run(function(_, _, _, _, column)
            column.recipe.products = {{type = "item", name = "plate", amount = 1, probability = 0.5}}
        end)
        H.equal(has(reasons, "BP_REJ_PROBABILISTIC"), true, "probability rejection")
    end)

    H.test(shape .. " BP_REJ_RANDOM_AMOUNT reports a random amount product", function()
        local reasons = run(function(_, _, _, _, column)
            column.recipe.products = {{type = "item", name = "plate", amount_min = 1, amount_max = 2}}
        end)
        H.equal(has(reasons, "BP_REJ_RANDOM_AMOUNT"), true, "random amount rejection")
    end)

    H.test(shape .. " BP_REJ_MINING reports a mining step", function()
        local snapshot, result, catalog, options = fixture(function(_, _, catalog, _, column)
            column.machine = {name = "miner"}
            catalog.entity.miner = {name = "miner", type = "mining-drill", module_slots = 0}
        end)
        local reasons = Preflight.check(snapshot, result, catalog, options)
        H.equal(has(reasons, "BP_REJ_MINING"), true, "mining rejection")
    end)

    H.test(shape .. " BP_REJ_BURNER_MACHINE reports a burner machine", function()
        local reasons = run(function(_, _, catalog) catalog.entity.assembler.burner = true end)
        H.equal(has(reasons, "BP_REJ_BURNER_MACHINE"), true, "burner rejection")
    end)

    H.test(shape .. " BP_REJ_FUEL_CONSUMER reports an active burner column", function()
        local reasons = run(function(_, result, _, _, column)
            column.recipe_name, column.machine, column.burner = "fuel", nil, {name = "boiler"}
            result.recipe_rates = {fuel = 1}
        end)
        H.equal(has(reasons, "BP_REJ_FUEL_CONSUMER"), true, "fuel consumer rejection")
        H.equal(has(reasons, "BP_REJ_HANDCRAFT"), false, "burner is not handcraft")
    end)

    H.test(shape .. " BP_REJ_HANDCRAFT reports a step without a machine", function()
        local reasons = run(function(snapshot, _, _, _, column)
            column.machine = nil
            snapshot.selection[1].machine = nil
        end)
        H.equal(has(reasons, "BP_REJ_HANDCRAFT"), true, "handcraft rejection")
    end)

    H.test(shape .. " BP_REJ_NON_ELECTRIC reports a non-electric machine", function()
        local reasons = run(function(_, _, catalog) catalog.entity.assembler.energy_source_type = "heat" end)
        H.equal(has(reasons, "BP_REJ_NON_ELECTRIC"), true, "non-electric rejection")
    end)

    H.test(shape .. " BP_REJ_SNAPSHOT_STALE rejects a stale snapshot", function()
        local reasons = run(function(snapshot) snapshot.state = "stale" end)
        H.equal(has(reasons, "BP_REJ_SNAPSHOT_STALE"), true, "stale rejection")
    end)

    H.test(shape .. " BP_REJ_NON_FINITE_RATE reports a non-finite rate", function()
        local reasons = run(function(_, result) result.recipe_rates.make = math.huge end)
        H.equal(has(reasons, "BP_REJ_NON_FINITE_RATE"), true, "non-finite rejection")
    end)

    H.test(shape .. " BP_REJ_NO_ACTIVE_STEPS rejects a sheet with nothing to build", function()
        local snapshot, result, catalog, options = fixture()
        result.columns, result.recipe_rates = {}, {}
        H.equal(has(Preflight.check(snapshot, result, catalog, options), "BP_REJ_NO_ACTIVE_STEPS"), true, "no steps rejection")
    end)

    H.test(shape .. " BP_REJ_UNRESOLVED_PROTOTYPE reports a missing machine", function()
        local reasons = run(function(_, _, catalog) catalog.entity = {} end)
        H.equal(has(reasons, "BP_REJ_UNRESOLVED_PROTOTYPE"), true, "unresolved rejection")
    end)

    H.test(shape .. " BP_REJ_MODULE_SLOTS_EXCEEDED reports too many modules", function()
        local reasons = run(function(_, _, catalog, _, column)
            catalog.entity.assembler.module_slots = 1
            column.setup = {modules = {{name = "m1"}, {name = "m2"}}, beacons = {}}
        end)
        H.equal(has(reasons, "BP_REJ_MODULE_SLOTS_EXCEEDED"), true, "module slot rejection")
    end)

    H.test(shape .. " BP_REJ_QUALITY_UNAVAILABLE reports a locked quality", function()
        local reasons = run(function(_, _, _, options, column)
            column.machine = {name = "assembler", quality = "rare"}
            options.unlocked_qualities = {rare = false}
        end)
        H.equal(has(reasons, "BP_REJ_QUALITY_UNAVAILABLE"), true, "quality rejection")
    end)

    H.test(shape .. " BP_REJ_EDGES_EQUAL rejects equal infrastructure edges", function()
        local reasons = run(function(_, _, _, options) options.input_edge, options.output_edge = "left", "left" end)
        H.equal(has(reasons, "BP_REJ_EDGES_EQUAL"), true, "edge rejection")
    end)

    H.test(shape .. " BP_REJ_BELT_FAMILY_MISSING rejects a belt without a family", function()
        local reasons = run(function(_, _, catalog, options)
            options.belt = "orphan-belt"
            catalog.belt = {belt = "orphan-belt"}
        end)
        H.equal(has(reasons, "BP_REJ_BELT_FAMILY_MISSING"), true, "belt family rejection")
    end)

    H.test(shape .. " BP_REJ_BEACON_SPEED_ON_QUALITY rejects quality plus speed beacons", function()
        local reasons = run(function(_, _, catalog, _, column)
            catalog.module.quality = {effects = {quality = 0.2}}
            catalog.module.speed = {effects = {speed = 0.2}}
            column.setup = {modules = {{name = "quality"}}, beacons = {{name = "beacon", count = 1, modules = {{name = "speed"}}}}}
        end)
        H.equal(has(reasons, "BP_REJ_BEACON_SPEED_ON_QUALITY"), true, "quality beacon rejection")
    end)

    H.test(shape .. " BP_REJ_SIZE_MACHINES reports count and limit", function()
        local snapshot, result, catalog, options = fixture()
        result.machine_count = 101
        local reasons = Preflight.check(snapshot, result, catalog, options)
        H.equal(has(reasons, "BP_REJ_SIZE_MACHINES"), true, "machine limit rejection")
        H.equal(reasons[1].detail:find("101", 1, true) ~= nil, true, "machine count in detail")
        H.equal(reasons[1].detail:find("100", 1, true) ~= nil, true, "machine limit in detail")
    end)

    H.test(shape .. " BP_REJ_SIZE_STEPS reports count and limit", function()
        local snapshot, result, catalog, options = fixture()
        result.step_count = 31
        local reasons = Preflight.check(snapshot, result, catalog, options)
        H.equal(has(reasons, "BP_REJ_SIZE_STEPS"), true, "step limit rejection")
        local found
        for _, reason in ipairs(reasons) do if reason.code == "BP_REJ_SIZE_STEPS" then found = reason end end
        H.equal(found.detail:find("31", 1, true) ~= nil, true, "step count in detail")
        H.equal(found.detail:find("30", 1, true) ~= nil, true, "step limit in detail")
    end)

    H.test(shape .. " BP-03 supported sheet returns no reasons", function()
        H.equal(#run(), 0, "supported sheet")
    end)

    H.test(shape .. " BP-03 zero-rate unsupported recipe does not block", function()
        local snapshot, result, catalog, options = fixture(function(_, result, catalog)
            result.columns[#result.columns + 1] = {recipe_name = "inactive", machine = {name = "miner"}, rate = 0,
                recipe = {name = "inactive", ingredients = {}, products = {{type = "item", name = "plate", amount = 1}}}}
            result.recipe_rates.inactive = 0
            catalog.entity.miner = {name = "miner", type = "mining-drill"}
        end)
        local reasons = Preflight.check(snapshot, result, catalog, options)
        H.equal(has(reasons, "BP_REJ_MINING"), false, "inactive mining does not block")
        H.equal(#reasons, 0, "inactive unsupported recipe is ignored")
    end)

    H.test(shape .. " BP-03 reports several blockers at once", function()
        local snapshot, result, catalog, options = fixture(function(_, _, catalog, options, column)
            column.machine = {name = "miner"}
            catalog.entity.miner = {name = "miner", type = "mining-drill"}
            column.recipe.products = {{type = "item", name = "plate", amount = 1, probability = 0.5}}
            options.input_edge, options.output_edge = "left", "left"
        end)
        local reasons = Preflight.check(snapshot, result, catalog, options)
        local found = codes(reasons)
        H.equal(found.BP_REJ_MINING ~= nil, true, "first blocker")
        H.equal(found.BP_REJ_PROBABILISTIC ~= nil, true, "second blocker")
        H.equal(found.BP_REJ_EDGES_EQUAL ~= nil, true, "third blocker")
    end)

    H.test(shape .. " BP-03 every returned code is enum-backed and localised", function()
        local snapshot, result, catalog, options = fixture(function(_, _, catalog, options, column)
            column.machine = {name = "miner"}
            catalog.entity.miner = {name = "miner", type = "mining-drill"}
            options.input_edge, options.output_edge = "left", "left"
        end)
        for _, reason in ipairs(Preflight.check(snapshot, result, catalog, options)) do
            H.equal(ReasonCodes.all()[reason.code], true, "enum code " .. reason.code)
            H.equal(reason.locale_key ~= nil, true, "locale key " .. reason.code)
            H.equal(reason.subject.name ~= nil, true, "named subject " .. reason.code)
        end
    end)
end

H.done("test_bp_preflight")

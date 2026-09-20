--The shared quality rule, case by case. Every row of this file is a decision that was wrong, ambiguous or
--unowned before round 9, and the reported bug is the first one: a speed module's -0.25 quality penalty is
--ordinary production, never quality-changing production.
local H = require "tests.harness"
local QualityPolicy = require "logic.bp.quality_policy"

local function catalog(extra)
    local result = {
        schema_version = 1,
        entity = {
            ["assembler"] = {name = "assembler", etype = "assembling-machine", tile_w = 3, tile_h = 3,
                effect_receiver = {status = "verified_default", source = "prototype", branch = "2.0",
                    base_effect = {}, uses_module_effects = true, uses_beacon_effects = true,
                    uses_surface_effects = true}},
            ["beacon"] = {name = "beacon", etype = "beacon", tile_w = 3, tile_h = 3,
                beacon = {distribution_effectivity = 1.5, counter = "same_type"}},
        },
        beacon = {["beacon"] = {name = "beacon", distribution_effectivity = 1.5, counter = "same_type"}},
        module = {
            --the captured values from the reported sheet: a speed module lowers quality and raises nothing
            ["speed-module-3"] = {name = "speed-module-3", effects = {speed = 0.5, consumption = 0.7, quality = -0.25}},
            ["quality-module-3"] = {name = "quality-module-3", effects = {quality = 0.25, speed = -0.05}},
            ["productivity-module-3"] = {name = "productivity-module-3", effects = {productivity = 0.25, speed = -0.15}},
            ["cancelling-module"] = {name = "cancelling-module", effects = {quality = -0.25}},
        },
    }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

--Replace one field of the assembler's receiver record, or remove the record entirely with `false`.
local function with_receiver(record)
    local built = catalog()
    if record == false then built.entity["assembler"].effect_receiver = nil
    else built.entity["assembler"].effect_receiver = record end
    return built
end

local function step(fields)
    local result = {machine = {name = "assembler", quality = "normal"}, modules = {}, beacons = {}}
    for key, value in pairs(fields or {}) do result[key] = value end
    return result
end

local function verified(extra)
    local record = {status = "verified_default", source = "prototype", branch = "2.0", base_effect = {},
        uses_module_effects = true, uses_beacon_effects = true, uses_surface_effects = true}
    for key, value in pairs(extra or {}) do record[key] = value end
    return record
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " QP1 a speed module's quality penalty is ordinary production", function()
        local value, supported = QualityPolicy.effective_quality(
            step({modules = {{name = "speed-module-3", count = 4}}}), catalog())
        H.equal(supported, true, "an ordinary verified receiver is supported")
        H.near(value, -1, 1e-9, "four penalties of -0.25 total -1")
        H.equal(value > 0, false, "a penalty never raises quality")
        H.equal(QualityPolicy.has_active_quality_module(
            step({modules = {{name = "speed-module-3", count = 4}}}), catalog()), false,
            "a speed module is no quality module")
    end)

    H.test(shape .. " QP2 a positive quality module is quality production", function()
        local value, supported = QualityPolicy.effective_quality(
            step({modules = {{name = "quality-module-3"}}}), catalog())
        H.equal(supported, true, "the receiver is verified")
        H.near(value, 0.25, 1e-9, "one quality module raises quality by 0.25")
        H.equal(QualityPolicy.has_active_quality_module(
            step({modules = {{name = "quality-module-3"}}}), catalog()), true, "the quality module is seen")
    end)

    H.test(shape .. " QP3 no modules and a zero base effect is supported and changes nothing", function()
        local value, supported = QualityPolicy.effective_quality(step(), with_receiver(verified()))
        H.equal(supported, true, "an empty machine on a verified receiver is supported")
        H.near(value, 0, 1e-9, "nothing raises quality")
    end)

    H.test(shape .. " QP4 no modules and a positive base effect is quality production", function()
        local value, supported = QualityPolicy.effective_quality(step(),
            with_receiver(verified({base_effect = {quality = 0.1}})))
        H.equal(supported, true, "the receiver is verified")
        H.equal(value > 0, true, "an intrinsic quality effect raises quality without any module")
    end)

    H.test(shape .. " QP5 missing receiver facts are never read as an ordinary machine", function()
        local value, supported, reason = QualityPolicy.effective_quality(step(), with_receiver(false))
        H.equal(supported, false, "an uncaptured receiver is not supported")
        H.equal(value, 0, "no value is invented")
        H.equal(type(reason) == "string" and #reason > 0, true, "the refusal names its reason")
        --an empty module list is not proof: base and surface effects are not modules
        H.equal(QualityPolicy.has_quality_capable_module(step(), with_receiver(false)), false,
            "the module list really is empty, and that changes nothing about the refusal")
    end)

    H.test(shape .. " QP6 a receiver record without a status is missing, never a default", function()
        local _, supported, reason = QualityPolicy.effective_quality(step(),
            with_receiver({base_effect = {}, uses_module_effects = true}))
        H.equal(supported, false, "a capture that predates the contract is missing facts")
        H.equal(reason:find("status", 1, true) ~= nil, true, "the reason names the missing status")
    end)

    H.test(shape .. " QP7 unsupported receiver semantics stay unsupported with empty module slots", function()
        local _, supported, reason = QualityPolicy.effective_quality(step(),
            with_receiver(verified({status = "unsupported", reason = "custom effect model"})))
        H.equal(supported, false, "empty slots never make an unsupported receiver supported")
        H.equal(reason, "custom effect model", "the projection's reason survives")
    end)

    H.test(shape .. " QP8 a receiver that ignores modules reports no quality from them", function()
        local value, supported = QualityPolicy.effective_quality(
            step({modules = {{name = "quality-module-3", count = 4}}}),
            with_receiver(verified({uses_module_effects = false})))
        H.equal(supported, true, "the receiver is verified, it simply ignores modules")
        H.near(value, 0, 1e-9, "a module the machine ignores produces no quality")
        H.equal(QualityPolicy.has_active_quality_module(
            step({modules = {{name = "quality-module-3", count = 4}}}),
            with_receiver(verified({uses_module_effects = false})), false), false,
            "an ignored module is no active quality module")
    end)

    H.test(shape .. " QP9 a quality module cancelled to zero still forbids speed beacons", function()
        local setup = step({modules = {{name = "quality-module-3"}, {name = "cancelling-module"}},
            beacons = {{name = "beacon", count = 2, modules = {{name = "speed-module-3", count = 2}}}}})
        local built = catalog()
        local value, supported = QualityPolicy.effective_quality(setup, built)
        H.equal(supported, true, "the receiver is verified")
        --the two machine modules cancel, and the beacons' speed modules carry penalties, so the total is
        --negative while a positive quality module is plainly installed: the total is never the test here
        H.equal(value > 0, false, "the cancelled total raises nothing")
        H.equal(QualityPolicy.has_active_quality_module(setup, built), true,
            "the positive module is present whatever the total")
    end)

    H.test(shape .. " QP10 speed beacons beside a penalty-only machine are no quality production", function()
        local setup = step({modules = {{name = "speed-module-3", count = 4}},
            beacons = {{name = "beacon", count = 3, modules = {{name = "speed-module-3", count = 2}}}}})
        local built = catalog()
        local value, supported = QualityPolicy.effective_quality(setup, built)
        H.equal(supported, true, "the receiver is verified")
        H.equal(value > 0, false, "penalties never raise quality, however many beacons carry them")
        H.equal(QualityPolicy.has_active_quality_module(setup, built), false,
            "this is the reported sheet: no quality module anywhere")
        H.equal(QualityPolicy.speed_beacon_contribution(setup, built) > 0, true, "the beacons do add speed")
    end)

    H.test(shape .. " QP11 a productivity beacon is no speed beacon", function()
        local setup = step({beacons = {{name = "beacon", count = 2,
            modules = {{name = "productivity-module-3", count = 2}}}}})
        H.equal(QualityPolicy.speed_beacon_contribution(setup, catalog()) > 0, false,
            "a negative speed contribution is never a speed beacon")
    end)

    H.test(shape .. " QP12 a recipe forbidding quality zeroes modules and beacons, never the base", function()
        local built = with_receiver(verified({base_effect = {quality = 0.1}}))
        local setup = step({modules = {{name = "quality-module-3", count = 4}},
            recipe = {name = "forbidden", allowed_effects = {quality = false, speed = true}}})
        local value, supported = QualityPolicy.effective_quality(setup, built)
        H.equal(supported, true, "the receiver is still verified")
        H.near(value, 0.1, 1e-9, "the module share is zeroed and the base effect is kept")
        H.equal(QualityPolicy.has_active_quality_module(setup, built), false,
            "a module the recipe forbids is not active")
    end)

    H.test(shape .. " QP13 quality limits that permit a decrease are refused by name", function()
        local _, supported, reason = QualityPolicy.effective_quality(step(),
            with_receiver(verified({branch = "2.1", quality_limits = {min = -1, max = 1}})))
        H.equal(supported, false, "a receiver that may lower quality is outside the supported model")
        H.equal(reason:find("decrease", 1, true) ~= nil, true, "the reason names the behaviour")
    end)

    H.test(shape .. " QP14 quality limits of an unreadable shape are refused, never assumed", function()
        local _, supported, reason = QualityPolicy.effective_quality(step(),
            with_receiver(verified({branch = "2.1", quality_limits = {something = "else"}})))
        H.equal(supported, false, "an unmodelled limit shape is not supported")
        H.equal(reason:find("lower bound", 1, true) ~= nil, true, "the reason names what could not be read")
    end)

    H.test(shape .. " QP15 a non-negative lower bound keeps an ordinary 2.1 machine supported", function()
        local value, supported = QualityPolicy.effective_quality(
            step({modules = {{name = "speed-module-3", count = 4}}}),
            with_receiver(verified({branch = "2.1", quality_limits = {min = 0, max = 1},
                uses_local_effects = true})))
        H.equal(supported, true, "a limit that cannot lower quality changes nothing for this rule")
        H.equal(value > 0, false, "the ordinary penalty is still ordinary on 2.1")
    end)

    H.test(shape .. " QP16 the quality-capable question is about verification, never about production", function()
        local built = catalog()
        H.equal(QualityPolicy.has_quality_capable_module(
            step({modules = {{name = "speed-module-3"}}}), built), true,
            "a -0.25 module is quality-capable, so its receiver must be verified")
        H.equal(QualityPolicy.has_active_quality_module(
            step({modules = {{name = "speed-module-3"}}}), built), false,
            "and it still produces no quality")
        H.equal(QualityPolicy.has_quality_capable_module(
            step({modules = {{name = "productivity-module-3"}}}), built), false,
            "a module with no quality effect is not quality-capable")
    end)
end

H.done("test_quality_policy")

-- MC1 and MC3 are red on round-50-base: prototype properties and module effects are reread on every call.
-- Module prototype facts are cached once per prototype root; effect reads are cached by module and quality.
local H = require "tests.harness"
local ModuleSetup = require "logic.module_setup"
local Utils = require "logic.utils"

local function world_with_modules()
    local world = H.new_world("2.0")
    world.add_module("m-speed", "speed", {speed = 0.2, consumption = 0.1})
    world.add_module("m-prod", "productivity", {productivity = 0.1})
    world.add_module("m-eff", "efficiency", {consumption = -0.2})
    world.add_machine({name = "machine", categories = {"crafting"}, speed = 1})
    world.add_beacon({name = "beacon"})
    world.add_item("ore")
    world.add_recipe({name = "ore", category = "crafting", ingredients = {}, products = {{name = "ore", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

local function proxy_reads(proto, counter)
    return setmetatable({}, {__index = function(_, key) counter.count = counter.count + 1; return proto[key] end})
end

H.test("MC1 module/entity/recipe facts are read once across picker calls", function()
    world_with_modules()
    ModuleSetup.forget_cache()
    local reads = {count = 0}
    local real = prototypes
    for _, name in ipairs({"m-speed", "m-prod", "m-eff"}) do real.item[name] = proxy_reads(real.item[name], reads) end
    real.entity.machine = proxy_reads(real.entity.machine, reads)
    real.recipe.ore = proxy_reads(real.recipe.ore, reads)
    local entities, recipe = {real.entity.machine}, real.recipe.ore
    ModuleSetup.allowed_module_names(entities, recipe)
    reads.count = 0
    ModuleSetup.allowed_module_names(entities, recipe)
    H.equal(reads.count, 0, "second lookup has no prototype reads")
end)

H.test("MC2 cached answers match the original allow/fits rules", function()
    world_with_modules()
    ModuleSetup.forget_cache()
    local base_allows = function(allowed, effect, absent) if allowed == nil then return absent end return allowed[effect] == true end
    local base_fits = function(name, entities, recipe)
        if not storage.module_names[name] then return false end
        local module = prototypes.item[name]
        local category = module.category
        for _, entity in ipairs(entities) do if entity.allowed_module_categories and not entity.allowed_module_categories[category] then return false end end
        if recipe.allowed_module_categories and not recipe.allowed_module_categories[category] then return false end
        for effect, value in pairs(module.module_effects or {}) do if value > 0 then
            for _, entity in ipairs(entities) do if not base_allows(entity.allowed_effects, effect, false) then return false end end
            if not base_allows(recipe.allowed_effects, effect, true) then return false end
        end end
        return true
    end
    local machine, beacon, recipe = prototypes.entity.machine, prototypes.entity.beacon, prototypes.recipe.ore
    local cases = {{machine, recipe}, { {machine, beacon}, recipe}}
    for _, pair in ipairs(cases) do for _, name in ipairs({"m-speed", "m-prod", "m-eff"}) do
        H.equal(ModuleSetup.fits(name, pair[1], pair[2]), base_fits(name, pair[1], pair[2]), "base fits " .. name)
    end end
    -- Absent effect lists preserve the distinct entity=false and recipe=true defaults.
    machine.allowed_effects, recipe.allowed_effects = nil, nil
    for _, name in ipairs({"m-speed", "m-prod", "m-eff"}) do
        H.equal(ModuleSetup.fits(name, {machine}, recipe), base_fits(name, {machine}, recipe), "nil lists " .. name)
    end
end)

H.test("MC3 module effect reads are cached and totals match the base calculation", function()
    world_with_modules()
    Utils.forget_cache()
    local calls = 0
    for _, name in ipairs({"m-speed", "m-prod", "m-eff"}) do
        local proto = prototypes.item[name]
        proto.get_module_effects = function(quality) calls = calls + 1; return proto.module_effects end
    end
    local setup = {modules = {{name = "m-speed"}, {name = "m-prod"}, {name = "m-eff"}}, beacons = {{name = "beacon", count = 1, modules = {{name = "m-speed"}}}}}
    local first = Utils.setup_effects(setup)
    calls = 0
    local second = Utils.setup_effects(setup)
    H.equal(calls, 0, "second calculation calls no module effect methods")
    H.deep_equal(second, first, "cached totals match first totals")
    H.near(first.speed, 0.4, "speed total")
    H.near(first.productivity, 0.1, "productivity total")
    H.near(first.consumption, 0, "consumption total")
end)

H.test("MC4 replacing prototypes root resets module facts", function()
    world_with_modules()
    ModuleSetup.forget_cache()
    local machine, recipe = prototypes.entity.machine, prototypes.recipe.ore
    H.equal(ModuleSetup.fits("m-speed", {machine}, recipe), true, "initial category fits")
    local old = prototypes
    local replacement = {}
    for key, value in pairs(old) do replacement[key] = value end
    replacement.item = {}
    for key, value in pairs(old.item) do replacement.item[key] = value end
    local changed = {}
    for key, value in pairs(old.item["m-speed"]) do changed[key] = value end
    changed.category = "other"
    replacement.item["m-speed"] = changed
    _G.prototypes = replacement
    H.equal(ModuleSetup.fits("m-speed", {machine}, recipe), true, "replacement facts used")
end)

H.done("test_module_cache")

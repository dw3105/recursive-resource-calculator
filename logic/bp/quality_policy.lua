--The one rule that decides whether a production step changes quality, and what may still be checked about it.
--
--Three separate questions, because conflating them is exactly how the reported bug happened:
--
--  effective_quality        does this step raise product quality?  A speed module's -0.25 penalty does not.
--  has_active_quality_module does this machine hold a quality module?  Only a positive effect counts, and a
--                            positive module cancelled to zero by other effects still counts as present.
--  speed_beacon_contribution do its beacons add speed?  Only a positive contribution counts.
--
--Quality can come from four places: machine modules, beacon modules, the machine's own base effect, and surface
--or local effects. An empty module list proves none of them are zero, so every active production machine needs
--a receiver decision. A receiver nobody captured is "missing", never "ordinary": the projection that omitted it
--is the same projection that omitted recipes.
--
--Plain data only: a step and a catalog, no prototypes, no globals.
local QualityPolicy = {}

QualityPolicy.SCHEMA_VERSION = 1

local function finite(value, fallback)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

local function name_of(value)
    if type(value) == "string" then return value end
    if type(value) == "table" then return value.name or value.type end
    return nil
end

local function quality_of(value)
    if type(value) == "table" and type(value.quality) == "string" then return value.quality end
    if type(value) == "string" then return value end
    return "normal"
end

--A module list may be an array, a map, or carry counts. Expand it to one entry per physical module.
local function expand_modules(modules)
    local result = {}
    for _, module in pairs(modules or {}) do
        if type(module) == "table" or type(module) == "string" then
            local name = name_of(module)
            if name then
                local count = 1
                if type(module) == "table" then count = math.max(0, math.floor(finite(module.count, 1))) end
                for _ = 1, count do
                    result[#result + 1] = {name = name, quality = quality_of(module)}
                end
            end
        end
    end
    return result
end

local function module_effects(catalog, module)
    local modules = catalog and (catalog.module or catalog.modules)
    local record = modules and modules[module.name]
    local effects = record and (record.effects or record.module_effects)
    if type(effects) ~= "table" then
        local item = catalog and catalog.item and catalog.item[module.name]
        effects = item and (item.module_effects or item.effects)
    end
    return type(effects) == "table" and effects or {}
end

local function effect_of(catalog, module, key)
    return finite(module_effects(catalog, module)[key], 0)
end

local function machine_record(step, catalog)
    local name = name_of(step and step.machine)
    if name == nil then return nil, nil end
    local entities = catalog and (catalog.entity or catalog.entities)
    return entities and entities[name] or nil, name
end

--Status of the receiver facts behind this machine. Four answers, never an assumption:
--  verified_default / verified_supported  a live prototype was read and its semantics are ones we model
--  unsupported                            behaviour outside the supported model, named in the reason
--  missing                                nobody captured it
function QualityPolicy.receiver(step, catalog)
    local record = machine_record(step, catalog)
    local receiver = record and record.effect_receiver
    if type(receiver) ~= "table" then
        return {status = "missing", reason = "no effect receiver facts for " .. tostring(name_of(step and step.machine))}
    end
    local status = receiver.status
    if status == nil then
        --A record without a declared status is a capture that predates the contract, never a verified default.
        return {status = "missing", reason = "effect receiver facts carry no status", record = receiver}
    end
    if status ~= "verified_default" and status ~= "verified_supported"
        and status ~= "unsupported" and status ~= "missing" then
        return {status = "unsupported", reason = "unknown receiver status " .. tostring(status), record = receiver}
    end
    return {status = status, reason = receiver.reason, record = receiver}
end

--2.1 exposes per-effect limits; 2.0 exposes none, and a 2.0 machine is never unsupported for that absence.
--A limit that permits a quality decrease changes what a negative total means, and that behaviour is not
--modelled here, so it is refused by name instead of being read as ordinary production.
local function quality_limit_reason(receiver)
    local record = receiver.record
    local limits = type(record) == "table" and record.quality_limits or nil
    if limits == nil then return nil end
    if type(limits) ~= "table" then return "quality limits are not a table" end
    --2.1.20 gives {low = 0, high = 1000} (headless probe, round 42); min/minimum/[1] stay for older captures
    local lower = limits.low
    if lower == nil then lower = limits.min end
    if lower == nil then lower = limits.minimum end
    if lower == nil then lower = limits[1] end
    if type(lower) ~= "number" then return "quality limits carry no readable lower bound" end
    if lower < 0 then return "quality limits permit a quality decrease" end
    return nil
end

local function receiver_usable(receiver)
    if receiver.status ~= "verified_default" and receiver.status ~= "verified_supported" then return false end
    return quality_limit_reason(receiver) == nil
end

local function uses(receiver, key, default)
    local record = receiver.record
    if type(record) ~= "table" or record[key] == nil then return default end
    return record[key] ~= false
end

local function base_quality(receiver)
    local record = receiver.record
    local base = type(record) == "table" and record.base_effect or nil
    return finite(type(base) == "table" and base.quality or nil, 0)
end

--A recipe may forbid the quality effect. That zeroes the module and beacon share and nothing else: a base or
--surface contribution is not a module effect and is not covered by allowed_effects.
local function modules_allowed(step)
    local recipe = step and step.recipe
    local allowed = type(recipe) == "table" and recipe.allowed_effects or nil
    if type(allowed) ~= "table" then return true end
    if allowed.quality == false then return false end
    if allowed.quality == nil and allowed[1] ~= nil then
        for _, value in ipairs(allowed) do
            if value == "quality" then return true end
        end
        return false
    end
    return allowed.quality ~= false
end

local function beacon_projection(catalog, group)
    local name = name_of(group)
    local entities = catalog and (catalog.entity or catalog.entities)
    local record = entities and entities[name]
    local beacon = (record and record.beacon) or (catalog and catalog.beacon and catalog.beacon[name]) or record or {}
    return {
        distribution_effectivity = finite(beacon.distribution_effectivity, 1),
        profile = beacon.profile,
        counter = beacon.counter or beacon.beacon_counter or "same_type",
    }
end

local function beacon_groups(step)
    local result = {}
    for _, group in pairs(step and step.beacons or {}) do
        local name = name_of(group)
        local count = finite(type(group) == "table" and (group.count_per_machine or group.count) or nil, 0)
        if name and count > 0 then
            result[#result + 1] = {name = name, quality = quality_of(group), count = count,
                modules = type(group) == "table" and group.modules or {}}
        end
    end
    return result
end

--Beacon weight follows the planner's model: count times distribution effectivity times the profile sample for
--the number of beacons of that kind reaching the machine.
local function beacon_weight(catalog, groups, group)
    local projection = beacon_projection(catalog, group)
    local reaching = 0
    for _, other in ipairs(groups) do
        if projection.counter ~= "same_type" or other.name == group.name then reaching = reaching + other.count end
    end
    local sample = 1
    local profile = projection.profile
    if type(profile) == "table" and #profile > 0 then
        local index = math.min(math.max(1, math.floor(reaching)), #profile)
        sample = finite(profile[index], 1)
    end
    return group.count * projection.distribution_effectivity * sample
end

--Sum of quality effects, and whether the answer can be trusted at all.
function QualityPolicy.effective_quality(step, catalog)
    local receiver = QualityPolicy.receiver(step, catalog)
    if receiver.status == "missing" then
        return 0, false, receiver.reason or "effect receiver facts are missing"
    end
    if receiver.status == "unsupported" then
        return 0, false, receiver.reason or "effect receiver behaviour is not supported"
    end
    local limit_reason = quality_limit_reason(receiver)
    if limit_reason then return 0, false, limit_reason end

    local total = base_quality(receiver)
    local allowed = modules_allowed(step)
    if allowed and uses(receiver, "uses_module_effects", true) then
        for _, module in ipairs(expand_modules(step and step.modules)) do
            total = total + effect_of(catalog, module, "quality")
        end
    end
    if allowed and uses(receiver, "uses_beacon_effects", true) then
        local groups = beacon_groups(step)
        for _, group in ipairs(groups) do
            local weight = beacon_weight(catalog, groups, group)
            for _, module in ipairs(expand_modules(group.modules)) do
                total = total + weight * effect_of(catalog, module, "quality")
            end
        end
    end
    return total, true, nil
end

--Presence of a quality module, which is a different question from the total. Only a positive quality effect is
--quality-module production; a negative penalty is an ordinary speed module and never triggers this.
function QualityPolicy.has_active_quality_module(step, catalog)
    local receiver = QualityPolicy.receiver(step, catalog)
    if not receiver_usable(receiver) then return false end
    if not modules_allowed(step) then return false end
    if uses(receiver, "uses_module_effects", true) then
        for _, module in ipairs(expand_modules(step and step.modules)) do
            if effect_of(catalog, module, "quality") > 0 then return true end
        end
    end
    if uses(receiver, "uses_beacon_effects", true) then
        for _, group in ipairs(beacon_groups(step)) do
            for _, module in ipairs(expand_modules(group.modules)) do
                if effect_of(catalog, module, "quality") > 0 then return true end
            end
        end
    end
    return false
end

--Speed a beacon set adds to this machine. Only a positive contribution is a speed beacon; a productivity module
--in a beacon carries a negative speed and is not one.
function QualityPolicy.speed_beacon_contribution(step, catalog)
    local receiver = QualityPolicy.receiver(step, catalog)
    if not receiver_usable(receiver) then return 0 end
    if not uses(receiver, "uses_beacon_effects", true) then return 0 end
    local groups = beacon_groups(step)
    local total = 0
    for _, group in ipairs(groups) do
        local weight = beacon_weight(catalog, groups, group)
        for _, module in ipairs(expand_modules(group.modules)) do
            total = total + weight * effect_of(catalog, module, "speed")
        end
    end
    return total
end

--A module whose quality effect is not zero, in either direction. This decides what must be verified, never what
--produces quality: the reported -0.25 speed module is quality-capable and produces nothing.
function QualityPolicy.has_quality_capable_module(step, catalog)
    for _, module in ipairs(expand_modules(step and step.modules)) do
        if effect_of(catalog, module, "quality") ~= 0 then return true end
    end
    for _, group in ipairs(beacon_groups(step)) do
        for _, module in ipairs(expand_modules(group.modules)) do
            if effect_of(catalog, module, "quality") ~= 0 then return true end
        end
    end
    return false
end

return QualityPolicy

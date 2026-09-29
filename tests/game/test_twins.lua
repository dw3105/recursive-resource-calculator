--Round 48 D4, engine half of every twin (docs/twins.md): build the twin's published blueprint for real, run it, and
--derive the engine's verdict (ok | defect | waste) from what the game does. The offline half is tests/test_twins.lua.
--tests/twins/index.lua is written by tools/game_stage.sh (the engine cannot list a directory); offline it is absent
--and this file registers nothing.
local Lab = require "tests.game.lib.lab"
local Twin = require "tests.twins.lib.twin"
local ok_index, INDEX = pcall(require, "tests.twins.index")
local TWINS = {}
if ok_index and type(INDEX) == "table" then
    for _, name in ipairs(INDEX) do TWINS[#TWINS + 1] = require(name) end
end

local WINDOW = 1200
local SPACING = 128

local function key(x, y) return x .. "," .. y end

local function slowest_belt_speed(twin)
    local slow
    for _, e in ipairs(twin.entities or {}) do
        local p = prototypes.entity[e.name]
        local ok, speed = pcall(function() return p and p.belt_speed end)
        if ok and speed and speed > 0 and (slow == nil or speed < slow) then slow = speed end
    end
    return slow
end

--Twin entity id -> built entity, through its top-left tile.
local function map_entities(surface, twin, built)
    local by_id = {}
    for _, e in ipairs(twin.entities or {}) do
        local ent = Lab.at(surface, built, e.x, e.y)
        if ent then by_id[e.id] = ent end
    end
    return by_id
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

--Engine facts behind each preflight code (check = "prototype"). Returns true when the subject HAS the fact the code
--rejects, false when it lacks it, nil + reason when this code has no engine fact rule yet.
local function product_list(recipe)
    local ok, list = pcall(function() return recipe.products end)
    return ok and list or {}
end
local FACTS = {
    BP_REJ_SPOILAGE = function(kind, p)
        if kind == "item" then local ok, t = pcall(p.get_spoil_ticks); return ok and t and t > 0 end
        for _, r in ipairs(product_list(p)) do
            local item = r.type == "item" and prototypes.item[r.name]
            if item then local ok, t = pcall(item.get_spoil_ticks); if ok and t and t > 0 then return true end end
        end
        return false
    end,
    BP_REJ_PROBABILISTIC = function(_, p)
        for _, r in ipairs(product_list(p)) do if r.probability and r.probability < 1 then return true end end
        return false
    end,
    BP_REJ_RANDOM_AMOUNT = function(_, p)
        for _, r in ipairs(product_list(p)) do if r.amount_min and r.amount_min ~= r.amount_max then return true end end
        return false
    end,
    BP_REJ_MINING = function(_, p) return p.type == "mining-drill" end,
    BP_REJ_BURNER_MACHINE = function(_, p) return p.burner_prototype ~= nil end,
    BP_REJ_NON_ELECTRIC = function(_, p) return p.electric_energy_source_prototype == nil end,
    BP_REJ_FUEL_CONSUMER = function(_, p) return p.burner_prototype ~= nil or p.fluid_energy_source_prototype ~= nil end,
    BP_REJ_SURFACE_RESTRICTED = function(_, p)
        local ok, c = pcall(function() return p.surface_conditions end)
        return ok and c ~= nil and next(c) ~= nil
    end,
    BP_REJ_BELT_FAMILY_MISSING = function(_, p) return p == nil end,
    BP_REJ_QUALITY_UNAVAILABLE = function(_, p) return p == nil or p.hidden == true end,
}

local function prototype_verdict(twin)
    local s = twin.subject or {}
    local store = ({recipe = prototypes.recipe, entity = prototypes.entity, item = prototypes.item, quality = prototypes.quality})[s.kind]
    if not store then return nil, "subject.kind must be recipe|entity|item|quality" end
    local rule = FACTS[twin.rule]
    if not rule then return nil, "no engine fact rule for " .. twin.rule .. " yet (integrator adds it)" end
    local has = rule(s.kind, store[s.name])
    return has and "defect" or "ok", "subject " .. s.kind .. " " .. tostring(s.name) .. " has fact: " .. tostring(has)
end

local STATIC = {placeable = true, network = true, powered = true, pickup_drop = true, underground_pair = true}

local function static_verdict(twin, surface, built, by_id, powered_ok)
    local check = twin.check
    if check == "placeable" then
        return #built.refused > 0 and "defect" or "ok", "refused entity numbers: " .. serpent.line(built.refused)
    end
    if #built.refused > 0 then return nil, "twin does not place: " .. serpent.line(built.refused) end
    if check == "network" then
        local elec, logi = {}, {}
        for _, ent in pairs(by_id) do
            if ent.type == "electric-pole" then elec[ent.electric_network_id or -1] = true end
            if ent.type == "roboport" then
                local n = ent.logistic_network
                logi[n and n.network_id or -1] = true
            end
        end
        local ne, nl = #sorted_keys(elec), #sorted_keys(logi)
        return (ne > 1 or nl > 1) and "defect" or "ok", "electric networks " .. ne .. ", logistic networks " .. nl
    end
    if check == "powered" then
        local bad = {}
        for id, ent in pairs(by_id) do
            local ok, connected = pcall(ent.is_connected_to_electric_network)
            if ok and connected == false then bad[#bad + 1] = id end
        end
        table.sort(bad)
        return #bad > 0 and "defect" or "ok", "unpowered: " .. serpent.line(bad) .. " lab power " .. tostring(powered_ok)
    end
    if check == "pickup_drop" then
        local bad = {}
        for id, ent in pairs(by_id) do
            if ent.type == "inserter" and (ent.pickup_target == nil or ent.drop_target == nil) then bad[#bad + 1] = id end
        end
        table.sort(bad)
        return #bad > 0 and "defect" or "ok", "hands with no pickup or drop target: " .. serpent.line(bad)
    end
    if check == "underground_pair" then
        local bad = {}
        for id, ent in pairs(by_id) do
            if ent.type == "underground-belt" and ent.neighbours == nil then bad[#bad + 1] = id end
            if ent.type == "pipe-to-ground" then
                local paired = false
                for _, c in pairs(ent.fluidbox.get_pipe_connections(1)) do
                    if c.connection_type == "underground" and c.target then paired = true end
                end
                if not paired then bad[#bad + 1] = id end
            end
        end
        table.sort(bad)
        return #bad > 0 and "defect" or "ok", "unpaired: " .. serpent.line(bad)
    end
end

describe("twins", function()
    for index, twin in ipairs(TWINS) do
        it(twin.id, function()
            if RRC_OFFLINE then return end
            if twin.check == "prototype" then
                local verdict, why = prototype_verdict(twin)
                assert(verdict ~= nil, twin.id .. ": " .. tostring(why))
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. why .. ")")
                return
            end
            assert((twin.stage or "validate") == "validate", twin.id .. ": check " .. twin.check .. " stage " .. tostring(twin.stage) .. " has no engine build yet (integrator)")
            local force = game.forces.player
            local stack = Lab.research_stack(force)
            local surface = Lab.surface()
            local origin = {index * SPACING, 0}
            Lab.prepare(surface, {{origin[1] - 16, origin[2] - 16}, {origin[1] + twin.grid.w + 16, origin[2] + twin.grid.h + 16}})
            local bp = Twin.to_bp(twin)
            local imported, code = Lab.import_ok(bp)
            assert(imported, twin.id .. ": engine refused the blueprint string (import_stack " .. tostring(code) .. ")")
            local built = Lab.build(surface, force, bp, origin)
            local by_id = map_entities(surface, twin, built)
            local powered_ok = Lab.power(surface, force, built)
            if twin.check == "placeable" then
                local verdict, why = static_verdict(twin, surface, built, by_id, powered_ok)
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. why .. ")")
                return
            end
            assert(#built.refused == 0, twin.id .. ": twin does not place, refused " .. serpent.line(built.refused))
            local feeds, sinks = {}, {}
            for _, f in ipairs(twin.feeds or {}) do
                local ent = Lab.at(surface, built, f.tile[1], f.tile[2])
                local fluid = f.fluid or (f.item and f.item:match("^fluid/(.+)$"))
                assert(Lab.feed_shape_ok(ent, fluid), twin.id .. ": FEED_PORT_SHAPE at " .. key(f.tile[1], f.tile[2]) .. " (" .. tostring(ent and ent.type) .. ")")
                local per_tick
                if not fluid then
                    --Twin default: half the lane max, so the belt has gaps a wrong side-load can enter (docs/twins.md).
                    per_tick = f.rate and (f.rate / 60 / 2) or Lab.lane_max_per_tick(ent, stack) / 2
                end
                feeds[#feeds + 1] = {entity = ent, item = (not fluid) and f.item or nil, fluid = fluid, per_tick = per_tick}
            end
            for _, s in ipairs(twin.sinks or {}) do
                sinks[#sinks + 1] = {entity = Lab.at(surface, built, s.tile[1], s.tile[2]), got = {}, items = s.items or {}, rate = s.rate}
            end
            local speed = slowest_belt_speed(twin)
            local warm = math.ceil((twin.grid.w + twin.grid.h) / (speed or 0.03125)) + 600
            local foreign, carried = {}, {}
            local t0 = game.tick
            game.speed = 64
            on_tick(function()
                local t = game.tick - t0
                Lab.feed_tick(feeds, stack)
                Lab.sink_tick(sinks, t >= warm)
                if t >= warm and t % 60 == 0 then
                    for _, e in ipairs(twin.entities or {}) do
                        if e.flows then
                            local allowed = {}
                            for _, f in ipairs(e.flows) do allowed[f:gsub("^fluid/", "")] = true end
                            for name, count in pairs(Lab.carried(by_id[e.id])) do
                                if not allowed[name] then foreign[e.id .. ":" .. name] = true end
                                carried[e.id] = (carried[e.id] or 0) + count
                            end
                        end
                    end
                end
                if t < warm + WINDOW then return end
                game.speed = 1
                local verdict, why
                if STATIC[twin.check] then
                    verdict, why = static_verdict(twin, surface, built, by_id, powered_ok)
                else
                    local defects = sorted_keys(foreign)
                    for _, s in ipairs(sinks) do
                        local allowed = {}
                        for _, n in ipairs(s.items) do allowed[n:gsub("^fluid/", "")] = true end
                        for name in pairs(s.got) do if not allowed[name] then defects[#defects + 1] = "sink got " .. name end end
                        for name in pairs(allowed) do if not s.got[name] then defects[#defects + 1] = "sink starved of " .. name end end
                        if s.rate then
                            local per_s = 0
                            for name in pairs(allowed) do per_s = per_s + (s.got[name] or 0) end
                            per_s = per_s / (WINDOW / 60)
                            if per_s < 0.95 * s.rate then defects[#defects + 1] = string.format("sink rate %.2f < 0.95 x %.2f", per_s, s.rate) end
                        end
                    end
                    if twin.check == "rate" then
                        local has_rate = false
                        for _, s in ipairs(sinks) do if s.rate then has_rate = true end end
                        assert(has_rate, twin.id .. ": check rate needs sinks[].rate")
                    end
                    local idle, sink_ent = {}, {}
                    for _, s in ipairs(sinks) do if s.entity then sink_ent[s.entity.unit_number] = true end end
                    for _, e in ipairs(twin.entities or {}) do
                        local ent = by_id[e.id]
                        if e.flows and ent and not sink_ent[ent.unit_number] and not carried[e.id] then idle[#idle + 1] = e.id end
                    end
                    table.sort(idle)
                    if #defects > 0 then verdict, why = "defect", table.concat(defects, "; ")
                    elseif #idle > 0 then verdict, why = "waste", "carried nothing: " .. table.concat(idle, " ")
                    else verdict, why = "ok", "every flow pure, every sink fed" end
                end
                assert(verdict ~= nil, twin.id .. ": " .. tostring(why))
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. tostring(why) .. ")")
                return false
            end)
        end)
    end
end)

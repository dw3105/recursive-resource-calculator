--Round 48 D4, engine half of every twin (docs/twins.md): build the twin's published blueprint for real, run it, and
--derive the engine's verdict (ok | defect | waste) from what the game does. The offline half is tests/test_twins.lua.
--tests/twins/index.lua is written by tools/game_stage.sh (the engine cannot list a directory); offline it is absent
--and this file registers nothing.
local Lab = require "tests.game.lib.lab"
local Twin = require "tests.twins.lib.twin"
local Catalog = require "logic.catalog"
local ok_profile, PROFILE_MAP = pcall(require, "tests.game.profile_map")
local PROFILE = ok_profile and PROFILE_MAP.profile or "vanilla"
local TWINS_ENABLED = not ok_profile
if ok_profile then
    for _, name in ipairs((PROFILE_MAP.tests or {})[PROFILE] or {}) do
        if name == "tests.game.test_twins" then TWINS_ENABLED = true end
    end
end
local ok_index, INDEX = pcall(require, "tests.twins.index")
local TWINS = {}
if ok_index and type(INDEX) == "table" then
    for _, name in ipairs(INDEX) do TWINS[#TWINS + 1] = require(name) end
end

local WINDOW = 1200

--Declared flows of a twin entity: the frozen `flows` list, or the validator-native flow_id / flow_ids some twins
--carry (lane 279); "item/" is dropped, "fluid/" kept for the fluid check.
local TRANSPORT = {belt = true, ["transport-belt"] = true, ["underground-belt"] = true, underground = true, splitter = true,
    pipe = true, ["pipe-to-ground"] = true}
local function flows_of(e)
    --Only transport carries a flow the engine can sample; a hand or machine with flow_ids is not "idle".
    if not (TRANSPORT[e.kind] or TRANSPORT[e.name] or (e.name or ""):find("belt") or (e.name or ""):find("splitter") or (e.name or ""):find("pipe")) then return nil end
    local list = e.flows or e.flow_ids or (e.flow_id and {e.flow_id}) or nil
    if not list then return nil end
    local out = {}
    for i, f in ipairs(list) do out[i] = (f:gsub("^item/", "")) end
    return out
end
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

--Engine half of a preflight twin (check "prototype"): project the twin's REAL subject from the running game with
--Catalog.build, put that projection into the twin's preflight input in place of the hand-written entry, and ask
--Preflight.check again. The code firing on the live projection is the engine's "defect"; a twin whose catalog
--invented a fact (an iron-gear-wheel that spoils) meets the live prototype here and fails.
local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep_copy(x) end
    return out
end
local function prototype_verdict(twin)
    local s = twin.subject or {}
    local store = ({recipe = prototypes.recipe, entity = prototypes.entity, item = prototypes.item, module = prototypes.item,
        quality = prototypes.quality})[s.kind]
    if not store then return nil, "subject.kind must be recipe|entity|item|module|quality" end
    if store[s.name] == nil then return "defect", "subject " .. s.kind .. " " .. tostring(s.name) .. " does not exist in this game" end
    --Every prototype the twin's catalog names that exists in this game is replaced by its live projection, not only
    --the subject: a fact invented on any real entry (burner = true on assembling-machine-2) must meet the engine.
    local cat = (twin.preflight or {}).catalog or {}
    local function real(names, store2) local out = {}; for n in pairs(names or {}) do if store2[n] then out[#out + 1] = n end end; return out end
    local options = {entities = real(cat.entity, prototypes.entity), recipe_names = real(cat.recipe, prototypes.recipe),
        item_names = real(cat.item, prototypes.item), module_names = real(cat.module, prototypes.item),
        quality_names = real(cat.quality, prototypes.quality)}
    local extra = ({entity = "entities", recipe = "recipe_names", item = "item_names", module = "module_names", quality = "quality_names"})[s.kind]
    table.insert(options[extra], s.name)
    for _, column in ipairs(((twin.preflight or {}).solver_result or {}).columns or {}) do
        if column.recipe_name and prototypes.recipe[column.recipe_name] then table.insert(options.recipe_names, column.recipe_name) end
    end
    local live = Catalog.build(1, options)
    local probe = deep_copy(twin)
    probe.preflight = deep_copy(twin.preflight)
    probe.preflight.catalog = probe.preflight.catalog or {}
    for _, section in ipairs({"entity", "recipe", "item", "fluid", "quality", "module"}) do
        for name, entry in pairs(live[section] or {}) do
            probe.preflight.catalog[section] = probe.preflight.catalog[section] or {}
            probe.preflight.catalog[section][name] = entry
        end
    end
    --Preflight reads a column's own recipe copy, not the catalog: give it the live recipe too.
    for _, column in ipairs((probe.preflight.solver_result or {}).columns or {}) do
        if column.recipe_name and live.recipe and live.recipe[column.recipe_name] then column.recipe = deep_copy(live.recipe[column.recipe_name]) end
    end
    local codes = Twin.verdict(probe)
    local fired = false
    for _, c in ipairs(codes) do if c == twin.rule then fired = true end end
    return fired and "defect" or "ok", "live " .. s.kind .. " " .. s.name .. " -> " .. (#codes > 0 and table.concat(codes, " ") or "no code")
end

--Engine half of an artifact twin: publish the artifact's own entities, build them for real, read them back, and
--compare with the plan (machine name, recipe, quality, count, modules) and with what the artifact asked for
--(direction the engine kept). Any difference is the engine's "defect".
local BlueprintString = require "logic.bp.blueprint_string"
local function artifact_verdict(twin, index)
    local input = twin.artifact or {}
    local artifact, plan = input.artifact, input.plan
    if type(artifact) ~= "table" or type(plan) ~= "table" or type(artifact.entities) ~= "table" or #artifact.entities == 0 then
        return "defect", "artifact or plan missing"
    end
    local entities = {}
    for i, e in ipairs(artifact.entities) do
        local copy = deep_copy(e)
        copy.entity_number = i
        copy.position = copy.position or {x = 3.5 + (i - 1) * 6, y = 3.5}
        copy.type = nil
        entities[i] = copy
    end
    local ok, bp = pcall(BlueprintString.build, {entities = entities, wires = artifact.wires}, "artifact " .. twin.id)
    if not ok then return "defect", "blueprint string refused by our builder: " .. tostring(bp) end
    local imported = Lab.import_ok(bp)
    if not imported then return "defect", "engine refused the artifact string" end
    local surface, force = Lab.surface(), Lab.twin_force()
    local origin = {index * SPACING, 1024}
    Lab.prepare(surface, {{origin[1] - 8, origin[2] - 8}, {origin[1] + 8 + 6 * #entities, origin[2] + 16}})
    local built = Lab.build(surface, force, bp, origin)
    local diffs = {}
    if #built.refused > 0 then diffs[#diffs + 1] = "refused " .. serpent.line(built.refused) end
    local by_machine = {}
    for i, e in ipairs(artifact.entities) do
        local ent = built.entities[i]
        if ent then
            if (e.direction or 0) ~= ent.direction then diffs[#diffs + 1] = e.name .. " direction " .. tostring(e.direction) .. " -> " .. ent.direction end
            local r = ent.type == "assembling-machine" and ent.get_recipe() or nil
            local key = ent.name .. "|" .. (r and r.name or "-") .. "|" .. ent.quality.name
            by_machine[key] = (by_machine[key] or 0) + 1
        end
    end
    local function contents(inv)
        local out = {}
        for _, it in ipairs(inv and inv.get_contents() or {}) do out[it.name .. "@" .. (it.quality or "normal")] = (out[it.name .. "@" .. (it.quality or "normal")] or 0) + it.count end
        return out
    end
    local function wanted(list)
        local out = {}
        for _, m in ipairs(list or {}) do local k = m.name .. "@" .. (m.quality or "normal"); out[k] = (out[k] or 0) + (m.count or 1) end
        return out
    end
    local function same(a, b)
        for k, v in pairs(a) do if b[k] ~= v then return false end end
        for k, v in pairs(b) do if a[k] ~= v then return false end end
        return true
    end
    for _, step in ipairs(plan.steps or {}) do
        for _, ent in pairs(built.entities) do
            if ent.valid and ent.name == step.machine and not same(contents(ent.get_module_inventory()), wanted(step.modules)) then
                diffs[#diffs + 1] = ent.name .. " modules " .. serpent.line(contents(ent.get_module_inventory())) .. " planned " .. serpent.line(wanted(step.modules))
            end
            if ent.valid and ent.type == "beacon" then
                local groups = step.beacon_groups or {}
                if #groups == 0 then diffs[#diffs + 1] = "beacon not planned"
                else
                    local g = groups[1]
                    if (g.quality or "normal") ~= ent.quality.name then diffs[#diffs + 1] = "beacon quality " .. ent.quality.name .. " planned " .. tostring(g.quality) end
                    if not same(contents(ent.get_module_inventory()), wanted(g.modules)) then diffs[#diffs + 1] = "beacon modules differ from plan" end
                end
            end
        end
        local key = tostring(step.machine) .. "|" .. tostring(step.recipe or "-") .. "|" .. tostring(step.machine_quality or "normal")
        local got = by_machine[key] or 0
        if got ~= (step.machine_count or 0) then diffs[#diffs + 1] = key .. " built " .. got .. " planned " .. tostring(step.machine_count) end
    end
    return #diffs > 0 and "defect" or "ok", #diffs > 0 and table.concat(diffs, "; ") or "engine read back what the plan asked for"
end

local STATIC = {placeable = true, network = true, powered = true, pickup_drop = true, underground_pair = true, beacon_effect = true}

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
        local CONSUMER = {["assembling-machine"] = true, furnace = true, inserter = true, beacon = true, roboport = true, lab = true, ["mining-drill"] = true}
        for id, ent in pairs(by_id) do
          if CONSUMER[ent.type] then
            local ok, connected = pcall(ent.is_connected_to_electric_network)
            if ok and connected == false then bad[#bad + 1] = id end
          end
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
    if check == "beacon_effect" then
        --Beacons the engine applies to each machine vs the plan's count_per_machine for its step: fewer = defect,
        --more, or a beacon that reaches no machine = waste.
        local steps = {}
        for _, step in ipairs(((twin.validator or {}).plan or {}).steps or {}) do steps[step.step_id] = step end
        local short, extra, idle = {}, {}, {}
        for _, e in ipairs(twin.entities or {}) do
            local ent = by_id[e.id]
            if ent and (ent.type == "assembling-machine" or ent.type == "furnace") and e.step_id and steps[e.step_id] then
                local want = 0
                for _, g in ipairs(steps[e.step_id].beacon_groups or {}) do want = want + (g.count_per_machine or g.count or 0) end
                local got = #ent.get_beacons()
                if got < want then short[#short + 1] = e.id .. " " .. got .. "<" .. want end
                if got > want then extra[#extra + 1] = e.id .. " " .. got .. ">" .. want end
            end
            if ent and ent.type == "beacon" and #ent.get_beacon_effect_receivers() == 0 then idle[#idle + 1] = e.id end
        end
        --A machine carrying quality modules under a beacon with speed modules: speed lowers quality (2.0).
        local mixed = {}
        for _, e in ipairs(twin.entities or {}) do
            local ent = by_id[e.id]
            if ent and (ent.type == "assembling-machine" or ent.type == "furnace") then
                local inv, has_quality = ent.get_module_inventory(), false
                for _, it in ipairs(inv and inv.get_contents() or {}) do if it.name:find("quality%-module") then has_quality = true end end
                if has_quality then
                    for _, b in ipairs(ent.get_beacons()) do
                        for _, it in ipairs(b.get_module_inventory().get_contents()) do
                            if it.name:find("speed%-module") then mixed[#mixed + 1] = e.id end
                        end
                    end
                end
            end
        end
        if #mixed > 0 then return "defect", "speed beacon on quality machine: " .. table.concat(mixed, " ") end
        if #short > 0 then return "defect", "machines short of beacons: " .. table.concat(short, " ") end
        if #extra > 0 or #idle > 0 then return "waste", "surplus beacons: " .. table.concat(extra, " ") .. " idle: " .. table.concat(idle, " ") end
        return "ok", "every machine gets its planned beacons"
    end
    if check == "underground_pair" then
        local bad = {}
        for id, ent in pairs(by_id) do
            if ent.type == "underground-belt" then
                --2.0: neighbours; 2.1 renamed it underground_belt_neighbour (docs/api/2.1.19.members.json).
                local ok, partner = pcall(function() return ent.underground_belt_neighbour end)
                if not (ok and partner) then ok, partner = pcall(function() return ent.neighbours end) end
                local want
                for _, e in ipairs(twin.entities or {}) do if e.id == id then want = e.ug_pair_id end end
                if not (ok and partner) then bad[#bad + 1] = id
                elseif want and by_id[want] and partner.unit_number ~= by_id[want].unit_number then bad[#bad + 1] = id .. "(paired with another)" end
            end
            if ent.type == "pipe-to-ground" then
                local paired = false
                local ok, conns = pcall(function() return ent.fluidbox.get_pipe_connections(1) end)
                for _, c in pairs(ok and conns or {}) do
                    if c.connection_type == "underground" and c.target then paired = true end
                end
                if not ok then
                    --2.1 has no get_pipe_connections: a partner pipe-to-ground among the fluid box neighbours, more
                    --than one tile away, is the underground link.
                    local okn, nb = pcall(function() return ent.fluidbox_neighbours end)
                    local function scan(v)
                        if type(v) == "table" then for _, x in pairs(v) do scan(x) end
                        elseif v and v.valid and v.type == "pipe-to-ground" and v.unit_number ~= ent.unit_number then
                            local dx, dy = v.position.x - ent.position.x, v.position.y - ent.position.y
                            if dx * dx + dy * dy > 1.5 then paired = true end
                        end
                    end
                    if okn then scan(nb) end
                end
                if not paired then bad[#bad + 1] = id end
            end
        end
        table.sort(bad)
        return #bad > 0 and "defect" or "ok", "unpaired: " .. serpent.line(bad)
    end
end

describe("twins", function()
    if not TWINS_ENABLED then
        it.skip("skipped: twins are vanilla-only", function() end)
    else
    --Offline the static index does not exist (tools/game_stage.sh writes it): check the twins are there to stage.
    if not ok_index then
        it("twin files exist to stage", function()
            local pipe = io.popen("find tests/twins -name '*.lua' -not -path '*/lib/*' -not -name required.lua | wc -l")
            local n = tonumber(pipe:read("*l")); pipe:close()
            assert.is_true(n and n > 0, "twin files under tests/twins")
        end)
    end
    for index, twin in ipairs(TWINS) do
        it(twin.id, function()
            if RRC_OFFLINE then return end
            if twin.check == "prototype" then
                local verdict, why = prototype_verdict(twin)
                assert(verdict ~= nil, twin.id .. ": " .. tostring(why))
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. why .. ")")
                return
            end
            if twin.check == "artifact" then
                local verdict, why = artifact_verdict(twin, index)
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. why .. ")")
                return
            end
            assert((twin.stage or "validate") == "validate", twin.id .. ": check " .. twin.check .. " stage " .. tostring(twin.stage) .. " has no engine build yet (integrator)")
            local force = Lab.twin_force()
            local stack = 1
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
                    per_tick = f.rate and (f.rate / 60 / 2) or Lab.lane_max_per_tick(ent, f.stack or 1) / 2
                end
                --Twins model flows made inside a blueprint: unstacked (stack 1) unless the twin says otherwise.
                feeds[#feeds + 1] = {entity = ent, item = (not fluid) and f.item or nil, fluid = fluid, per_tick = per_tick, stack = f.stack or 1}
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
                        local declared = flows_of(e)
                        if declared then
                            local allowed = {}
                            for _, f in ipairs(declared) do allowed[(f:gsub("^fluid/", ""))] = true end
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
                    --A machine must hold every fluid its recipe takes (fluid_system: a gap in the pipe starves it).
                    for _, e in ipairs(twin.entities or {}) do
                        local ent = by_id[e.id]
                        if ent and (ent.type == "assembling-machine" or ent.type == "furnace") and ent.get_recipe() then
                            local held = Lab.carried(ent)
                            for _, ing in ipairs(ent.get_recipe().ingredients) do
                                if ing.type == "fluid" and not held[ing.name] then defects[#defects + 1] = e.id .. " starved of " .. ing.name end
                            end
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
                        if flows_of(e) and ent and not sink_ent[ent.unit_number] and not carried[e.id] then idle[#idle + 1] = e.id end
                    end
                    table.sort(idle)
                    local rates = {}
                    for _, sk in ipairs(sinks) do
                        local total = 0
                        for _, c in pairs(sk.got) do total = total + c end
                        rates[#rates + 1] = string.format("%.2f/s%s", total / (WINDOW / 60), sk.rate and ("(plan " .. sk.rate .. ")") or "")
                    end
                    local measured = #rates > 0 and (" | sinks " .. table.concat(rates, " ")) or ""
                    if #defects > 0 then verdict, why = "defect", table.concat(defects, "; ") .. measured
                    elseif #idle > 0 then verdict, why = "waste", "carried nothing: " .. table.concat(idle, " ")
                    else verdict, why = "ok", "every flow pure, every sink fed" .. measured end
                end
                assert(verdict ~= nil, twin.id .. ": " .. tostring(why))
                assert.are_equal(twin.truth, verdict, twin.id .. " engine verdict (" .. tostring(why) .. ")")
                return false
            end)
        end)
    end
    end
end)

--Lab: builds a blueprint string for real on a lab surface, powers it, feeds its ports, drains its sinks and watches
--what the engine does (round 48 I2, docs/twins.md). Headless only: offline (tests/game/offline.lua) has no surface.
--
--Placement: our own blueprint string is decoded (helpers.decode_string + json_to_table, the same bytes a player
--pastes) and each entity is created with create_entity at an integer origin, so twin tile (x, y) is world
--(origin.x + x, origin.y + y) exactly. can_place_entity runs first for every entity; its refusals are the engine's
--placement verdict. Wires come from the string, never from auto-connect.
--
--Feed (G10d, proven 2.0.77 + 2.1.20 2026-09-29): insert_at_back on both lines of the port belt every tick, stack =
--1 + force.belt_stack_size_bonus after every belt-stack tech is researched; a straight belt then runs at exact max.
local Lab = {}

Lab.SURFACE = "rrc-lab"
Lab.EEI = "electric-energy-interface"

function Lab.surface()
    local s = game.surfaces[Lab.SURFACE]
    if s then return s end
    s = game.create_surface(Lab.SURFACE, {width = 4096, height = 4096, peaceful_mode = true, no_enemies_mode = true})
    s.generate_with_lab_tiles = true
    s.always_day = true
    return s
end

function Lab.prepare(surface, area)
    local l, t, r, b = area[1][1], area[1][2], area[2][1], area[2][2]
    surface.request_to_generate_chunks({(l + r) / 2, (t + b) / 2}, math.ceil(math.max(r - l, b - t) / 64) + 1)
    surface.force_generate_chunk_requests()
    for _, e in pairs(surface.find_entities({{l, t}, {r, b}})) do if e.valid and e.type ~= "character" then e.destroy() end end
end

--Unlock every recipe (a fresh lab force has none researched: machines sit at recipe_not_researched, engine
--2026-09-29), then research every tech whose effects raise belt stacking (mods included, G10). Returns the max
--belt stack. enable_all_recipes grants no productivity or speed bonus; research_all_technologies would.
function Lab.research_stack(force)
    force.enable_all_recipes()
    for _, tech in pairs(force.technologies) do
        for _, e in pairs(tech.prototype.effects or {}) do
            if e.type == "belt-stack-size-bonus" then tech.researched = true end
        end
    end
    return 1 + force.belt_stack_size_bonus
end

function Lab.decode(bp_string)
    local json = helpers.decode_string(bp_string:sub(2))
    assert(json, "blueprint string does not decode")
    local t = helpers.json_to_table(json)
    return assert(t.blueprint, "not a single blueprint")
end

--Engine acceptance of the string itself (a player's paste).
function Lab.import_ok(bp_string)
    local inv = game.create_inventory(1)
    local ok, result = pcall(function() return inv[1].import_stack(bp_string) end)
    local setup = ok and inv[1].valid_for_read and inv[1].is_blueprint and inv[1].is_blueprint_setup()
    inv.destroy()
    return ok and result == 0 and setup == true, result
end

local function module_list(items)
    local out = {}
    for _, entry in ipairs(items or {}) do
        local id = entry.id or {}
        local count = entry.items and entry.items.in_inventory and #entry.items.in_inventory or 0
        if id.name and count > 0 then out[#out + 1] = {name = id.name, quality = id.quality or "normal", count = count} end
    end
    return out
end

--Build a blueprint at integer origin {ox, oy}. Returns {entities = {[entity_number] = LuaEntity}, by_tile, refused,
--placed, bp}. by_tile["x,y"] (grid tile, origin removed) -> every entity covering that tile's top-left point.
function Lab.build(surface, force, bp_string, origin)
    local bp = Lab.decode(bp_string)
    local built = {entities = {}, refused = {}, placed = 0, bp = bp, origin = origin, by_tile = {}}
    for _, e in ipairs(bp.entities or {}) do
        local pos = {x = origin[1] + e.position.x, y = origin[2] + e.position.y}
        local spec = {name = e.name, position = pos, direction = e.direction or 0, force = force,
            quality = e.quality or "normal", type = e.type, input_priority = e.input_priority,
            output_priority = e.output_priority, filter = e.filter, raise_built = false}
        local can = surface.can_place_entity{name = e.name, position = pos, direction = e.direction or 0, force = force,
            build_check_type = defines.build_check_type.manual}
        if not can then
            built.refused[#built.refused + 1] = e.entity_number
        else
            local ok, ent = pcall(surface.create_entity, spec)
            if ok and ent then
                built.entities[e.entity_number] = ent
                built.placed = built.placed + 1
                if e.recipe and ent.type == "assembling-machine" then pcall(ent.set_recipe, e.recipe, e.recipe_quality or "normal") end
                local mods = module_list(e.items)
                if #mods > 0 then
                    local inv = ent.get_module_inventory()
                    for _, m in ipairs(mods) do if inv then inv.insert(m) end end
                end
            else
                built.refused[#built.refused + 1] = e.entity_number
            end
        end
    end
    --Script-built poles may auto-connect; the string's wires are the only truth.
    for _, ent in pairs(built.entities) do
        if ent.type == "electric-pole" then
            local c = ent.get_wire_connector(defines.wire_connector_id.pole_copper, false)
            if c then c.disconnect_all(defines.wire_origin.player) end
        end
    end
    for _, w in ipairs(bp.wires or {}) do
        local a, b = built.entities[w[1]], built.entities[w[3]]
        if a and b then
            local ca, cb = a.get_wire_connector(w[2], true), b.get_wire_connector(w[4], true)
            if ca and cb then ca.connect_to(cb, false, defines.wire_origin.player) end
        end
    end
    return built
end

--Entity whose box covers grid tile (x, y).
function Lab.at(surface, built, x, y)
    local o = built.origin
    local found = surface.find_entities_filtered{area = {{o[1] + x + 0.1, o[2] + y + 0.1}, {o[1] + x + 0.9, o[2] + y + 0.9}}}
    for _, e in pairs(found) do if e.type ~= "character" and e.type ~= "entity-ghost" then return e end end
    return nil
end

--Power: an electric-energy-interface and a substation wired to the twin pole nearest the grid's left edge.
--Returns false when the build has no pole (nothing to power through) or no pole is in reach.
function Lab.power(surface, force, built)
    local best, best_d
    for _, ent in pairs(built.entities) do
        if ent.valid and ent.type == "electric-pole" then
            local d = ent.position.x - built.origin[1]
            if best == nil or d < best_d then best, best_d = ent, d end
        end
    end
    if not best then return false end
    local x = built.origin[1] - 4
    local sub = surface.create_entity{name = "substation", position = {x, best.position.y}, force = force}
    local eei = surface.create_entity{name = Lab.EEI, position = {x - 3, best.position.y}, force = force}
    if not (sub and eei) then return false end
    eei.electric_buffer_size = 1e15
    eei.power_production = 1e13
    eei.power_usage = 0
    local c = sub.get_wire_connector(defines.wire_connector_id.pole_copper, true)
    c.disconnect_all(defines.wire_origin.player)
    return c.connect_to(best.get_wire_connector(defines.wire_connector_id.pole_copper, true), false, defines.wire_origin.player)
end

--Feeds: list of {entity, item | fluid, per_tick?}. Items: both lines at max stack. per_tick nil = every tick as much
--as fits (a sheet port, G10: full belt). per_tick = items per tick per line: a partly loaded belt, which is what a
--twin needs, because a FULL belt refuses every side-load and so can never show bleed (engine, 2026-09-29).
function Lab.feed_tick(feeds, stack)
    for _, f in ipairs(feeds) do
        local e = f.entity
        if e and e.valid then
            if f.fluid then
                pcall(e.insert_fluid, {name = f.fluid, amount = 1000})
            else
                for lane = 1, 2 do
                    if f.per_tick then
                        f.budget = f.budget or {0, 0}
                        f.budget[lane] = math.min(f.budget[lane] + f.per_tick, 2 * stack)
                        if f.budget[lane] >= stack and e.get_transport_line(lane).insert_at_back({name = f.item, count = stack}, stack) then
                            f.budget[lane] = f.budget[lane] - stack
                        end
                    else
                        e.get_transport_line(lane).insert_at_back({name = f.item, count = stack}, stack)
                    end
                end
            end
        end
    end
end

--Lane max in items per tick for a belt entity at this stack (belt_speed tiles/tick x 4 slots per tile... per lane).
function Lab.lane_max_per_tick(entity, stack)
    return entity.prototype.belt_speed * 4 * stack
end

function Lab.feed_shape_ok(entity, fluid)
    if not entity then return false end
    if fluid then return entity.type == "pipe" or entity.type == "pipe-to-ground" or entity.type == "storage-tank" end
    return entity.type == "transport-belt"
end

--Sinks: drain both lines (or the fluid) every tick, counting what arrived by name.
function Lab.sink_tick(sinks, counting)
    for _, s in ipairs(sinks) do
        local e = s.entity
        if e and e.valid then
            if e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter" then
                for lane = 1, e.get_max_transport_line_index() do
                    local line = e.get_transport_line(lane)
                    if counting then
                        for _, c in pairs(line.get_contents()) do s.got[c.name] = (s.got[c.name] or 0) + c.count end
                    end
                    line.clear()
                end
            elseif e.fluidbox and #e.fluidbox > 0 then
                for i = 1, #e.fluidbox do
                    local f = e.fluidbox[i]
                    if f then
                        if counting then s.got[f.name] = (s.got[f.name] or 0) + f.amount end
                        e.fluidbox[i] = nil
                    end
                end
            end
        end
    end
end

--Names carried by a transport entity right now (every line), or its fluids.
function Lab.carried(entity)
    local names = {}
    if not (entity and entity.valid) then return names end
    local ok, n = pcall(entity.get_max_transport_line_index)
    if ok and n then
        for lane = 1, n do
            for _, c in pairs(entity.get_transport_line(lane).get_contents()) do names[c.name] = (names[c.name] or 0) + c.count end
        end
    elseif entity.fluidbox then
        for i = 1, #entity.fluidbox do
            local f = entity.fluidbox[i]
            if f then names[f.name] = (names[f.name] or 0) + f.amount end
        end
    end
    return names
end

return Lab

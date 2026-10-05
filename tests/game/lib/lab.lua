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

--A fresh force for twins: every recipe unlocked, no research at all (belt-stack techs also raise inserter hand
--size in 2.0, which let a plain inserter beat its planned 0.83/s: V121, 2026-09-29). Sheet sims keep "player".
function Lab.twin_force()
    local force = game.forces["rrc-twin"] or game.create_force("rrc-twin")
    force.enable_all_recipes()
    return force
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
            output_priority = e.output_priority, filter = e.filter, raise_built = false,
            recipe = e.recipe and e.recipe or nil}
        --Placement verdict from the engine's own boxes and masks: create (script), then any overlapping entity whose
        --collision layers intersect refuses it. can_place_entity was no oracle here: manual refused every
        --underground, script skipped collisions, blueprint_ghost refused nearly everything (2026-09-29).
        do
            local ok, ent = pcall(surface.create_entity, spec)
            if ok and ent then
                built.entities[e.entity_number] = ent
                built.placed = built.placed + 1
                -- 2026-09-30: crafting machines created without a recipe ignore direction; set it at creation.
                if e.mirror then pcall(function() ent.mirroring = true end) end
                if e.recipe and ent.type == "assembling-machine" then pcall(ent.set_recipe, e.recipe, e.recipe_quality or "normal") end
                local mods = module_list(e.items)
                if #mods > 0 then
                    local inv = ent.get_module_inventory()
                    for _, m in ipairs(mods) do if inv then inv.insert(m) end end
                end
            else
                built.refused[#built.refused + 1] = e.entity_number
            end
            if ok and ent and ent.valid and Lab.collides(surface, ent) then
                built.entities[e.entity_number] = nil
                built.placed = built.placed - 1
                built.refused[#built.refused + 1] = e.entity_number
                ent.destroy()
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
            if ca and cb then ca.connect_to(cb, true, defines.wire_origin.player) end  --reach_check: an over-long wire stays unconnected
        end
    end
    return built
end

--True when another entity's box overlaps this one (strictly) and their collision layers intersect.
function Lab.collides(surface, ent)
    local box = ent.bounding_box
    local eps = 0.01
    local area = {{box.left_top.x + eps, box.left_top.y + eps}, {box.right_bottom.x - eps, box.right_bottom.y - eps}}
    local mine = ent.prototype.collision_mask.layers
    for _, other in pairs(surface.find_entities_filtered{area = area}) do
        if other.valid and other ~= ent and other.unit_number ~= ent.unit_number and other.type ~= "character" then
            for layer in pairs(other.prototype.collision_mask.layers) do
                if mine[layer] then return true end
            end
        end
    end
    return false
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
    --A link pole just outside the grid, fed by a substation + electric-energy-interface further left. The lab must
    --never power the twin by itself: a substation beside the grid did, and hid an uncovered machine (V61, 2026-09-29).
    local y = best.position.y
    --big-electric-pole: 2x2 at tiles -4..-3, supply reaches -5..-1 only (never a grid tile), wire reach 30, so it
    --meets a sheet's edge-most substation too (blue / gray-magenta had none within a small pole's 7.5).
    local link = surface.create_entity{name = "big-electric-pole", position = {built.origin[1] - 3, y}, force = force}
    local sub = surface.create_entity{name = "substation", position = {built.origin[1] - 12, y}, force = force}
    local eei = surface.create_entity{name = Lab.EEI, position = {built.origin[1] - 16, y}, force = force}
    if not (link and sub and eei) then return false end
    eei.electric_buffer_size = 1e15
    eei.power_production = 1e13
    eei.power_usage = 0
    local copper = defines.wire_connector_id.pole_copper
    for _, pole in ipairs({link, sub}) do pole.get_wire_connector(copper, true).disconnect_all(defines.wire_origin.player) end
    local a = sub.get_wire_connector(copper, true).connect_to(link.get_wire_connector(copper, true), true, defines.wire_origin.player)
    --No reach check on the lab's own wire (round 54): a small sheet's nearest pole is a medium pole (reach 9) up to
    --12.5 tiles from the link pole, and 15 Turn and Flip sheets read "power failed". The wire carries power only;
    --the link pole's supply area still ends outside the grid.
    local b = link.get_wire_connector(copper, true).connect_to(best.get_wire_connector(copper, true), false, defines.wire_origin.player)
    return a and b
end

--Feeds: list of {entity, item | fluid, per_tick?}. Items: both lines at max stack. per_tick nil = every tick as much
--as fits (a sheet port, G10: full belt). per_tick = items per tick per line: a partly loaded belt, which is what a
--twin needs, because a FULL belt refuses every side-load and so can never show bleed (engine, 2026-09-29).
function Lab.feed_tick(feeds, default_stack)
    for _, f in ipairs(feeds) do
        local e = f.entity
        local stack = f.stack or default_stack
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

--Metered feed: one fractional item/fluid pool per full name, shared by every matching entry port.
function Lab.meter_new(inputs)
    local pool = {}
    for full_name, rate in pairs(inputs or {}) do pool[full_name] = {rate = rate, credit = 0} end
    return pool
end

local function full_name(feed)
    if feed.fluid then return "fluid/" .. feed.fluid end
    if feed.item then return "item/" .. feed.item end
end

function Lab.meter_tick(pool, feeds, stack)
    local names = {}
    for name in pairs(pool) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local meter = pool[name]
        meter.credit = meter.credit + meter.rate / 60
    end
    for _, feed in ipairs(feeds or {}) do
        local name = full_name(feed)
        local meter = name and pool[name]
        local entity = feed.entity
        if meter and entity and entity.valid then
            if feed.fluid then
                if meter.credit > 0 then
                    local ok, inserted = pcall(entity.insert_fluid, {name = feed.fluid, amount = meter.credit})
                    if ok and type(inserted) == "number" and inserted > 0 then
                        meter.credit = math.max(0, meter.credit - inserted)
                    end
                end
            else
                --Batch = one second of rate, 1..stack: whole-stack-only held calcite at 0.0178/s for 67500 ticks and
                --foundries made nothing (red-1s-bulk R=0.000, 2026-10-05); 1-item stacks at 10/s would waste belt slots.
                local batch = math.max(1, math.min(stack, math.ceil(meter.rate)))
                --Lanes take turns batch by batch: lane 1 first always had room at low rates, lane 2 stayed empty and a
                --furnace fed from it never ran (green-1s R=0.96, 2026-10-05).
                local failed = 0
                while meter.credit >= batch and failed < 2 do
                    feed.lane = (feed.lane or 0) % 2 + 1
                    local n = math.min(stack, math.floor(meter.credit))
                    local ok, inserted = pcall(entity.get_transport_line(feed.lane).insert_at_back, {name = feed.item, count = n}, n)
                    if ok and inserted then
                        meter.credit, failed = meter.credit - n, 0
                    else
                        failed = failed + 1
                    end
                end
            end
        end
    end
end

function Lab.meter_backlog(pool, feeds, stack)
    local heads = {}
    for _, feed in ipairs(feeds or {}) do
        if feed.item then
            local name = "item/" .. feed.item
            heads[name] = (heads[name] or 0) + 1
        end
    end
    local names = {}
    local names_in_order = {}
    for name in pairs(heads) do names_in_order[#names_in_order + 1] = name end
    table.sort(names_in_order)
    for _, name in ipairs(names_in_order) do
        local count = heads[name]
        local meter = pool[name]
        if meter and meter.credit > 2 * stack * count then names[#names + 1] = name end
    end
    return names
end

function Lab.judge(per_s, outputs)
    local problems, lines = {}, {}
    local names = {}
    for name in pairs(outputs or {}) do names[#names + 1] = name end
    table.sort(names)
    local ok = true
    for _, name in ipairs(names) do
        local rate, measured = outputs[name], (per_s or {})[name] or 0
        local ratio = rate > 0 and measured / rate or math.huge
        lines[#lines + 1] = string.format("%s %.3f/s of %.3f/s R=%.3f", name, measured, rate, ratio)
        if ratio < 0.98 then
            ok = false
            problems[#problems + 1] = string.format("SHORT %s R=%.3f", name, ratio)
        elseif ratio > 1.1 then
            ok = false
            problems[#problems + 1] = string.format("OVER %s R=%.3f", name, ratio)
        end
    end
    return ok, problems, lines
end

--End of warm-up (2026-10-05): empty every belt that carries only sheet inputs (the input chains). A full-feed warm-up
--primes machines and pipes (metering from empty left red-1s-bulk at R=0.967 after 22 game minutes), but its stacked
--input stock would be eaten by rounded-up machines faster than calc (R=1.05). Inner belts keep their stock: emptying
--them too let plate and gear foundries take shared molten iron to refill them and starved casting-pipe (blue 0.567).
function Lab.clear_input_belts(entities, inputs)
    local cleared = 0
    for _, e in pairs(entities) do
        if e.valid and (e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter") then
            local only_inputs, any = true, false
            for i = 1, e.get_max_transport_line_index() do
                for _, it in pairs(e.get_transport_line(i).get_contents()) do
                    any = true
                    if not inputs["item/" .. it.name] then only_inputs = false end
                end
            end
            if any and only_inputs then
                for i = 1, e.get_max_transport_line_index() do
                    local line = e.get_transport_line(i)
                    cleared = cleared + line.get_item_count()
                    line.clear()
                end
            end
        end
    end
    return cleared
end

--Output made so far, from the machines that make each output: products_finished counts crafts including productivity
--bonus crafts (blue 2026-10-05: plastic 5.35/s game vs 2.143 x 2.5 calc), so items = crafts x base product amount.
--Smooth per craft, unlike a sink count that arrives in hand loads (bulk hands drop 16: +-2.7% in a 600-item window).
function Lab.made(entities, outputs)
    local made = {}
    for _, e in pairs(entities) do
        if e.valid and (e.type == "assembling-machine" or e.type == "furnace") then
            local r = e.get_recipe()
            if r then
                for _, p in ipairs(r.products) do
                    local full = p.type .. "/" .. p.name
                    if outputs[full] then made[full] = (made[full] or 0) + e.products_finished * (p.amount or 0) end
                end
            end
        end
    end
    return made
end

--Items on belts that are neither sheet inputs nor outputs: the inner buffers a full-feed warm-up must fill first. Metered
--feed has no slack to fill them: green-1s foundry filled a 54-tile belt (188 -> 692 belts) on iron the packs needed,
--R 0.80-0.97 for 90000 ticks (2026-10-05).
function Lab.inner_stock(entities, inputs, outputs)
    local stock = 0
    for _, e in pairs(entities) do
        if e.valid and (e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter") then
            for i = 1, e.get_max_transport_line_index() do
                for _, it in pairs(e.get_transport_line(i).get_contents()) do
                    local name = "item/" .. it.name
                    if not inputs[name] and not outputs[name] then stock = stock + it.count end
                end
            end
        end
    end
    return stock
end

--Warm-up ends once inner stock grew under 2% (+5 items) over the last WARM_STEP ticks, or at WARM_CAP.
Lab.WARM_STEP, Lab.WARM_CAP = 3600, 72000
function Lab.warm_ready(previous, stock)
    return previous ~= nil and stock <= previous * 1.02 + 5
end

--Window long enough for 200 units of the slowest output: one craft at 1/s was 1.7% of a 60 s window, wider than the
--1.5% band, so green-1s and am2 never settled (2026-10-05).
Lab.WINDOW_UNITS = 200
function Lab.window_ticks(outputs)
    local slowest = math.huge
    for _, rate in pairs(outputs) do slowest = math.min(slowest, rate) end
    if slowest == math.huge or slowest <= 0 then return 3600 end
    return math.max(3600, 60 * math.ceil(Lab.WINDOW_UNITS / slowest))
end

--Settling (player Q14, 2026-10-05): metered windows run until output stabilizes = the last 3 windows of every output
--are all > 0 and within 1.5% of each other (max - min <= 0.015 x mean). Two windows within 2% fired mid-climb
--(vanilla green 0.867 -> 0.883, judged 0.903). The band widens by SETTLE_UNITS of output per window (window_s seconds
--long): window edges cut crafts, vanilla green 2.1 cycled 1.01/0.99/1.00 at 200 packs a window and never settled
--(2026-10-05). Returns stable, mean made, mean sunk over those 3 windows.
Lab.SETTLE_WINDOWS, Lab.SETTLE_BAND, Lab.SETTLE_UNITS = 3, 0.015, 4
function Lab.settle(history, per, sunk, window_s)
    history[#history + 1] = {per = per, sunk = sunk}
    local n = Lab.SETTLE_WINDOWS
    if #history < n then return false end
    local mean_per, mean_sunk = {}, {}
    for name in pairs(per) do
        local lo, hi, sum, sum_sunk = math.huge, -math.huge, 0, 0
        for i = #history - n + 1, #history do
            local v = history[i].per[name] or 0
            lo, hi, sum = math.min(lo, v), math.max(hi, v), sum + v
            sum_sunk = sum_sunk + (history[i].sunk[name] or 0)
        end
        local mean = sum / n
        local band = Lab.SETTLE_BAND * mean + (window_s and Lab.SETTLE_UNITS / window_s or 0)
        if lo <= 0 or hi - lo > band then return false end
        mean_per[name], mean_sunk[name] = mean, sum_sunk / n
    end
    return true, mean_per, mean_sunk
end

--Lane max in items per tick for a belt entity at this stack (belt_speed tiles/tick x 4 slots per tile... per lane).
function Lab.lane_max_per_tick(entity, stack)
    return entity.prototype.belt_speed * 4 * stack
end

function Lab.feed_shape_ok(entity, fluid)
    if not entity then return false end
    if fluid then return entity.type == "pipe" or entity.type == "pipe-to-ground" or entity.type == "storage-tank" end
    --An underground entrance on the map edge is fed like a belt (round 54).
    return entity.type == "transport-belt" or entity.type == "underground-belt"
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
            else
                --Count what is REMOVED, never what one pipe reports: a pipe reports its own share of its fluid network
                --(round 54: an 8-pipe run read 1.25/s of 9.99/s), Factorio 2.1.20 has no LuaEntity.fluidbox to ask for
                --the whole network, and summing the pipes misses the machines' own boxes (EM plant x4: 13.5/s of
                --15.98/s). remove_fluid returns what it took, whichever way the engine shares a network.
                local names = {}
                for _, name in ipairs(s.items or {}) do names[#names + 1] = name end
                if #names == 0 then
                    local okf, fluids = pcall(e.get_fluid_contents)
                    for name in pairs(okf and fluids or {}) do names[#names + 1] = name end
                end
                for _, name in ipairs(names) do
                    --2.0.77: remove_fluid{name, amount} returns the amount. 2.1.20 (probed 2026-10-01): remove_fluid(fluid
                    --box index, amount) returns the removed fluid {name, amount}.
                    local okr, removed = pcall(e.remove_fluid, {name = name, amount = 1000000})
                    if not okr then
                        okr, removed = pcall(e.remove_fluid, 1, 1000000)
                        if okr and type(removed) == "table" then name, removed = removed.name or name, removed.amount end
                    end
                    if okr and type(removed) == "number" and removed > 0 and counting then
                        s.got[name] = (s.got[name] or 0) + removed
                    end
                end
            end
        end
    end
end

--Names carried by a transport entity right now (every line), or its fluids (get_fluid_contents: name -> amount).
function Lab.carried(entity)
    local names = {}
    if not (entity and entity.valid) then return names end
    local ok, n = pcall(entity.get_max_transport_line_index)
    if ok and n then
        for lane = 1, n do
            for _, c in pairs(entity.get_transport_line(lane).get_contents()) do names[c.name] = (names[c.name] or 0) + c.count end
        end
        return names
    end
    local okf, fluids = pcall(entity.get_fluid_contents)
    if okf and fluids then
        for name, amount in pairs(fluids) do
            if type(amount) == "table" then amount = amount.amount or 0; name = amount.name or name end
            if amount > 0 then names[name] = (names[name] or 0) + amount end
        end
    end
    return names
end

return Lab

--Player run (plan ~/.claude/plans/rrc-player-run-plan-2026-10-05.md, player 2026-10-05): one Case driven end to end
--the way a player does it. GUI handlers set up the sheet (tests/game/lib/player_drive.lua), the generation dialog's
--generate click puts the blueprint in the cursor, build_from_cursor places ghosts, revive + module insert stand in for
--bots, the lab powers it, ports are found from the built factory (tests/game/lib/ports.lua), a full-feed warm-up
--primes machines and pipes, input belts are emptied, then Metered feed pushes exactly calc input rate (tests/game/lib/lab.lua). Pass: every output 0.98 <= R <= 1.1
--against the calculation (Lab.judge), live calc == staged refs, no foreign item at a sink, no refused build.
--Round gate + release only: runs when tools/game_test.sh got RRC_PLAYER_RUN=1 (profile_map.player_run).
--Engine facts (probes P1/P3 2026-10-05, 2.0 + 2.1): the headless player is a character; build_from_cursor out of
--reach or on ungenerated chunks silently places nothing; revive leaves modules in an item-request-proxy insert_plan.
local S = require "tests.game.support"
local Lab = require "tests.game.lib.lab"
local Ports = require "tests.game.lib.ports"
local Drive = require "tests.game.lib.player_drive"
local Calculation = require "logic.calculation_result"
local ok_profile, PROFILE_MAP = pcall(require, "tests.game.profile_map")

local CASES = {
    {case = "player-am2-chain-repaired", profile = "player"},
    {case = "player-blue-science-10s", profile = "player"},
    {case = "player-green-science-1s", profile = "player"},
    {case = "player-inserter-10s", profile = "player"},
    {case = "player-inserter-10s-bulk", profile = "player"},
    {case = "player-inserter-10s-stack1", profile = "player"},
    {case = "player-magenta-science-10s", profile = "player",
     skip = "skipped 2026-10-04 (player): magenta builds too slowly; not tested by Player run"},
    {case = "player-red-green-science-10s", profile = "player"},
    {case = "player-red-science-10s", profile = "player"},
    {case = "player-red-science-10s-bulk", profile = "player"},
    {case = "player-red-science-10s-stack1", profile = "player"},
    {case = "player-red-science-1s", profile = "player"},
    {case = "player-red-science-1s-bulk", profile = "player"},
    {case = "player-red-science-1s-foundry", profile = "player"},
    {case = "vanilla-2.1-red-science-1s", profile = "vanilla", version = "2.1"},
    {case = "vanilla-2.1-green-science-1s", profile = "vanilla", version = "2.1"},
}

--Fixture modules staged by tools/game_stage.sh; required at parse time (headless refuses runtime require).
local REFS, PREPARED, SHEET = {}, {}, {}
for _, c in ipairs(CASES) do
    local module = c.case:gsub("[-%.]", "_")
    local ok_s, sheet = pcall(require, "tests.game.fixtures.sheet_" .. module)
    if ok_s then SHEET[c.case] = sheet end
    local ok_r, refs = pcall(require, "tests.game.fixtures." .. module .. "_refs")
    if ok_r then REFS[c.case] = refs end
    if c.profile == "player" then
        local ok_p, prepared = pcall(require, "tests.game.fixtures." .. module .. "_prepared")
        if ok_p then PREPARED[c.case] = prepared end
    end
end

local function player_profile() return script.active_mods["Moshine"] ~= nil end
local function rel_close(a, b) return math.abs((a or 0) - (b or 0)) <= 1e-6 * math.max(1, math.abs(b or 0)) end

--Modules a revived ghost left in its item-request-proxy go into the slots its insert_plan names (bots stand-in).
--Built poles must be wired as the game wires them (red-1s: one pole group powered, 20 hands no_power, 2.0.77
--2026-10-05). A blueprint with wires: they are laid, its poles mapped onto built poles by one offset that fits them
--all. The delivered blueprint has none: poles connect in wire reach as bot-built poles auto-connect.
--Returns wires laid, wires in the blueprint.
local function lay_wires(bp, surface, area, force)
    local poles = {}
    for _, e in ipairs(bp.entities or {}) do
        if prototypes.entity[e.name] and prototypes.entity[e.name].type == "electric-pole" then poles[#poles + 1] = e end
    end
    local built = surface.find_entities_filtered{area = area, force = force, type = "electric-pole"}
    if #(bp.wires or {}) == 0 then
        --The delivered blueprint carries no wires (2026-10-05): a bot-built pole auto-connects to poles in wire reach.
        local laid = 0
        for i, a in ipairs(built) do
            for j = i + 1, #built do
                local b = built[j]
                local reach = math.min(a.prototype.get_max_wire_distance(a.quality), b.prototype.get_max_wire_distance(b.quality))
                local dx, dy = a.position.x - b.position.x, a.position.y - b.position.y
                if dx * dx + dy * dy <= reach * reach then
                    local ca = a.get_wire_connector(defines.wire_connector_id.pole_copper, true)
                    local cb = b.get_wire_connector(defines.wire_connector_id.pole_copper, true)
                    if ca.is_connected_to(cb) or ca.connect_to(cb, false) then laid = laid + 1 end
                end
            end
        end
        return laid, 0
    end
    if #poles == 0 then return 0, #bp.wires end
    local at = {}
    for _, b in ipairs(built) do at[b.name .. "@" .. b.position.x .. "," .. b.position.y] = b end
    local map
    for _, b in ipairs(built) do
        if b.name == poles[1].name then
            local dx, dy = b.position.x - poles[1].position.x, b.position.y - poles[1].position.y
            local try = {}
            for _, p in ipairs(poles) do
                try[p.entity_number] = at[p.name .. "@" .. (p.position.x + dx) .. "," .. (p.position.y + dy)]
                if not try[p.entity_number] then try = nil; break end
            end
            if try then map = try; break end
        end
    end
    assert(map, "no offset maps the blueprint's poles onto the built poles")
    local laid = 0
    for _, w in ipairs(bp.wires) do
        local a, b = map[w[1]], map[w[3]]
        if a and b then
            local ca, cb = a.get_wire_connector(w[2], true), b.get_wire_connector(w[4], true)
            if ca.is_connected_to(cb) or ca.connect_to(cb, false) then laid = laid + 1 end
        end
    end
    return laid, #bp.wires
end

local function fulfil(proxy)
    local target = proxy.proxy_target
    if target and target.valid then
        for _, entry in ipairs(proxy.insert_plan or {}) do
            local id = entry.id or {}
            for _, slot in ipairs(entry.items and entry.items.in_inventory or {}) do
                local inv = target.get_inventory(slot.inventory)
                if inv then inv[slot.stack + 1].set_stack{name = id.name, quality = id.quality or "normal", count = 1} end
            end
        end
    end
    proxy.destroy()
end

local function plain(ent)
    local recipe
    if ent.type == "assembling-machine" or ent.type == "furnace" then
        local r = ent.get_recipe()
        recipe = r and r.name
    end
    local mirror = false
    pcall(function() mirror = ent.mirroring == true end)
    return {name = ent.name, position = {x = ent.position.x, y = ent.position.y}, direction = ent.direction,
        recipe = recipe, mirror = mirror, belt_to_ground_type = ent.type == "underground-belt" and ent.belt_to_ground_type or nil}
end

--Catalog for Ports.find: a player Case brings the capture's catalog (recipes with fluid-box binding, entity sizes and
--fluid boxes); a vanilla Case (no prepared input, no fluids, no furnaces) gets recipes and sizes from prototypes.
local function prototype_catalog(entities)
    local catalog = {recipe = {}, entity = {}}
    for _, e in ipairs(entities) do
        if e.recipe and not catalog.recipe[e.recipe] then
            local r = prototypes.recipe[e.recipe]
            catalog.recipe[e.recipe] = {ingredients = r.ingredients, products = r.products}
        end
        if not catalog.entity[e.name] then
            local p = prototypes.entity[e.name]
            catalog.entity[e.name] = {tile_w = p.tile_width, tile_h = p.tile_height}
        end
    end
    return catalog
end

local function at_tile(surface, x, y)
    for _, e in pairs(surface.find_entities_filtered{area = {{x + 0.1, y + 0.1}, {x + 0.9, y + 0.9}}}) do
        if e.type ~= "character" and e.type ~= "entity-ghost" then return e end
    end
end

describe("player run", function()
    for index, c in ipairs(CASES) do
        local register = (c.skip or not (ok_profile and PROFILE_MAP.player_run)) and it.skip or it
        register(c.case, function()
            if RRC_OFFLINE then return end
            if (c.profile == "player") ~= player_profile() then return end
            if c.version and c.version ~= (script.active_mods.base or ""):match("^(%d+%.%d+)") then return end
            local refs = assert(REFS[c.case], c.case .. ": no staged refs")
            if type(refs) == "string" then refs = helpers.json_to_table(refs) end  --staged as JSON text
            local def = c.profile == "player"
                and Drive.case_def(helpers.json_to_table((assert(PREPARED[c.case], c.case .. ": no staged prepared input"))))
                or Drive.vanilla_def(c.case)
            local force = game.forces.player
            local stack = Lab.research_stack(force)
            --The player's force as the Case captured it (ports.json "force", newest export, 1e67075): inserter bonuses
            --and recipe productivity research. Blue ran 5.7-6.8/s of 10 without the research (2026-09-29).
            local captured = SHEET[c.case] and helpers.json_to_table(SHEET[c.case].ports).force or {}
            if captured.bulk_inserter_capacity_bonus then force.bulk_inserter_capacity_bonus = captured.bulk_inserter_capacity_bonus end
            if captured.inserter_stack_size_bonus then force.inserter_stack_size_bonus = captured.inserter_stack_size_bonus end
            for recipe, bonus in pairs(captured.research or {}) do
                if force.recipes[recipe] then force.recipes[recipe].productivity_bonus = bonus end
            end
            local player = S.player()
            async(10000000)  --settling has no tick limit (player Q14); the 120 s per-check cap ends a Case that never settles
            Drive.setup(def, function(sheet)
                --The record keeps the solver answer under .result (logic/calculation_result.lua normalized_record).
                local calc = assert((Calculation.get(1, S.sheet_id(sheet))), c.case .. ": no calculation result after setup").result
                for full_name, rate in pairs(refs.outputs) do
                    assert(rel_close(calc.solved_rates[full_name], rate), string.format("%s: calc %s %s/s, refs %s/s",
                        c.case, full_name, tostring(calc.solved_rates[full_name]), rate))
                end
                for full_name, rate in pairs(refs.inputs) do
                    assert(rel_close(calc.unsolved_rates[full_name], rate), string.format("%s: calc input %s %s/s, refs %s/s",
                        c.case, full_name, tostring(calc.unsolved_rates[full_name]), rate))
                end
                Drive.generate(sheet, def)
                S.wait_until(function() return storage[1].blueprint_job == nil end, 36000, function()
                    local cursor = player.cursor_stack
                    assert(cursor.valid_for_read and cursor.is_blueprint and cursor.is_blueprint_setup(), c.case .. ": no blueprint in cursor")
                    local bp = cursor.get_blueprint_entities()
                    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
                    for _, e in ipairs(bp) do
                        l, t = math.min(l, e.position.x), math.min(t, e.position.y)
                        r, b = math.max(r, e.position.x), math.max(b, e.position.y)
                    end
                    --nauvis, not Lab.surface(): the engine places no blueprint ghost on the lab surface (build_from_cursor and
                    --LuaItemStack.build_blueprint both 0 of 148 on rrc-lab, 2.0.77 2026-10-05; Lab.build notes the same 2026-09-29).
                    local surface = game.surfaces.nauvis
                    surface.peaceful_mode = true
                    local spot = {index * 1024, 0}
                    local half = math.ceil(math.max(r - l, b - t) / 2) + 24
                    local area = {{spot[1] - half, spot[2] - half}, {spot[1] + half, spot[2] + half}}
                    Lab.prepare(surface, area)
                    local tiles = {}
                    for x = area[1][1], area[2][1] - 1 do for y = area[1][2], area[2][2] - 1 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
                    surface.set_tiles(tiles)
                    for _, e in pairs(surface.find_entities(area)) do if e.valid and e.type ~= "character" then e.destroy() end end
                    assert(player.teleport(spot, surface), c.case .. ": character cannot reach the build spot")
                    if player.character then player.character_build_distance_bonus = 10000 end
                    player.opened = nil
                    player.build_from_cursor{position = spot, build_mode = defines.build_mode.forced}
                    local ghosts = surface.find_entities_filtered{area = area, type = "entity-ghost"}
                    assert(#ghosts == #bp, string.format("%s: %d ghosts for %d blueprint entities", c.case, #ghosts, #bp))
                    local failed = {}
                    for _, g in ipairs(ghosts) do
                        if g.valid then
                            local name = g.ghost_name
                            local _, ent, proxy = g.revive{return_item_request_proxy = true}
                            if not ent then failed[#failed + 1] = name end
                            if proxy and proxy.valid then fulfil(proxy) end
                        end
                    end
                    for _, p in ipairs(surface.find_entities_filtered{area = area, name = "item-request-proxy"}) do fulfil(p) end
                    assert(#failed == 0, c.case .. ": " .. #failed .. " ghosts do not revive: " .. serpent.line(failed))
                    local laid, wires = lay_wires(Lab.decode(cursor.export_stack()), surface, area, force)
                    log(string.format("PLAYER-RUN-WIRES %s laid=%d of %d", c.case, laid, wires))
                    player.teleport({spot[1] - half - 8, spot[2]}, surface)
                    local entities, plains = {}, {}
                    local wl, wt, wr, wb = math.huge, math.huge, -math.huge, -math.huge
                    for _, e in pairs(surface.find_entities_filtered{area = area, force = force}) do
                        if e.type ~= "character" then
                            entities[#entities + 1] = e
                            plains[#plains + 1] = plain(e)
                            local box = e.bounding_box
                            wl, wt = math.min(wl, box.left_top.x), math.min(wt, box.left_top.y)
                            wr, wb = math.max(wr, box.right_bottom.x), math.max(wb, box.right_bottom.y)
                        end
                    end
                    local built = {entities = entities, origin = {math.floor(wl), math.floor(wt)}}
                    assert(Lab.power(surface, force, built), c.case .. ": lab power could not reach a pole")
                    local inputs, outputs = {}, {}
                    for k in pairs(refs.inputs) do inputs[k] = true end
                    for k in pairs(refs.outputs) do outputs[k] = true end
                    local prepared = PREPARED[c.case] and helpers.json_to_table(PREPARED[c.case])
                    local by_machine = {}
                    for _, col in ipairs(def.columns or {}) do
                        local m = type(col.machine) == "table" and col.machine.name or col.machine
                        if m then by_machine[m] = by_machine[m] or {}; table.insert(by_machine[m], col.recipe_name) end
                    end
                    local found = Ports.find{entities = plains, catalog = prepared and prepared.catalog or prototype_catalog(plains),
                        inputs = inputs, outputs = outputs, recipes_for = function(m) return by_machine[m] or {} end}
                    assert(#found.problems == 0, c.case .. ": ports " .. serpent.line(found.problems))
                    local feeds, sinks = {}, {}
                    for _, f in ipairs(found.feeds) do
                        local ent = at_tile(surface, f.tile[1] or f.tile.x, f.tile[2] or f.tile.y)
                        assert(Lab.feed_shape_ok(ent, f.fluid), c.case .. ": FEED_PORT_SHAPE " .. serpent.line(f))
                        feeds[#feeds + 1] = {entity = ent, item = f.item, fluid = f.fluid}
                    end
                    for _, s in ipairs(found.sinks) do
                        sinks[#sinks + 1] = {entity = at_tile(surface, s.tile[1] or s.tile.x, s.tile[2] or s.tile.y), got = {}, items = {s.item}}
                    end
                    local speed = 0.03125
                    for _, e in ipairs(entities) do if e.valid and e.type == "transport-belt" then speed = math.max(speed, e.prototype.belt_speed) end end
                    local warm = math.max(3600, math.ceil(((wr - wl) + (wb - wt)) * 2 / speed) + 600)
                    local window = Lab.window_ticks(refs.outputs)  --metered windows until output stabilizes (Lab.settle), as tests/game/test_sheets.lua
                    local pool = Lab.meter_new(refs.inputs)
                    local t0, window_start, history, cleared = game.tick, nil, {}, false
                    local warmed, warm_stock = false, nil
                    --Judged on production (Lab.made deltas); the sink count is the cross-check (tests/game/test_sheets.lua).
                    local made_start
                    local function per_s_now()
                        local per, sunk = {}, {}
                        for _, s in ipairs(sinks) do
                            for name, count in pairs(s.got) do
                                local full = outputs["item/" .. name] and ("item/" .. name) or ("fluid/" .. name)
                                sunk[full] = (sunk[full] or 0) + count / (window / 60)
                            end
                        end
                        local made_now = Lab.made(entities, outputs)
                        for full in pairs(outputs) do per[full] = ((made_now[full] or 0) - ((made_start or {})[full] or 0)) / (window / 60) end
                        made_start = made_now
                        return per, sunk
                    end
                    game.speed = 1000
                    on_tick(function()
                        local now = game.tick - t0
                        --Full-feed warm-up primes machines, pipes and inner belts (until inner stock stops growing, Lab.warm_ready),
                        --then input-only belts are emptied and only Metered feed runs (tests/game/test_sheets.lua).
                        local measuring = warmed
                        if not measuring then
                            Lab.feed_tick(feeds, stack)
                            if now >= warm and (now - warm) % Lab.WARM_STEP == 0 then
                                local stock = Lab.inner_stock(entities, refs.inputs, refs.outputs)
                                if Lab.warm_ready(warm_stock, stock) or now - warm >= Lab.WARM_CAP then
                                    warmed, warm = true, now
                                    log(string.format("PLAYER-RUN-WARM %s t=%d inner=%d window=%d", c.case, now, stock, window))
                                end
                                warm_stock = stock
                            end
                        else
                            if not cleared then cleared = true; log("PLAYER-RUN-CLEAR " .. c.case .. " items=" .. Lab.clear_input_belts(entities, refs.inputs)) end
                            Lab.meter_tick(pool, feeds, stack)
                        end
                        if measuring and not window_start then window_start = now; made_start = Lab.made(entities, outputs) end
                        Lab.sink_tick(sinks, measuring)
                        if not window_start or now - window_start < window then return end
                        local per, sunk = per_s_now()
                        local worst = math.huge
                        for full_name, rate in pairs(refs.outputs) do worst = math.min(worst, (per[full_name] or 0) / rate) end
                        local credit = {}
                        for name, m in pairs(pool) do credit[#credit + 1] = string.format("%s=%.1f", name, m.credit) end
                        table.sort(credit)
                        log(string.format("PLAYER-RUN-WINDOW %s t=%d worst=%.3f %s credit %s", c.case, now, worst, serpent.line(per), table.concat(credit, " ")))
                        for _, s in ipairs(sinks) do s.seen = s.seen or {}; for name in pairs(s.got) do s.seen[name] = true end; s.got = {} end
                        window_start = now
                        local stable, mean_per, mean_sunk = Lab.settle(history, per, sunk, window / 60)
                        do local c = {} for name, m in pairs(pool) do c[name] = m.credit end history[#history].credit = c end
                        if not stable then return end
                        per, sunk = mean_per, mean_sunk
                        game.speed = 1
                        local ok, problems, lines = Lab.judge(per, refs.outputs)
                        problems = problems or {}
                        for full_name, made in pairs(per) do
                            if made > 0 and math.abs((sunk[full_name] or 0) - made) > 0.05 * made then
                                problems[#problems + 1] = string.format("SINK_DIFF %s made %.3f/s sunk %.3f/s", full_name, made, sunk[full_name] or 0)
                            end
                        end
                        local backlog = Lab.meter_backlog(pool, feeds, stack, (history[#history - Lab.SETTLE_WINDOWS] or {}).credit)
                        if #backlog > 0 then problems[#problems + 1] = "POOL_BACKLOG " .. table.concat(backlog, ",") end
                        for _, s in ipairs(sinks) do
                            local allowed = {}
                            for _, n in ipairs(s.items) do allowed[(n:gsub("^%a+/", ""))] = true end
                            for name in pairs(s.seen or {}) do if not allowed[name] then problems[#problems + 1] = "foreign " .. name .. " at sink" end end
                        end
                        log("PLAYER-RUN " .. c.case .. " stack=" .. stack .. " warm=" .. warm .. " t=" .. now .. " " .. table.concat(lines or {}, "; "))
                        assert(ok and #problems == 0, c.case .. ": " .. table.concat(problems, "; ") .. " | " .. table.concat(lines or {}, "; "))
                        done()
                        return false
                    end)
                end, c.case .. ": blueprint delivery")
            end)
        end)
    end
end)

--Feed and sink tiles of a built sheet from geometry alone (Player run, plan 2026-10-05). A Lua port of
--tools/sheet_ports.py (the Sheet sim's port tracer since round 48) with one change: blueprint bytes carry no port
--ids, so seeds are every hand that picks from a belt (inputs) and every hand that drops an output item onto a belt (sinks).
--Furnaces carry no recipe in blueprint bytes (they pick it from what arrives): such a machine's recipe comes from
--downstream, the recipe among those it can craft whose product its output hands' consumers take.
--Entities are plain tables {name, position = {x, y}, direction (16-way), recipe?, mirror?, belt_to_ground_type? or
--type = "input"|"output" for undergrounds}, so the same code runs on decoded fixtures offline and on built entities.
--An inserter's direction points at its PICKUP (reach 2 for long-handed). Catalog = prepared_input catalog shape
--(recipe[name] = {ingredients, products, fluid_boxes}, entity[name] = {fluid_boxes, tile_w, tile_h}); recipes_for(machine
--name) = the recipes the calculation runs on that machine (a furnace's candidates).
local Ports = {}

local VEC = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}

local function kind(name)
    if name:find("underground%-belt$") then return "ug" end
    if name:find("splitter$") then return "splitter" end
    if name:find("transport%-belt$") then return "belt" end
    if name == "pipe" or name:find("%-pipe$") then return "pipe" end
    if name:find("pipe%-to%-ground$") then return "ptg" end
    if name:find("inserter", 1, true) then return "hand" end
    return "other"
end
local function key(x, y) return x .. "," .. y end
local function tile_of(e) return math.floor(e.position.x), math.floor(e.position.y) end
local function dir(e) return e.direction or 0 end
local function ug_type(e) return e.belt_to_ground_type or ((e.type == "input" or e.type == "output") and e.type) or nil end
local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function Ports.find(args)
    local entities, catalog = args.entities, args.catalog or {}
    local recipes, specs = catalog.recipe or {}, catalog.entity or {}
    local inputs, outputs = args.inputs or {}, args.outputs or {}
    local problems = {}
    local cells, partner, pair = {}, {}, {}
    local xs, ys = {}, {}
    local function note(x, y) xs[#xs + 1] = x; ys[#ys + 1] = y end

    --Tiles: splitter halves share one entity; everything else one tile per entity (machines handled by footprint).
    local machines, hands, ugs = {}, {}, {}
    for _, e in ipairs(entities) do
        local k = kind(e.name)
        local x, y = tile_of(e)
        if k == "splitter" then
            local d = dir(e)
            local dx, dy = (d == 0 or d == 8) and 0.5 or 0, (d == 0 or d == 8) and 0 or 0.5
            local h1 = {math.floor(e.position.x - dx), math.floor(e.position.y - dy)}
            local h2 = {math.floor(e.position.x + dx), math.floor(e.position.y + dy)}
            cells[key(h1[1], h1[2])] = {e = e, k = k, x = h1[1], y = h1[2]}
            cells[key(h2[1], h2[2])] = {e = e, k = k, x = h2[1], y = h2[2]}
            partner[key(h1[1], h1[2])], partner[key(h2[1], h2[2])] = key(h2[1], h2[2]), key(h1[1], h1[2])
            note(h1[1], h1[2]); note(h2[1], h2[2])
        elseif k ~= "other" then
            cells[key(x, y)] = {e = e, k = k, x = x, y = y}
            note(x, y)
            if k == "hand" then hands[#hands + 1] = e end
            if k == "ug" then ugs[#ugs + 1] = e end
        else
            note(x, y)
            if recipes[e.recipe or ""] or (args.recipes_for and #args.recipes_for(e.name) > 0) then machines[#machines + 1] = e end
        end
    end
    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #xs do l, r = math.min(l, xs[i]), math.max(r, xs[i]); t, b = math.min(t, ys[i]), math.max(b, ys[i]) end
    local function on_edge(x, y) return x == l or x == r or y == t or y == b end

    --Underground pairs: an entrance pairs with the nearest exit ahead on its axis facing the same way (no ug_pair_id in
    --blueprint bytes, no LuaEntity.neighbours on 2.1).
    for _, a in ipairs(ugs) do
        if ug_type(a) == "input" then
            local ax, ay = tile_of(a)
            local v = VEC[dir(a)]
            local best, best_d
            for _, o in ipairs(ugs) do
                if o ~= a and ug_type(o) == "output" and dir(o) == dir(a) then
                    local ox, oy = tile_of(o)
                    local along = (v[1] ~= 0 and oy == ay) or (v[2] ~= 0 and ox == ax)
                    local dist = (ox - ax) * v[1] + (oy - ay) * v[2]
                    if along and dist > 0 and (not best_d or dist < best_d) then best, best_d = key(ox, oy), dist end
                end
            end
            if best then pair[key(ax, ay)] = best end
        end
    end

    local function beltish(c) return c and (c.k == "belt" or c.k == "ug" or c.k == "splitter") end
    local function successors(c)
        local e, d = c.e, dir(c.e)
        if c.k == "ug" and ug_type(e) == "input" then
            local p = pair[key(c.x, c.y)]
            return p and {p} or {}
        end
        local v = VEC[d]
        local nk = key(c.x + v[1], c.y + v[2])
        local n = cells[nk]
        if beltish(n) then
            local nd = dir(n.e)
            if n.k == "ug" and ug_type(n.e) == "output" and nd == d then return {} end  --exit entered from its buried rear
            local nv = VEC[nd]
            if nv[1] + v[1] == 0 and nv[2] + v[2] == 0 then return {} end  --head-on
            return {nk}
        end
        return {}
    end
    local preds = {}
    for _, ck in ipairs(sorted_keys(cells)) do
        local c = cells[ck]
        if beltish(c) then
            for _, n in ipairs(successors(c)) do preds[n] = preds[n] or {}; table.insert(preds[n], ck) end
        end
    end

    --Machine footprints: tile -> machine.
    local at_machine = {}
    for _, m in ipairs(machines) do
        local spec = specs[m.name] or {}
        local w, h = spec.tile_w or 3, spec.tile_h or 3
        local d = dir(m)
        if d == 4 or d == 12 then w, h = h, w end
        local x0, y0 = math.floor(m.position.x - w / 2 + 0.5), math.floor(m.position.y - h / 2 + 0.5)
        for x = x0, x0 + w - 1 do for y = y0, y0 + h - 1 do at_machine[key(x, y)] = m end end
    end
    local function reach(e) return e.name:find("long%-handed") and 2 or 1 end
    local function pickup(e) local x, y = tile_of(e); local v = VEC[dir(e)]; return x + v[1] * reach(e), y + v[2] * reach(e) end
    local function drop(e) local x, y = tile_of(e); local v = VEC[dir(e)]; return x - v[1] * reach(e), y - v[2] * reach(e) end

    --Downstream walk from a belt tile: every belt cell reached (both splitter halves).
    local function downstream(start)
        local seen, todo = {}, {start}
        while #todo > 0 do
            local ck = table.remove(todo)
            local c = cells[ck]
            if beltish(c) and not seen[ck] then
                seen[ck] = true
                for _, n in ipairs(successors(c)) do todo[#todo + 1] = n end
                if partner[ck] then todo[#todo + 1] = partner[ck] end
            end
        end
        return seen
    end
    local hands_picking, hands_dropping = {}, {}
    for _, hnd in ipairs(hands) do
        local px, py = pickup(hnd)
        local dx, dy = drop(hnd)
        local pk, dk = key(px, py), key(dx, dy)
        hands_picking[pk] = hands_picking[pk] or {}; table.insert(hands_picking[pk], hnd)
        hands_dropping[#hands_dropping + 1] = {hand = hnd, pk = pk, dk = dk}
    end

    --Recipe of a machine: its own, or (furnace) the recipe whose product its consumers take.
    local recipe_memo, inferring = {}, {}
    local function items_of(list, want_kind)
        local out = {}
        for _, i in ipairs(list or {}) do
            local k = i.type or i.kind or "item"
            if not want_kind or k == want_kind then out[#out + 1] = {name = i.name, kind = k} end
        end
        return out
    end
    local recipe_of
    local function consumers_want(m)
        local want = {}
        for _, hd in ipairs(hands_dropping) do
            if at_machine[hd.pk] == m then
                local targets = {}
                if at_machine[hd.dk] then targets[#targets + 1] = at_machine[hd.dk]
                elseif beltish(cells[hd.dk]) then
                    for ck in pairs(downstream(hd.dk)) do
                        for _, ch in ipairs(hands_picking[ck] or {}) do
                            local tm = at_machine[key(drop(ch))]
                            if tm and tm ~= m then targets[#targets + 1] = tm end
                        end
                    end
                end
                for _, tm in ipairs(targets) do
                    local tr = recipe_of(tm)
                    for _, i in ipairs(items_of(tr and recipes[tr] and recipes[tr].ingredients)) do want[i.kind .. "/" .. i.name] = true end
                end
            end
        end
        return want
    end
    recipe_of = function(m)
        if m.recipe then return m.recipe end
        if recipe_memo[m] ~= nil then return recipe_memo[m] or nil end
        if inferring[m] then return nil end
        inferring[m] = true
        local want = consumers_want(m)
        local found = {}
        for _, rn in ipairs(args.recipes_for and args.recipes_for(m.name) or {}) do
            local rec = recipes[rn]
            if rec then
                for _, p in ipairs(items_of(rec.products)) do
                    local full = p.kind .. "/" .. p.name
                    if want[full] or outputs[full] then found[#found + 1] = rn; break end
                end
            end
        end
        inferring[m] = nil
        local chosen = #found == 1 and found[1] or nil
        if not chosen then
            local mx, my = tile_of(m)
            problems[#problems + 1] = string.format("NO_RECIPE %d,%d %s candidates=%s", mx, my, m.name, table.concat(found, ","))
        end
        recipe_memo[m] = chosen or false
        return chosen
    end

    --Inputs: from each hand that picks from a belt into a machine, walk upstream to heads; edge heads are feeds.
    local feeds, feed_items = {}, {}
    for _, hd in ipairs(hands_dropping) do
        local c = cells[hd.pk]
        local m = at_machine[hd.dk]
        if beltish(c) and m then
            local rn = recipe_of(m)
            local cands = {}
            for _, i in ipairs(items_of(rn and recipes[rn] and recipes[rn].ingredients, "item")) do
                if inputs["item/" .. i.name] then cands[#cands + 1] = i.name end
            end
            if #cands > 0 then
                local todo, seen, heads = {hd.pk}, {}, {}
                while #todo > 0 do
                    local ck = table.remove(todo)
                    if cells[ck] and not seen[ck] then
                        seen[ck] = true
                        local ups = {}
                        for _, u in ipairs(preds[ck] or {}) do ups[#ups + 1] = u end
                        local pk2 = partner[ck]
                        if pk2 then
                            for _, u in ipairs(preds[pk2] or {}) do ups[#ups + 1] = u end
                            todo[#todo + 1] = pk2
                        end
                        if #ups > 0 then
                            for _, u in ipairs(ups) do todo[#todo + 1] = u end
                        elseif not pk2 then
                            heads[#heads + 1] = ck
                        end
                    end
                end
                for _, h in ipairs(heads) do
                    local hc = cells[h]
                    if on_edge(hc.x, hc.y) and (hc.k == "belt" or hc.k == "ug") then
                        --Intersection over every hand on the chain: a foundry hand wants ore AND calcite, but the
                        --calcite chain's hands go to every foundry, so only calcite survives there.
                        local now = {}
                        for _, n in ipairs(cands) do if feed_items[h] == nil or feed_items[h][n] then now[n] = true end end
                        feed_items[h] = now
                    end
                end
            end
        end
    end
    --Elimination: an item fixed at one head (a single candidate left) leaves every head that still has a choice.
    local changed = true
    while changed do
        changed = false
        for _, h in ipairs(sorted_keys(feed_items)) do
            local names = sorted_keys(feed_items[h])
            if #names == 1 then
                for _, o in ipairs(sorted_keys(feed_items)) do
                    if o ~= h and feed_items[o][names[1]] and #sorted_keys(feed_items[o]) > 1 then feed_items[o][names[1]] = nil; changed = true end
                end
            end
        end
    end
    for _, h in ipairs(sorted_keys(feed_items)) do
        local names = sorted_keys(feed_items[h])
        local hc = cells[h]
        if #names == 1 then feeds[#feeds + 1] = {tile = {hc.x, hc.y}, item = names[1]}
        else problems[#problems + 1] = string.format("TWO_ITEMS %d,%d %s", hc.x, hc.y, table.concat(names, ",")) end
    end
    --Every edge belt head nobody feeds must be named: one left unnamed is reported, never guessed.
    for _, ck in ipairs(sorted_keys(cells)) do
        local c = cells[ck]
        if (c.k == "belt" or c.k == "ug") and on_edge(c.x, c.y) and not preds[ck] and #successors(c) > 0 and not feed_items[ck] then
            problems[#problems + 1] = string.format("UNNAMED_HEAD %d,%d", c.x, c.y)
        end
    end

    --Sinks: from each hand that drops an output item from a machine onto a belt, walk downstream to the chain end.
    local sink_items = {}
    for _, hd in ipairs(hands_dropping) do
        local m = at_machine[hd.pk]
        local c = cells[hd.dk]
        if m and beltish(c) then
            local rn = recipe_of(m)
            local made = {}
            for _, p in ipairs(items_of(rn and recipes[rn] and recipes[rn].products, "item")) do
                if outputs["item/" .. p.name] then made[#made + 1] = p.name end
            end
            if #made > 0 then
                local ck, seen = hd.dk, {}
                while cells[ck] and not seen[ck] do
                    seen[ck] = true
                    local nxt = beltish(cells[ck]) and successors(cells[ck]) or {}
                    if #nxt == 0 then break end
                    ck = nxt[1]
                end
                local ec = cells[ck]
                if ec and on_edge(ec.x, ec.y) then
                    sink_items[ck] = sink_items[ck] or {}
                    for _, n in ipairs(made) do sink_items[ck][n] = true end
                else
                    problems[#problems + 1] = "SINK_NOT_ON_EDGE " .. ck .. " " .. table.concat(made, ",")
                end
            end
        end
    end
    local sinks = {}
    for _, ck in ipairs(sorted_keys(sink_items)) do
        local c = cells[ck]
        for _, n in ipairs(sorted_keys(sink_items[ck])) do sinks[#sinks + 1] = {tile = {c.x, c.y}, item = n} end
    end

    --Fluid inputs: tools/sheet_ports.py fluid section, line for line.
    local fluid_in = {}
    for full in pairs(inputs) do local n = full:match("^fluid/(.+)$"); if n then fluid_in[n] = true end end
    if next(fluid_in) then
        local pipes, ptgs, ptg_pair = {}, {}, {}
        for ck, c in pairs(cells) do if c.k == "pipe" or c.k == "ptg" then pipes[ck] = c end end
        for _, c in pairs(pipes) do if c.k == "ptg" then ptgs[#ptgs + 1] = c end end
        table.sort(ptgs, function(p, q) return key(p.x, p.y) < key(q.x, q.y) end)
        for _, a in ipairs(ptgs) do
            local best, best_d
            for _, o in ipairs(ptgs) do
                if o ~= a and (dir(a.e) + 8) % 16 == dir(o.e) then
                    local v = VEC[dir(o.e)]
                    local along = (v[1] ~= 0 and a.y == o.y) or (v[2] ~= 0 and a.x == o.x)
                    if along and (o.x ~= a.x or o.y ~= a.y) and ((o.x - a.x) * v[1] > 0 or (o.y - a.y) * v[2] > 0) then
                        local dist = math.abs(a.x - o.x) + math.abs(a.y - o.y)
                        if not best_d or dist < best_d then best, best_d = key(o.x, o.y), dist end
                    end
                end
            end
            if best then ptg_pair[key(a.x, a.y)] = best end
        end
        local function links(ck)
            local c = pipes[ck]
            local out = {}
            if c.k == "ptg" then
                local v = VEC[dir(c.e)]
                out[#out + 1] = key(c.x + v[1], c.y + v[2])
                if ptg_pair[ck] then out[#out + 1] = ptg_pair[ck] end
            else
                for _, d in ipairs({0, 4, 8, 12}) do out[#out + 1] = key(c.x + VEC[d][1], c.y + VEC[d][2]) end
            end
            local keep = {}
            for _, nk in ipairs(out) do
                local n = pipes[nk]
                if n then
                    local ok = true
                    if n.k == "ptg" and nk ~= ptg_pair[ck] then
                        local v = VEC[dir(n.e)]
                        if key(n.x + v[1], n.y + v[2]) ~= ck then ok = false end
                    end
                    if ok then keep[#keep + 1] = nk end
                end
            end
            return keep
        end
        local comp = {}
        for _, p0 in ipairs(sorted_keys(pipes)) do
            if not comp[p0] then
                comp[p0] = p0
                local stack = {p0}
                while #stack > 0 do
                    local ck = table.remove(stack)
                    for _, nk in ipairs(links(ck)) do if not comp[nk] then comp[nk] = p0; stack[#stack + 1] = nk end end
                end
            end
        end
        local function connection_tiles(m, fbox)
            local d, out = dir(m), {}
            for _, conn in ipairs(fbox.connections or {}) do
                local positions = conn.positions or {}
                local pos, cdir = positions[math.floor(d / 4) + 1], ((conn.direction or 0) + d) % 16
                if m.mirror then
                    local north = positions[1]
                    if north then
                        local x, y, nd = -north.x, north.y, (16 - (conn.direction or 0)) % 16
                        for _ = 1, math.floor(d / 4) do x, y = -y, x end
                        pos, cdir = {x = x, y = y}, (nd + d) % 16
                    else
                        pos = nil
                    end
                end
                if pos then
                    local v = VEC[cdir]
                    out[#out + 1] = key(math.floor(m.position.x + pos.x + v[1]), math.floor(m.position.y + pos.y + v[2]))
                end
            end
            return out
        end
        local fluid_of = {}
        local function add(root, fluid) fluid_of[root] = fluid_of[root] or {}; fluid_of[root][fluid] = true end
        for _, m in ipairs(machines) do
            local rec = recipes[m.recipe or ""]
            if rec then
                local wants = {}
                for _, i in ipairs(items_of(rec.ingredients, "fluid")) do wants[#wants + 1] = i.name end
                local any = false
                for _, w in ipairs(wants) do if fluid_in[w] then any = true end end
                if any then
                    local spec = specs[m.name] or {}
                    local all_boxes = spec.fluid_boxes or {}
                    local bound = (rec.fluid_boxes or {})[m.name] or {}
                    local has_bound = false
                    for _, w in ipairs(wants) do if bound[w] then has_bound = true end end
                    if has_bound then
                        for _, w in ipairs(wants) do
                            if fluid_in[w] then
                                for _, index in ipairs((bound[w] or {}).boxes or {}) do
                                    for pos, fbox in ipairs(all_boxes) do
                                        if (fbox.index or pos) == index then
                                            for _, nk in ipairs(connection_tiles(m, fbox)) do if comp[nk] then add(comp[nk], w) end end
                                        end
                                    end
                                end
                            end
                        end
                    else
                        local boxes = {}
                        for _, fbox in ipairs(all_boxes) do if fbox.production_type == "input" then boxes[#boxes + 1] = fbox end end
                        table.sort(boxes, function(p, q) return (p.index or 0) < (q.index or 0) end)
                        for i, fbox in ipairs(boxes) do
                            if wants[i] and fluid_in[wants[i]] then
                                for _, nk in ipairs(connection_tiles(m, fbox)) do if comp[nk] then add(comp[nk], wants[i]) end end
                            end
                        end
                    end
                end
            end
        end
        for _, root in ipairs(sorted_keys(fluid_of)) do
            local fluids = sorted_keys(fluid_of[root])
            if #fluids > 1 then
                problems[#problems + 1] = "pipe network " .. root .. " gets several input fluids " .. table.concat(fluids, ",")
            else
                for _, ck in ipairs(sorted_keys(comp)) do
                    local c = pipes[ck]
                    if comp[ck] == root and on_edge(c.x, c.y) then feeds[#feeds + 1] = {tile = {c.x, c.y}, fluid = fluids[1]} end
                end
            end
        end
    end
    return {feeds = feeds, sinks = sinks, problems = problems, bbox = {l, t, r, b}}
end

return Ports

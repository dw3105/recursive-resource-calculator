-- p06.lua: ckpt.lua --patch file (in-memory only, RC-17). LEVERS env = comma list:
--   heap    route.lua: heap_before without `or cost` fallback, push/pop with hole sift (same order: serial is unique)
--   dirv    route.lua: local dir_vector / dir_opposite tables instead of Grid.dir_vector calls
--   pcov    power.lua: consumer_covered + rect_intersects without temp tables / extra calls
--   psel    power.lua: greedy selected_check remembers per candidate a permanent rejection (selected only grows in greedy)
--   sitime  search.lua: time stage_input per top-level key (stderr SI lines)
--   sishare search.lua: stage_input shares listed top-level keys (SISHARE=catalog,...) by reference
--   siguard with sishare: sha of shared keys before/after, stderr SIGUARD line when changed
local levers = {}
for l in (rawget(_G, "P06_LEVERS") or os.getenv("LEVERS") or ""):gmatch("[^,]+") do levers[l] = true end
local function rep(src, old, new, label)
    local a, b = src:find(old, 1, true)
    assert(a, "p06: missing anchor " .. label)
    assert(not src:find(old, b + 1, true), "p06: anchor not unique " .. label)
    return src:sub(1, a - 1) .. new .. src:sub(b + 1)
end
local function block(src, first_line, label)
    -- replace a top-level local function from its first line to the first "\nend\n" after it
    local a = src:find(first_line, 1, true); assert(a, "p06: missing " .. label)
    local e1, e2 = src:find("\nend\n", a, true)
    return a, e2
end
local function replace_fn(src, first_line, new, label)
    local a, e = block(src, first_line, label)
    return src:sub(1, a - 1) .. new .. "\n" .. src:sub(e + 1)
end

return function(name, src)
    if name == "logic.bp.route" then
        if levers.heap then
            src = replace_fn(src, "local function heap_before(left, right)", [[
local function heap_before(left, right)
    local lp, rp = left.priority, right.priority
    if lp ~= rp then return lp < rp end
    local lc, rc = left.cost, right.cost
    if lc ~= rc then return lc < rc end
    return left.serial < right.serial
end]], "heap_before")
            src = replace_fn(src, "local function heap_push(search, node)", [[
local function heap_push(search, node)
    local serial = search.serial + 1
    search.serial = serial
    node.serial = serial
    local heap = search.heap
    local index = #heap + 1
    local np, nc = node.priority, node.cost
    while index > 1 do
        local parent = (index - index % 2) / 2
        local p = heap[parent]
        local pp = p.priority
        if pp ~= np then
            if pp < np then break end
        else
            local pc = p.cost
            if pc ~= nc then
                if pc < nc then break end
            elseif p.serial < serial then break end
        end
        heap[index] = p
        index = parent
    end
    heap[index] = node
end]], "heap_push")
            src = replace_fn(src, "local function heap_pop(search)", [[
local function heap_pop(search)
    local heap = search.heap
    local n = #heap
    if n == 0 then return nil end
    local result = heap[1]
    local last = heap[n]
    heap[n] = nil
    n = n - 1
    if n > 0 then
        local index = 1
        while true do
            local child = index * 2
            if child > n then break end
            local cn = heap[child]
            if child < n then
                local rn = heap[child + 1]
                if heap_before(rn, cn) then child = child + 1; cn = rn end
            end
            if heap_before(cn, last) then heap[index] = cn; index = child else break end
        end
        heap[index] = last
    end
    return result
end]], "heap_pop")
            io.stderr:write("P06 heap live\n")
        end
        if levers.cempty then
            -- crossing_targets: early exits return one shared empty list (the only caller only iterates it)
            local a = src:find("local function crossing_targets(", 1, true); assert(a, "p06: crossing_targets")
            local e = src:find("\nend\n", a, true)
            local body = src:sub(a, e)
            local n
            body, n = body:gsub("return {} end", "return P06_EMPTY end")
            src = src:sub(1, a - 1) .. "local P06_EMPTY = setmetatable({}, {__newindex = function() error('P06_EMPTY written') end})\n" .. body .. src:sub(e + 1)
            io.stderr:write("P06 cempty live n=" .. n .. "\n")
        end
        if levers.dirv then
            -- defined right after the module's first `local Grid = require` line
            local a, b = src:find('local Grid = require[^\n]*\n')
            assert(a, "p06: Grid require")
            src = src:sub(1, b) .. [[
local P06 = {}
do
    local DX = {[0] = 0, [4] = 1, [8] = 0, [12] = -1}
    local DY = {[0] = -1, [4] = 0, [8] = 1, [12] = 0}
    P06.dv = function(dir)
        dir = (dir or 0) % 16
        local x = DX[dir]
        if x == nil then return nil end
        return x, DY[dir]
    end
    P06.opp = function(dir) return ((dir or 0) % 16 + 8) % 16 end
end
]] .. src:sub(b + 1)
            local n1, n2
            src, n1 = src:gsub("Grid%.dir_vector%(", "P06.dv(")
            src, n2 = src:gsub("Grid%.dir_opposite%(", "P06.opp(")
            io.stderr:write(string.format("P06 dirv live dir_vector=%d dir_opposite=%d\n", n1, n2))
        end
    elseif name == "logic.bp.power" then
        if levers.pcov then
            src = replace_fn(src, "local function rect_intersects(a, b)", [[
local function rect_intersects(a, b)
    if a == nil or b == nil then return false end
    local aw, ah, bw, bh = a.w, a.h, b.w, b.h
    if not (aw > 0 and ah > 0 and bw > 0 and bh > 0) then return false end
    local ax, ay, bx, by = a.x, a.y, b.x, b.y
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end]], "rect_intersects")
            src = replace_fn(src, "local function consumer_covered(candidate, consumer)", [[
local function consumer_covered(candidate, consumer)
    local r = consumer.rect
    if r == nil or not (r.w > 0 and r.h > 0) then return false end
    local cr = candidate.rect
    local sw, sh = candidate.supply_w, candidate.supply_h
    local sx, sy = cr.x + cr.w / 2 - sw, cr.y + cr.h / 2 - sh
    local w, h = sw * 2, sh * 2
    if not (w > 0 and h > 0) then return false end
    return sx < r.x + r.w and r.x < sx + w and sy < r.y + r.h and r.y < sy + h
end]], "consumer_covered")
            io.stderr:write("P06 pcov live\n")
        end
        if levers.pfast then
            -- per-op scheduler: finite/integer fast path for plain finite numbers (same results)
            src = replace_fn(src, "local function finite(value, fallback)", [[
local function finite(value, fallback)
    if type(value) == "number" and value - value == 0 then return value end
    return fallback
end]], "finite")
            src = replace_fn(src, "local function integer(value, fallback)", [[
local function integer(value, fallback)
    if type(value) == "number" and value - value == 0 then return math.floor(value) end
    value = finite(value, fallback)
    if value == nil then return nil end
    return math.floor(value)
end]], "integer")
            -- index builder: coverage test on one scratch candidate instead of a fresh table per position
            src = rep(src, [[
            local candidate = {spec_index = builder.spec_index, name = spec.name, quality = spec.quality,
                rect = candidate_rect(spec, builder.x, builder.y), supply_w = spec.supply_w,
                supply_h = spec.supply_h, wire_reach = spec.wire_reach, covers = {}}
            if consumer_covered(candidate, work.consumers[consumer_index]) then]], [[
            local candidate = P06_CAND
            local cr = candidate.rect
            cr.x, cr.y, cr.w, cr.h = builder.x, builder.y, spec.tile_w, spec.tile_h
            candidate.supply_w, candidate.supply_h = spec.supply_w, spec.supply_h
            if consumer_covered(candidate, work.consumers[consumer_index]) then]], "index candidate")
            src = rep(src, "local function advance_candidate_index(state)", "local P06_CAND = {rect = {}}\nlocal function advance_candidate_index(state)", "P06_CAND")
            io.stderr:write("P06 pfast live\n")
        end
        if levers.psel then
            src = rep(src, [[
                local rejected, variant_count = false, 0
                for _, selected_index in ipairs(work.selected) do
                    local selected = work.candidates[selected_index]
                    local candidate = work.candidates[greedy.candidate]
                    if rect_intersects(candidate.rect, selected.rect) then rejected = true end
                    if candidate.spec_index == selected.spec_index then variant_count = variant_count + 1 end
                end]], [[
                local rejected, variant_count = false, 0
                local memo = work._p06_sel
                if memo == nil or memo.list ~= work.selected then memo = {list = work.selected, hit = {}}; work._p06_sel = memo end
                if memo.hit[greedy.candidate] then rejected = true; _G.__p06_selhit = (_G.__p06_selhit or 0) + 1 else
                for _, selected_index in ipairs(work.selected) do
                    local selected = work.candidates[selected_index]
                    local candidate = work.candidates[greedy.candidate]
                    if rect_intersects(candidate.rect, selected.rect) then rejected = true end
                    if candidate.spec_index == selected.spec_index then variant_count = variant_count + 1 end
                end
                if rejected then memo.hit[greedy.candidate] = true end
                end]], "selected_check")
            io.stderr:write("P06 psel live\n")
        end
    elseif name == "logic.bp.search" then
        if levers.sitime then
            src = replace_fn(src, "local function stage_input(state, extra)", [[
local function stage_input(state, extra)
    local acc = _G.__p06_si or {n = 0, total = 0, keys = {}}; _G.__p06_si = acc
    local t0 = os.clock()
    local result = {}
    for key, value in pairs(state.work.input or {}) do
        local t = os.clock(); result[key] = copy(value); acc.keys[key] = (acc.keys[key] or 0) + os.clock() - t
    end
    for key, value in pairs(extra or {}) do
        local t = os.clock(); result[key] = copy(value); local k = "+" .. tostring(key); acc.keys[k] = (acc.keys[k] or 0) + os.clock() - t
    end
    acc.n = acc.n + 1; acc.total = acc.total + os.clock() - t0
    local list = {}; for k, v in pairs(acc.keys) do list[#list + 1] = {k, v} end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local parts = {}; for i = 1, math.min(6, #list) do parts[#parts + 1] = string.format("%s=%.0f", tostring(list[i][1]), list[i][2] * 1000) end
    io.stderr:write(string.format("SI n=%d total_ms=%.0f %s\n", acc.n, acc.total * 1000, table.concat(parts, " ")))
    return result
end]], "stage_input time")
        elseif levers.sishare then
            local share = os.getenv("SISHARE") or "catalog"
            src = replace_fn(src, "local function stage_input(state, extra)", [[
local P06_SHARE = {}
for k in (]] .. string.format("%q", share) .. [[):gmatch("[^,]+") do P06_SHARE[k] = true end
local function p06_fp(v, seen, out)
    local t = type(v)
    if t ~= "table" then out[#out + 1] = t .. ":" .. tostring(v); return end
    if seen[v] then out[#out + 1] = "<cycle>"; return end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "="; p06_fp(v[k], seen, out) end
    out[#out + 1] = "}"
    seen[v] = nil
end
local function p06_sig(v) local o = {}; p06_fp(v, {}, o); return table.concat(o, ",") end
local function stage_input(state, extra)
    local input = state.work.input or {}
    if os.getenv("SIGUARD") then
        local g = _G.__p06_guard or {}; _G.__p06_guard = g
        for k in pairs(P06_SHARE) do
            local sig = p06_sig(input[k])
            if g[k] == nil then g[k] = sig elseif g[k] ~= sig then io.stderr:write("SIGUARD changed " .. k .. "\n"); g[k] = sig end
        end
    end
    local result = {}
    for key, value in pairs(input) do
        if P06_SHARE[key] then result[key] = value else result[key] = copy(value) end
    end
    for key, value in pairs(extra or {}) do result[key] = copy(value) end
    return result
end]], "stage_input share")
            io.stderr:write("P06 sishare live " .. share .. "\n")
        end
    end
    return src
end

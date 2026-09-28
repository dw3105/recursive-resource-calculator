-- Function-level timer for logic/bp/route.lua, used as `ckpt.lua resume <snap> --patch prof_patch.lua`.
-- Env: PROF_OUT=<file> (default stderr), PROF_SET=coarse|fine|all (default all), PROF_EXTRA=<patch file> chained first.
local COARSE = {"route_snapshot", "restore_route_snapshot", "all_bindings_reach_sinks", "lift_binding", "binding_path",
    "route_weight", "append_normal_path", "begin_search", "search_step", "result_for", "audit_route_work",
    "restart_with_priority", "reanchor_bindings", "unbury_empty_pairs", "untangle_splitter_chains",
    "trial_start", "trial_run", "trial_finish", "fail_demand", "lay_belt_runs", "reserve_port_cells",
    "advance_flow_demand_build", "pairing_flood_step", "finish_demand_build", "append_underground",
    "underground_candidate"}
local FINE = {"path_cell_free", "enqueue_state", "heap_push", "heap_pop", "crossing_targets", "transition_cost",
    "route_chain_walk", "downstream_reaches_root", "search_path_tiles", "segment_allows", "bury_candidate",
    "splitter_branch_allowed", "splitter_straight_fed", "same_flow_port_tile", "reconstruct", "static_owner",
    "coordinate_key", "state_key", "coordinate_from_key"}
local set = os.getenv("PROF_SET") or "all"
local names = {}
if set ~= "fine" then for _, n in ipairs(COARSE) do names[#names + 1] = n end end
if set ~= "coarse" then for _, n in ipairs(FINE) do names[#names + 1] = n end end
if set == "fine" then names[#names + 1] = "search_step" end

if not _G.__P then
    local P = {stat = {}, counts = {}}
    local clock = os.clock
    local depth, child = 0, {}
    local function finish(s, t0, d, ...)
        local dt = clock() - t0
        s.n, s.incl, s.excl = s.n + 1, s.incl + dt, s.excl + dt - child[d]
        if dt > s.worst then s.worst = dt end
        depth = d - 1
        if d > 1 then child[d - 1] = child[d - 1] + dt end
        return ...
    end
    function P.call(name, f, ...)
        local s = P.stat[name]
        if not s then s = {n = 0, incl = 0, excl = 0, worst = 0}; P.stat[name] = s end
        depth = depth + 1
        local d = depth
        child[d] = 0
        return finish(s, clock(), d, f(...))
    end
    function P.count(name, by) P.counts[name] = (P.counts[name] or 0) + (by or 1) end
    local trial_log
    function P.trial(stage, st, weight, entities)
        trial_log = trial_log or assert(io.open(os.getenv("PROF_TRIALS"), "w"))
        local t, d, o = st.trial or {}, st.demand or {}, st.trial and st.trial.option or nil
        local kind = not o and "plain" or ((o.hop and "hop" or "slide") .. (o.multi_bindings and "+multi" or ""))
        trial_log:write(string.format("%s binding=%d opt=%d/%d kind=%s steps=%d found=%s refused=%s weight=%s before=%s best=%s flow=%s src=%s,%s sink=%s,%s entities=%d wanted=%s|%s|%s ep=%s hop=%s\n",
            stage, st.index or 0, st.option_index or 0, #(st.options or {}), kind, t.steps or 0, tostring(t.path ~= nil or (t.multi and t.index > #t.demands)),
            tostring(t.refused == true), tostring(weight), tostring(st.before), tostring(st.best_weight), tostring(d.flow_id),
            tostring(d.source and d.source.x), tostring(d.source and d.source.y), tostring(d.sink and d.sink.x), tostring(d.sink and d.sink.y), entities, tostring(st.wanted and st.wanted[1]), tostring(st.wanted and st.wanted[2]), tostring(st.wanted and st.wanted[3]), tostring(o and o.endpoint and o.endpoint.port_id), o and o.hop and (tostring(o.hop.port_x)..","..tostring(o.hop.port_y).." t"..tostring(o.hop.turns)) or (o and (tostring(o.dx)..","..tostring(o.dy)) or "-")))
        trial_log:flush()
    end
    local search_log
    function P.search(work, search, outcome)
        if not os.getenv("PROF_SEARCHES") then return end
        search_log = search_log or assert(io.open(os.getenv("PROF_SEARCHES"), "w"))
        local d = search.demand or {}
        search_log:write(string.format("search gen=%s tidy=%s steps=%d outcome=%s order=%s flow=%s src=%s,%s sink=%s,%s kind=%s blocked=%s cap=%s mix=%s ride=%s flags=%s%s%s%s%s\n",
            tostring(work.attempt_generation), tostring(work.allow_bury == true), search._n or 0,
            type(outcome) == "table" and ("path" .. #outcome) or tostring(outcome), tostring(search.order_index), tostring(d.flow_id),
            tostring(d.source and d.source.x), tostring(d.source and d.source.y), tostring(d.sink and d.sink.x), tostring(d.sink and d.sink.y),
            tostring(d.kind), tostring(search.saw_blocked), tostring(search.saw_capacity), tostring(search.saw_fluid_mix), tostring(search.allow_ride),
            d.strict_dive and "D" or "", d.no_self_cross and "X" or "", d.no_chain_dive and "C" or "", d.free_heading and "H" or "", d.curve_allowed and "V" or ""))
    end
    local dumped = false
    function P.dump()
        if dumped then return end
        dumped = true
        local out = os.getenv("PROF_OUT") and assert(io.open(os.getenv("PROF_OUT"), "w")) or io.stderr
        local rows = {}
        for name, s in pairs(P.stat) do rows[#rows + 1] = {name = name, s = s} end
        table.sort(rows, function(a, b) return a.s.excl > b.s.excl end)
        out:write(string.format("%-28s %10s %10s %10s %10s %10s\n", "function", "calls", "incl s", "excl s", "us/call", "worst ms"))
        for _, r in ipairs(rows) do
            out:write(string.format("%-28s %10d %10.3f %10.3f %10.2f %10.2f\n", r.name, r.s.n, r.s.incl, r.s.excl,
                r.s.n > 0 and r.s.incl / r.s.n * 1e6 or 0, r.s.worst * 1e3))
        end
        local keys = {}
        for k in pairs(P.counts) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do out:write(string.format("COUNT %s %s\n", k, tostring(P.counts[k]))) end
        out:write(string.format("TOTAL_CPU %.3f\n", clock()))
        if out ~= io.stderr then out:close() end
    end
    local exit = os.exit
    os.exit = function(...) P.dump(); return exit(...) end
    P.sentinel = setmetatable({}, {__gc = function() P.dump() end})
    _G.__P = P
end

local extra = os.getenv("PROF_EXTRA") and assert(loadfile(os.getenv("PROF_EXTRA")))() or nil

local function wrap_after(src, head, target, label)
    local a, b = src:find(head, 1, true)
    if not a then io.stderr:write("PROF missing " .. label .. "\n"); return src end
    local e1, e2 = src:find("\nend\n", b, true)
    assert(e1, "no end for " .. label)
    local inject = "do local raw = " .. target .. "; " .. target .. " = function(...) return _G.__P.call(" ..
        string.format("%q", label) .. ", raw, ...) end end\n"
    return src:sub(1, e2) .. inject .. src:sub(e2 + 1)
end

return function(name, src)
    if extra then src = assert(extra(name, src)) end
    if name ~= "logic.bp.route" then return src end
    for _, n in ipairs(names) do
        src = wrap_after(src, "\nlocal function " .. n .. "(", n, n)
    end
    if set ~= "fine" then
        src = wrap_after(src, "\nimprove_step = function(", "improve_step", "improve_step")
        src = wrap_after(src, "\nfunction Route.tidy_step(", "Route.tidy_step", "Route.tidy_step")
        src = wrap_after(src, "\nfunction Route.step(", "Route.step", "Route.step")
    end
    do
        local a, b = src:find("\nlocal function search_step(", 1, true)
        local e1, e2 = src:find("\nend\n", b, true)
        src = src:sub(1, e2) .. "do local raw = search_step; search_step = function(work, search) search._n = (search._n or 0) + 1; " ..
            "local o = raw(work, search); if o ~= 'continue' then _G.__P.search(work, search, o) end; return o end end\n" .. src:sub(e2 + 1)
    end
    --Trial census: how many trials, how many search steps each, how each ended.
    src = src:gsub("(local function trial_finish%(work, trial, demand%)\n)", function(h)
        return h .. "    _G.__P.count('trials'); _G.__P.count('trial_steps', trial.steps or 0)\n" ..
            "    _G.__P.count(trial.path and 'trial_path_found' or 'trial_no_path')\n" ..
            "    if (trial.steps or 0) >= 2000 then _G.__P.count('trials_over_2000_steps'); _G.__P.count('steps_in_trials_over_2000', trial.steps) end\n" ..
            "    if not trial.path then _G.__P.count('steps_in_failed_trials', trial.steps or 0) end\n"
    end, 1)
    --One line per trial: stage, steps, outcome, weights, option kind, flow, endpoints.
    if os.getenv("PROF_TRIALS") then
        local n = 0
        src = src:gsub("local weight = trial_finish%(work, st%.trial, st%.demand%)\n", function(h)
            n = n + 1
            local stage = n == 1 and "trial" or "commit"
            return h .. "            _G.__P.trial('" .. stage .. "', st, weight, #work.entities)\n"
        end)
        assert(n == 2, "trial log hooks " .. n)
    end
    return src
end

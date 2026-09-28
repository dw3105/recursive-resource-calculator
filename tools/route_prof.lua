-- Route profiler for one checkpoint. Usage is shown by running without a checkpoint.
package.path = "./?.lua;" .. package.path

local function patch_route(name, src)
    if name ~= "logic.bp.route" then return src end
    local coarse = {"route_snapshot", "restore_route_snapshot", "all_bindings_reach_sinks", "lift_binding", "binding_path",
        "route_weight", "append_normal_path", "begin_search", "search_step", "result_for", "audit_route_work",
        "restart_with_priority", "reanchor_bindings", "unbury_empty_pairs", "untangle_splitter_chains", "trial_start",
        "trial_run", "trial_finish", "fail_demand", "lay_belt_runs", "reserve_port_cells", "advance_flow_demand_build",
        "pairing_flood_step", "finish_demand_build", "append_underground", "underground_candidate"}
    local fine = {"path_cell_free", "enqueue_state", "heap_push", "heap_pop", "crossing_targets", "transition_cost",
        "route_chain_walk", "downstream_reaches_root", "search_path_tiles", "segment_allows", "bury_candidate",
        "splitter_branch_allowed", "splitter_straight_fed", "same_flow_port_tile", "reconstruct", "static_owner",
        "coordinate_key", "state_key", "coordinate_from_key"}
    local set = _G.__route_prof_set or "all"
    local names = {}
    if set ~= "fine" then for _, n in ipairs(coarse) do names[#names + 1] = n end end
    if set ~= "coarse" then for _, n in ipairs(fine) do names[#names + 1] = n end end
    if set == "fine" then names[#names + 1] = "search_step" end
    local P = {stats = {}, counts = {trials = 0, zero = 0, steps = 0, snapshots = 0, searches = 0,
        search_steps = 0, failed = 0, replayed = 0, keys = 0}}
    collectgarbage("stop")
    _G.__route_prof = P
    local depth, children = 0, {}
    for _, n in ipairs(names) do
        local head = "\nlocal function " .. n .. "("
        local _, b = src:find(head, 1, true)
        if b then
            local _, e = src:find("\nend\n", b, true)
            if e then
                local inject = "do local raw=" .. n .. "; " .. n .. "=function(...) " ..
                    "local t=os.clock(); depth=depth+1; local d=depth; children[d]=0; " ..
                    "local r={raw(...)}; local dt=os.clock()-t; local s=P.stats['" .. n .. "'] or {calls=0,incl=0,excl=0,worst=0}; " ..
                    "P.stats['" .. n .. "']=s; s.calls=s.calls+1; s.incl=s.incl+dt; s.excl=s.excl+dt-children[d]; " ..
                    "if dt>s.worst then s.worst=dt end; depth=d-1; if d>1 then children[d-1]=children[d-1]+dt end; return (table.unpack or unpack)(r) end end\n"
                src = src:sub(1, e) .. inject .. src:sub(e + 1)
            end
        end
    end
    -- The source wrapper closes over this state through its environment.
    src = "local P,depth,children=_G.__route_prof,0,{}\n" .. src
    -- Count route searches, their expanded states, and temporary Lua memory.
    local a, b = src:find("\nlocal function search_step(", 1, true)
    if a then
        local _, e = src:find("\nend\n", b, true)
        local wrap = [[
do local raw=search_step; search_step=function(work,search)
 local before=collectgarbage("count"); local result=raw(work,search); local after=collectgarbage("count")
 local c=_G.__route_prof.counts; c.search_steps=c.search_steps+1; c.garbage=(c.garbage or 0)+(after-before)
 if c.search_steps%20000==0 then collectgarbage("collect"); collectgarbage("stop") end
 if result~="continue" then c.searches=c.searches+1; if result=="failed" then c.failed=c.failed+1 end
 if search.order_index and search.order_index>1 then c.replayed=c.replayed+1 end end
 return result end end
]]
        src = src:sub(1, e) .. wrap .. src:sub(e + 1)
    end
    local needle = "local function trial_finish(work, trial, demand)"
    local _, te = src:find(needle, 1, true)
    if te then src = src:sub(1, te) .. " _G.__route_prof.counts.trials=_G.__route_prof.counts.trials+1; _G.__route_prof.counts.steps=_G.__route_prof.counts.steps+(trial.steps or 0); if (trial.steps or 0)==0 then _G.__route_prof.counts.zero=_G.__route_prof.counts.zero+1 end\n" .. src:sub(te + 1) end
    local sn = "local function route_snapshot(work)"
    local _, se = src:find(sn, 1, true)
    if se then src = src:sub(1, se) .. " _G.__route_prof.counts.snapshots=_G.__route_prof.counts.snapshots+1\n" .. src:sub(se + 1) end
    local kn = "local function coordinate_key("; local _, ke = src:find(kn, 1, true)
    if ke then src = src:sub(1, ke) .. " _G.__route_prof.counts.keys=_G.__route_prof.counts.keys+1\n" .. src:sub(ke + 1) end
    return src
end

if _G.__ROUTE_PROF_LOADING then
    return function(name, src)
        if _G.__route_prof_user_patch then src = assert(_G.__route_prof_user_patch(name, src)) end
        return patch_route(name, src)
    end
end

local checkpoint = arg[1]
if not checkpoint or checkpoint:sub(1, 2) == "--" then
    io.write("usage: lua5.2 tools/route_prof.lua <checkpoint.lua.gz> [--until <at-spec>] [--set coarse|fine|all] [--patch f.lua]\n")
    os.exit(2)
end
local options, i = {}, 2
while i <= #arg do
    local key = arg[i]
    if key == "--until" or key == "--set" or key == "--patch" then options[key] = arg[i + 1]; i = i + 2
    else error("unknown option " .. tostring(key)) end
end
if options["--set"] and options["--set"] ~= "coarse" and options["--set"] ~= "fine" and options["--set"] ~= "all" then error("--set must be coarse, fine, or all") end
_G.__route_prof_set = options["--set"] or "all"
if options["--patch"] then _G.__route_prof_user_patch = assert(loadfile(options["--patch"]))() end
local captured, original_write = {}, io.write
io.write = function(...) local s = {}; for j = 1, select("#", ...) do s[j] = tostring(select(j, ...)) end; captured[#captured + 1] = table.concat(s) end
_G.__ROUTE_PROF_LOADING = true
arg = {[0] = "tools/ckpt.lua", "resume", checkpoint}
if options["--until"] then arg[#arg + 1] = "--until"; arg[#arg + 1] = options["--until"] end
arg[#arg + 1] = "--patch"; arg[#arg + 1] = "tools/route_prof.lua"
dofile("tools/ckpt.lua")
io.write = original_write
local output = table.concat(captured)
local P = _G.__route_prof or {stats = {}, counts = {}}
local rows = {}
for name, stat in pairs(P.stats) do rows[#rows + 1] = {name = name, stat = stat} end
table.sort(rows, function(a, b) return a.stat.incl > b.stat.incl end)
io.write("== functions\nname calls incl s excl s worst ms\n")
for _, row in ipairs(rows) do local s = row.stat; io.write(string.format("%s %d %.6f %.6f %.3f\n", row.name, s.calls, s.incl, s.excl, s.worst * 1000)) end
local c = P.counts
io.write(string.format("== trials\nrun=%d zero-step=%d steps=%d snapshots=%d\n", c.trials or 0, c.zero or 0, c.steps or 0, c.snapshots or 0))
io.write(string.format("== searches\ncount=%d steps=%d failed floods=%d order_index > 1=%d\n", c.searches or 0, c.search_steps or 0, c.failed or 0, c.replayed or 0))
local kb = (c.search_steps or 0) > 0 and (c.garbage or 0) / c.search_steps or 0
io.write(string.format("== garbage\n%.6f kb per search step\n", kb))
local ratio = (c.search_steps or 0) > 0 and (c.keys or 0) / c.search_steps or 0
io.write(string.format("== keys\ncoordinate_key calls per search step=%.6f\n", ratio))
local endline = output:match("END ok=[^\n]+") or "END ticks=0 sha=unknown entities=0"
local ticks = endline:match("ticks=(%d+)") or "0"
local sha = endline:match("sha=(%w+)") or "unknown"
local entities = endline:match("entities=(%d+)") or "0"
io.write(string.format("END ticks=%s sha=%s entities=%s\n", ticks, sha, entities))

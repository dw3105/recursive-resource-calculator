-- Strict re-route (in memory): B1/B2/B3' fire only when route work.strict_ends; search re-runs the same grid once
-- with strict_ends after validate refuses a candidate for a route-shape code.
local F2 = assert(loadfile((os.getenv("R49P") or "docs/tasks/r49_probes") .. "/f2_fix.lua"))()
local F3 = assert(loadfile((os.getenv("R49P") or "docs/tasks/r49_probes") .. "/f3b_fix.lua"))()
local function sub(src, a, b, tag) local i, j = src:find(a, 1, true); assert(i, "missing " .. tag); return src:sub(1, i - 1) .. b .. src:sub(j + 1) end
return function(name, src)
  if name == "logic.bp.route" then
    src = F3(name, F2(name, src))
    src = sub(src, "and heading ~= demand.sink.travel_dir and (demand.sink.row_port or demand.sink.perimeter) then",
                   "and heading ~= demand.sink.travel_dir and work.strict_ends and (demand.sink.row_port or demand.sink.perimeter) then", "B2 gate")
    src = sub(src, "if other and other_flow == nil and other.flow_ids then", "if other and other_flow == nil and other.flow_ids and work.strict_ends then", "B1 gate")
    src = sub(src, "elseif work.improve_state ~= nil and segment_has_flow(other, demand.flow_id) then",
                   "elseif work.strict_ends and work.improve_state ~= nil and segment_has_flow(other, demand.flow_id) then", "B3 gate")
    src = sub(src, "collectors = input.collectors ~= false, collectors_used = false,",
                   "collectors = input.collectors ~= false, collectors_used = false, strict_ends = input.strict_ends == true,", "work field")
    io.write("STRICT route live\n")
  elseif name == "logic.bp.search" then
    src = sub(src, "local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)",
      "local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)\n                    if route_input and state.work.strict_ends then route_input.strict_ends = true end", "search route input")
    src = sub(src, [[                    record_rejection(state, state.work.validate.errors, "validate")
                    discard_candidate(state)]],
      [[                    record_rejection(state, state.work.validate.errors, "validate")
                    local shape = false
                    for _, e in ipairs(state.work.validate.errors or {}) do
                        local c = e.code
                        if c == "BP_V_BELT_BLEED" or c == "BP_V_UNDERGROUND_SIDELOAD_BLOCKED" or c == "BP_V_ROUTE_DISCONTINUOUS"
                            or c == "BP_V_ROUTE_LOOP" or c == "BP_V_BELT_NO_SOURCE" or c == "BP_V_TRANSPORT_UNUSED" then shape = true; break end
                    end
                    if shape and not state.work.strict_ends and state.work.collector_trial == nil then
                        io.write("STRICT redo grid=", tostring(state.cursor.grid_index), " tick=", tostring(_G.__ckpt_tick), "\n"); io.flush()
                        state.work.strict_ends = true
                        start_grid(state)
                    else
                        state.work.strict_ends = nil
                        discard_candidate(state)
                    end]], "search validate branch")
    io.write("STRICT search live\n")
  end
  return src
end

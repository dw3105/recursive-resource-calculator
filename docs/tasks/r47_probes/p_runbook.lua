-- lay_belt_runs books only demands whose run-side endpoint touches this run (head +-1, run tile, feed side tile);
-- a flow with no touching demand keeps the old whole-flow booking.
return function(name, src)
  if name ~= "logic.bp.route" then return src end
  local old = [[                for _, flow_id in ipairs(run.flows or {}) do
                    register_segment_flow(work, segment, flow_id)
                    for _, demand in ipairs(work.demands or {}) do
                        local endpoint = run.role == "in" and demand.sink or demand.source
                        if not run.synthetic_collector and demand.flow_id == flow_id and endpoint and endpoint.step_id ~= "$external" then]]
  local new = [[                for _, flow_id in ipairs(run.flows or {}) do
                    register_segment_flow(work, segment, flow_id)
                    local touching = {}
                    do
                        local near = {}
                        local function mark(x, y) if x and y then near[coordinate_key(x, y)] = true end end
                        if run.head then for dx = -1, 1 do for dy = -1, 1 do if dx == 0 or dy == 0 then mark(run.head.x + dx, run.head.y + dy) end end end end
                        for _, t in ipairs(run.tiles or {}) do mark(t.x, t.y) end
                        for _, t in ipairs({(run.tiles or {})[1], (run.tiles or {})[#(run.tiles or {})]}) do
                            if t then mark(t.x + 1, t.y); mark(t.x - 1, t.y); mark(t.x, t.y + 1); mark(t.x, t.y - 1) end
                        end
                        for _, fd in ipairs(run.feeds or {}) do if fd.side_tile then mark(fd.side_tile.x, fd.side_tile.y) end end
                        local any = false
                        for _, demand in ipairs(work.demands or {}) do
                            local endpoint = run.role == "in" and demand.sink or demand.source
                            if demand.flow_id == flow_id and endpoint and endpoint.x and near[coordinate_key(endpoint.x, endpoint.y)] then touching[demand] = true; any = true end
                        end
                        if not any then touching = nil end
                    end
                    for _, demand in ipairs(work.demands or {}) do
                        local endpoint = run.role == "in" and demand.sink or demand.source
                        if not run.synthetic_collector and demand.flow_id == flow_id and endpoint and endpoint.step_id ~= "$external"
                            and (touching == nil or touching[demand]) then]]
  local a, b = src:find(old, 1, true); assert(a, "lay_belt_runs anchor")
  io.stderr:write("PATCH runbook on\n")
  return src:sub(1, a - 1) .. new .. src:sub(b + 1)
end

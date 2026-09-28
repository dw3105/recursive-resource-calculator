-- RunDir.choose: a flipped row port and its exit tile must not sit on a roboport/obstacle rect
return function(name, src)
  local function rep(a, b) local i, j = src:find(a, 1, true); assert(i, a); src = src:sub(1, i - 1) .. b .. src:sub(j + 1) end
  if name == "logic.bp.run_dir" then
    rep("function RunDir.choose(block, placement, all_blocks, all_placements, grid, flows, input_edge, output_edge)",
        "function RunDir.choose(block, placement, all_blocks, all_placements, grid, flows, input_edge, output_edge, obstacles)")
    rep("                                    if tile.x < 1 or tile.y < 1 or tile.x >= grid.w - 1 or tile.y >= grid.h - 1 then valid = false end",
        [[                                    if tile.x < 1 or tile.y < 1 or tile.x >= grid.w - 1 or tile.y >= grid.h - 1 then valid = false end
                                    for _, ob in ipairs(obstacles or {}) do
                                        local r = ob.rect or ob
                                        if r.x and tile.x >= r.x and tile.y >= r.y and tile.x < r.x + (r.w or 1) and tile.y < r.y + (r.h or 1) then
                                            valid = false; __RUNDIR = (__RUNDIR or 0) + 1
                                        end
                                    end]])
    io.stderr:write("PATCH rundir on\n")
  elseif name == "logic.bp.search" then
    rep("                state.work.plan_result.flows, input_edge, output_edge)\n            local placed = Groups.materialize(block, placement)",
        "                state.work.plan_result.flows, input_edge, output_edge, state.work.robo_obstacles)\n            local placed = Groups.materialize(block, placement)")
  end
  return src
end

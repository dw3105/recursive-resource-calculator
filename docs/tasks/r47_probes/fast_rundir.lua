-- seconds: RunDir.choose over all pack placements of a checkpoint; PATCHES applied to run_dir; prints flips + exit tiles on obstacles
package.path = "./?.lua;" .. package.path
local t0 = os.clock()
local st = require("tools.lib.graph_dump").load(arg[1]).state
local w = st.work
local PL = {}; for p in (os.getenv("PATCHES") or ""):gmatch("[^,]+") do PL[#PL+1] = assert(loadfile(p))() end
local src = io.open("logic/bp/run_dir.lua"):read("*a"); for _, f in ipairs(PL) do src = f("logic.bp.run_dir", src) end
local RunDir = assert(load(src, "@run_dir"))()
local Grid = require "logic.bp.grid"
local cand, pl = w.candidate, w.pack.result.placements
local by_id, order = {}, {}
for _, p in ipairs(pl) do by_id[p.block_id or p.id] = p end
for _, b in ipairs(cand.blocks) do order[#order+1] = by_id[b.id or b.block_id] end
local set = w.input.settings or {}
local flips, bad = 0, 0
local function on_ob(x, y) for _, o in ipairs(w.robo_obstacles or {}) do local r = o.rect or o; if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then return true end end end
for _, b in ipairs(cand.blocks) do
  local p = by_id[b.id or b.block_id]
  if p and b.row then
    local r = RunDir.choose(b, p, cand.blocks, order, w.grid, w.plan_result.flows, set.input_edge or "left", set.output_edge or "top", w.robo_obstacles)
    if r ~= b then flips = flips + 1 end
    for _, port in ipairs(r.ports or {}) do if port.row_port and port.role == "out" and port.travel_dir then
      local q = Grid.place_port(r, p, port); local vx, vy = Grid.dir_vector(Grid.rotate_dir(port.travel_dir, p.dir))
      local ex, ey = q.x + vx, q.y + vy
      local hit = on_ob(ex, ey)
      if hit then bad = bad + 1 end
      print(string.format("%-40s flipped=%-5s out=(%d,%d) exit=(%d,%d)%s", tostring(b.id or b.block_id), tostring(r ~= b), q.x, q.y, ex, ey, hit and " ON-ROBOPORT" or ""))
    end end
  end
end
print(string.format("FLIPS=%d EXIT_ON_ROBOPORT=%d cpu=%.1fs", flips, bad, os.clock() - t0))

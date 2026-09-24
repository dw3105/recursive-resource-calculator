-- Print the placements of the FIRST pack run on a golden input, one line per block, then exit (round 30).
-- Usage (repo root): lua5.2 tools/pack_placements.lua tests/golden/cases/<case>/prepared_input.json
-- Lines: PLACE <block_id> x=<x> y=<y> dir=<d> w=<w> h=<h> slots=<attach_dx,attach_dy,travel_dir;...>
--        PACK-CPU <seconds> origins=<n>
package.path = "./?.lua;./?/init.lua;" .. package.path
local Pack = require "logic.bp.pack"
local step, t = Pack.step, 0
Pack.step = function(state, budget)
  local c = os.clock(); local r = step(state, budget); t = t + os.clock() - c
  if state.done then
    for _, p in ipairs(state.placements or {}) do
      local slots = {}
      for _, s in ipairs(p.port_slots or {}) do
        slots[#slots + 1] = tostring(s.attach_dx) .. "," .. tostring(s.attach_dy) .. "," .. tostring(s.travel_dir)
      end
      print(string.format("PLACE %s x=%s y=%s dir=%s w=%s h=%s slots=%s", tostring(p.block_id), tostring(p.x),
        tostring(p.y), tostring(p.dir), tostring(p.w), tostring(p.h), table.concat(slots, ";")))
    end
    print(string.format("PACK-CPU %.2f origins=%s ok=%s", t, tostring(state.counters and state.counters.origins), tostring(state.ok)))
    os.exit(0)
  end
  return r
end
arg = {[0] = "tests/golden/generate.lua", "--input", arg[1], "--output", "/dev/null"}
dofile("tests/golden/generate.lua")

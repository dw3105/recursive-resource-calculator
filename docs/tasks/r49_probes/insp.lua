package.path = "./?.lua;" .. package.path
local Graph = require "tools.lib.graph_dump"
local d = Graph.load(arg[1]); local st = d.state; local w = st.work or {}
print("tick", d.meta.tick, "phase", st.phase, "grid", st.cursor and st.cursor.grid_index, "attempt", w.attempt, "layered_off", tostring(w.layered_off))
for i, r in ipairs(w.rejections or {}) do
  local parts = {}
  for k, v in pairs(r) do if type(v) ~= "table" then parts[#parts+1] = k .. "=" .. tostring(v) end end
  table.sort(parts)
  local e = r.errors and r.errors[1]
  print(i, table.concat(parts, " "), e and (tostring(e.code) .. " " .. tostring(e.block_id or "") .. " " .. tostring(e.ids and table.concat(e.ids, ",") or "")) or "")
end

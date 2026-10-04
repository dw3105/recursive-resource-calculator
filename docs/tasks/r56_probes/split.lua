-- LUA_INIT=@split.lua with tools/ckpt.lua (RRC_GAME_TICK=1): per game tick, CPU in Groups.step / Pack.step /
-- rest, printed for ticks over SPLIT_MS. Groups ticks also name the bucket built (step ids, machine count).
package.path = "./?.lua;" .. package.path
local thr = tonumber(os.getenv("SPLIT_MS") or "30") / 1000
local G, Pk = require "logic.bp.groups", require "logic.bp.pack"
local acc = {g = 0, p = 0, gc = 0, pc = 0, info = nil}
local cur, t0 = nil, os.clock()
local function flush(now)
  if cur and now - t0 >= thr then
    local st = _G.__ckpt_last_state
    io.stderr:write(string.format("TICK %d ms=%.0f groups=%.0f(%d) pack=%.0f(%d) rest=%.0f phase=%s grid=%s %s\n", cur,
      (now - t0) * 1000, acc.g * 1000, acc.gc, acc.p * 1000, acc.pc, (now - t0 - acc.g - acc.p) * 1000,
      st and tostring(st.phase) or "?", st and st.cursor and tostring(st.cursor.grid_index) or "?", acc.info or ""))
  end
  acc = {g = 0, p = 0, gc = 0, pc = 0}
end
local function tick() local t = _G.__ckpt_tick; if t ~= cur then local now = os.clock(); flush(now); cur, t0 = t, now end end
local gs, ps = G.step, Pk.step
G.step = function(s, b)
  tick(); local w = s.work and s.work.build; local bi = w and w.bucket_index; local grp = w and w.buckets and bi and w.buckets[bi]
  local t = os.clock(); local r = gs(s, b); local d = os.clock() - t; acc.g = acc.g + d; acc.gc = acc.gc + 1
  if grp and d > 0.02 then local ids, m = {}, 0; for _, st in ipairs(grp) do ids[#ids + 1] = tostring(st.step_id); m = m + math.max(1, st.machine_count or 1) end
    if os.getenv("BUCKETS") then io.stderr:write(string.format("BUCKET tick=%s ms=%.0f bucket=%d/%d machines=%d steps=%s\n", tostring(_G.__ckpt_tick), d*1000, bi, #w.buckets, m, table.concat(ids, "+"))) end
    acc.info = string.format("bucket=%d/%d steps=%s machines=%d", bi, #w.buckets, table.concat(ids, "+"), m) end
  return r end
Pk.step = function(s, b) tick(); local t = os.clock(); local r = ps(s, b); acc.p = acc.p + os.clock() - t; acc.pc = acc.pc + 1; return r end
local exit = os.exit; os.exit = function(...) flush(os.clock()); return exit(...) end

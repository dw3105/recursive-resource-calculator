-- LUA_INIT=@spike.lua with tools/ckpt.lua (RRC_GAME_TICK=1). Per game tick (_G.__ckpt_tick) sums CPU by
-- sampled stack. A tick over SPIKE_MS prints: SPIKE tick phase ms, then top self lines and top inclusive functions.
local clock, getinfo = os.clock, debug.getinfo
local thr = tonumber(os.getenv("SPIKE_MS") or "100") / 1000
local cur_tick, tick_t, last = nil, 0, clock()
local selfl, incl = {}, {}
local seen = {}
local function flush()
  if cur_tick and tick_t >= thr then
    local ph = _G.__ckpt_last_state and tostring(_G.__ckpt_last_state.phase) or "?"
    io.stderr:write(string.format("SPIKE tick=%s phase=%s ms=%.0f\n", tostring(cur_tick), ph, tick_t * 1000))
    for _, tb in ipairs({{"SELF", selfl, 8}, {"INCL", incl, 14}}) do
      local ks = {}; for k, v in pairs(tb[2]) do ks[#ks + 1] = k end
      table.sort(ks, function(a, b) return tb[2][a] > tb[2][b] end)
      for i = 1, math.min(tb[3], #ks) do io.stderr:write(string.format("  %s %5.0f %s\n", tb[1], tb[2][ks[i]] * 1000, ks[i])) end
    end
  end
  selfl, incl, tick_t = {}, {}, 0
end
local function hook()
  local now = clock(); local dt = now - last; last = now
  local t = _G.__ckpt_tick
  if t ~= cur_tick then flush(); cur_tick = t end
  if not t then return end
  tick_t = tick_t + dt
  local i = getinfo(2, "Sl"); if not i then return end
  local k = i.short_src .. ":" .. (i.currentline or 0)
  selfl[k] = (selfl[k] or 0) + dt
  for kk in pairs(seen) do seen[kk] = nil end
  for lvl = 2, 60 do
    local j = getinfo(lvl, "Sl"); if not j then break end
    if j.short_src:find("logic/") then
      local kj = j.short_src .. ":" .. (j.linedefined or 0) .. "@" .. (j.currentline or 0)
      local kf = j.short_src .. ":fn" .. (j.linedefined or 0)
      if not seen[kf] then seen[kf] = true; incl[kj] = (incl[kj] or 0) + dt end
    end
  end
end
local exit = os.exit; os.exit = function(...) flush(); return exit(...) end
debug.sethook(hook, "", tonumber(os.getenv("SAMPLE_N") or "2000"))

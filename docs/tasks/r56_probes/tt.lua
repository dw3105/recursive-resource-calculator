-- LOCAL PROBE ticket 06 tail: VM instruction count per game tick (count hook every TT_N instr) + stack sampler.
-- env: TT_OUT file (append), TT_N (1000), TT_WALK (every k-th fire walks stack; 0 = count only), TT_KEEP (instr; ticks
-- at or above keep their stack samples). Hook instructions are not counted (Lua 5.2 disables hooks inside a hook).
local N=tonumber(os.getenv("TT_N") or "1000")
local WALK=tonumber(os.getenv("TT_WALK") or "5")
local KEEP=tonumber(os.getenv("TT_KEEP") or "150000")
local out=assert(io.open(assert(os.getenv("TT_OUT"),"TT_OUT"),"a"))
local getinfo=debug.getinfo
local SFMT=string.format
local fires, f0, cur, k = 0, 0, nil, 0
local function walk()
  local parts, n, lvl = {}, 0, 2
  while n < 16 do
    local i = getinfo(lvl, "Sl"); if not i then break end
    local s = i.short_src
    if s:sub(1,6) == "logic/" then
      n = n + 1
      parts[n] = s:sub(7, -5) .. ":" .. i.linedefined .. (n == 1 and ("@" .. i.currentline) or "")
    end
    lvl = lvl + 1
  end
  return n > 0 and table.concat(parts, "<") or "(none)"
end
local function hook()
  fires = fires + 1
  if cur and WALK > 0 then
    k = k + 1
    if k >= WALK then k = 0; local sg = walk(); cur[sg] = (cur[sg] or 0) + 1 end
  end
end
local CC=os.getenv("TT_CCALL")=="1"
local cc, cc0, ts, ts0 = 0, 0, 0, 0
local TOSTR, FMT = tostring, string.format
if CC then
  -- C-call counter mode: counts calls into C functions; instruction counts in this mode are inflated, use count-only runs
  debug.sethook(function(ev) if ev == "call" or ev == "tail call" then local i = getinfo(2, "Sf"); if i and i.what == "C" then cc = cc + 1; if i.func == TOSTR or i.func == FMT then ts = ts + 1 end end end end, "c")
else
  debug.sethook(hook, "", N)
end
local nts, nfm, nts0, nfm0 = 0, 0, 0, 0
if os.getenv("TT_WRAP") == "1" then
  -- count tostring / string.format calls with Lua wrappers (fixed instructions per call, subtracted in analysis)
  local TS, SF = tostring, string.format
  tostring = function(v) nts = nts + 1; return TS(v) end
  string.format = function(...) nfm = nfm + 1; return SF(...) end
end
local U = {}            -- per tick: name -> {n, max_ms, tot_ms, max_instr, max_ts}
local AI, AT = 20.28e-6, 1.58e-3   -- pooled 4-sheet fit: ms per instr, ms per tostring call
local function urec(name, d, dt)
  local ms = AI * d + AT * dt
  local u = U[name]; if not u then u = {0, 0, 0, 0, 0}; U[name] = u end
  u[1] = u[1] + 1; u[3] = u[3] + ms; if ms > u[2] then u[2], u[4], u[5] = ms, d, dt end
end
_G.__TTR = {}
_G.__ttu0 = function() return fires, nts end
_G.__ttu1 = function(name, f0, t0, ...) urec(name, (fires - f0) * N, nts - t0); return ... end
local mname, mf, mt
_G.__ttm = function(name) if mname then urec(mname, (fires - mf) * N, nts - mt) end; mname, mf, mt = name, fires, nts end
local function mclose() if mname then urec(mname, (fires - mf) * N, nts - mt) end; mname = nil end
local tticks=0
local ALLOC=os.getenv("TT_ALLOC")=="1"
local m0=0
_G.__tt = {
  begin = function(tick, ph) mclose(); U = {}; if ALLOC then collectgarbage("stop"); m0 = collectgarbage("count") end; f0 = fires; cc0 = cc; ts0 = ts; nts0 = nts; nfm0 = nfm; cur = {}; k = 0 end,
  finish = function(tick, ph0, ph1, dt, calls)
    local instr = (fires - f0) * N
    local kb = 0; if ALLOC then kb = collectgarbage("count") - m0; collectgarbage("restart") end
    out:write(SFMT("T %d %s %s %d %.3f %d %d %d %d %d %d\n", tick, ph0, ph1, instr, dt * 1000, calls, kb, cc - cc0, ts - ts0, nts - nts0, nfm - nfm0))
    mclose()
    for nm, u in pairs(U) do if u[3] >= 1 then out:write(SFMT("U %d %s %d %.2f %.2f %d %d\n", tick, nm, u[1], u[2], u[3], u[4], u[5])) end end
    if instr >= KEEP and cur then
      for sg, c in pairs(cur) do out:write(SFMT("S %d %d %s\n", tick, c * WALK * N, sg)) end
    end
    cur = nil; tticks = tticks + 1; if tticks % 50 == 0 then out:flush() end
  end,
}

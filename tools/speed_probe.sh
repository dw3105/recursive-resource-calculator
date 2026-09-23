#!/bin/sh
# In-game speed probe for the player's sheet.  The game advances a blueprint search on_tick with
# Jobs.OPS_PER_TICK = 2000 ops (logic/jobs.lua).  This drives Search.step exactly so and times:
#   SPEED line : ticks, total CPU, worst single tick, done/ok, entities when done
#   MOD lines  : every begin/step of plan, groups, pack, route, power, validate, serialize -- calls, CPU, worst call
# It stops after CAP seconds of CPU (default 40) and says CAP, or END when the search finished.
# Measured 2026-09-23 on legalcopilot-dev at 59e31ff, CAP=40: not done; worst pack.step 8.157 s,
# route.begin 1.340 s, route.step 0.783 s, groups.begin 0.611 s; power.step 1997 calls.
# Usage (repository root): CAP=40 sh tools/speed_probe.sh
CAP=${CAP:-40} INPUT=${INPUT:-tests/golden/cases/player-red-science-1s/prepared_input.json} lua5.2 -e '
package.path = "./?.lua;./?/init.lua;" .. package.path
local stats, cpu0 = {}, os.clock()
local function wrap(modname)
  local M = require(modname)
  for _, fname in ipairs({"begin", "step"}) do
    local f = M[fname]
    if type(f) == "function" then
      local key = modname:gsub("logic%.bp%.", "") .. "." .. fname
      M[fname] = function(...)
        local t = os.clock(); local a, b, c = f(...); local d = os.clock() - t
        local s = stats[key] or {n = 0, t = 0, w = 0}; stats[key] = s
        s.n, s.t = s.n + 1, s.t + d; if d > s.w then s.w = d end
        return a, b, c
      end
    end
  end
end
for _, m in ipairs({"logic.bp.plan", "logic.bp.groups", "logic.bp.pack", "logic.bp.route", "logic.bp.power",
    "logic.bp.validate", "logic.bp.serialize"}) do wrap(m) end
local S = require "logic.bp.search"
local step = S.step
local cap, ticks, worst = tonumber(os.getenv("CAP")), 0, 0
local function report(tag, state)
  local entities = state.result and state.result.entities and #state.result.entities or 0
  io.stdout:write(string.format("SPEED %s ticks=%d cpu=%.2f worst_tick=%.3f done=%s ok=%s entities=%d\n", tag, ticks,
    os.clock() - cpu0, worst, tostring(state.done), tostring(state.ok), entities))
  local keys = {}; for k in pairs(stats) do keys[#keys + 1] = k end; table.sort(keys)
  for _, k in ipairs(keys) do local s = stats[k]
    io.stdout:write(string.format("MOD %s calls=%d cpu=%.2f worst=%.3f\n", k, s.n, s.t, s.w)) end
  io.stdout:flush()
end
S.step = function(state, budget)
  budget.ops = 2000; ticks = ticks + 1
  local t = os.clock(); local r = step(state, budget); local d = os.clock() - t
  if d > worst then worst = d end
  if state.done then report("END", state); os.exit(0) end
  if os.clock() - cpu0 > cap then report("CAP", state); os.exit(0) end
  return r
end
arg = {[0] = "tests/golden/generate.lua", "--input", os.getenv("INPUT"), "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
' 2>/dev/null

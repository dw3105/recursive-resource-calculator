-- Profile one generation of the player's sheet as the game runs it: Search.step once per tick with 2000 ops
-- (logic/jobs.lua OPS_PER_TICK). Attributes each tick's CPU to the search phase it started in, splits route into
-- first routing vs improve pass, and candidates into ordinary vs flip trials (id contains ":flip:").
-- Usage (repo root): lua5.2 ~/.claude/plans/rrc-round-22-probes/profile.lua [input.json]
package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require "logic.bp.search"
local step = S.step
local cpu0, ticks, worst, worst_where = os.clock(), 0, 0, ""
local by, order = {}, {}
local first
local function add(key, d)
  local s = by[key]; if not s then s = {n = 0, t = 0, w = 0}; by[key] = s; order[#order + 1] = key end
  s.n, s.t = s.n + 1, s.t + d; if d > s.w then s.w = d end
end
local function where(st)
  local w = st and st.work or {}
  local phase = tostring(st and st.phase)
  local cand = w.candidate and tostring(w.candidate.id or "") or ""
  local kind = cand:find(":flip:", 1, true) and "flip-trial" or "candidate"
  if phase == "route" then
    local r = w.route and w.route.work
    phase = (r and (r.improve_state ~= nil or (r.demands and r.demands[(w.route.cursor or {}).demand_index or 1] == nil))) and "route.improve" or "route.first"
  end
  if phase == "plan" or phase == "preflight" or phase == "groups" or phase == "serialize" then return phase end
  return phase .. " (" .. kind .. ")"
end
local function report(state)
  local total = os.clock() - cpu0
  print(string.format("TOTAL ticks=%d (%.1f s game time at 60 UPS) cpu=%.2f s worst_tick=%.3f s [%s] ok=%s entities=%d",
    ticks, ticks / 60, total, worst, worst_where, tostring(state.ok), state.result and state.result.entities and #state.result.entities or 0))
  if first then print(string.format("FIRST valid layout: tick %d (%.1f s game time), cpu %.2f s, %s entities", first.t, first.t / 60, first.c, tostring(first.e))) end
  table.sort(order, function(a, b) return by[a].t > by[b].t end)
  print(string.format("%-28s %7s %9s %6s %9s", "phase", "ticks", "cpu s", "share", "worst s"))
  for _, k in ipairs(order) do
    local s = by[k]
    print(string.format("%-28s %7d %9.2f %5.1f%% %9.3f", k, s.n, s.t, 100 * s.t / total, s.w))
  end
end
S.step = function(state, budget)
  budget.ops = 2000; ticks = ticks + 1
  local key = where(state.state or state)
  local t = os.clock(); local r = step(state, budget); local d = os.clock() - t
  add(key, d)
  if d > worst then worst, worst_where = d, key end
  local st = state.state or state
  if not first and type(st.interim) == "table" and st.interim.result ~= nil then
    first = {t = ticks, c = os.clock() - cpu0, e = st.interim.entities}
  end
  if st.done or state.done then report(st); os.exit(0) end
  return r
end
arg = {[0] = "tests/golden/generate.lua", "--input", arg[1] or "tests/golden/cases/player-red-science-1s/prepared_input.json", "--output", "/dev/null"}
dofile("tests/golden/generate.lua")

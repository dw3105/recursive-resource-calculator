-- LUA_INIT=@fp.lua with tools/ckpt.lua save (RRC_GAME_TICK=1): every Groups run (one per grid start) prints
-- sha256 of its input minus `grid` and of its result, plus the first differing paths against the first run.
-- SAMPLE=1: count-hook sampler inside build_block (groups.lua), CPU split by direct sub-call (linedefined).
package.path = "./?.lua;" .. package.path
local G = require "logic.bp.groups"
local dir = os.getenv("FP_DIR") or "/tmp"
local function ser(v, out, seen)
  local t = type(v)
  if t == "table" then
    if seen[v] then out[#out + 1] = "<cyc>"; return end
    seen[v] = true
    local ks = {}; for k in pairs(v) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) local ta, tb = type(a), type(b); if ta ~= tb then return ta < tb end; return a < b end)
    out[#out + 1] = "{"
    for _, k in ipairs(ks) do out[#out + 1] = tostring(k) .. "="; ser(v[k], out, seen); out[#out + 1] = "," end
    out[#out + 1] = "}"; seen[v] = nil
  elseif t == "number" then out[#out + 1] = string.format("%.17g", v)
  elseif t == "string" then out[#out + 1] = string.format("%q", v)
  elseif t == "function" then out[#out + 1] = "<fn>"
  else out[#out + 1] = tostring(v) end
end
local function sha(v)
  local out = {}; ser(v, out, {}); local s = table.concat(out)
  local p = dir .. "/fp.tmp"; local f = assert(io.open(p, "wb")); f:write(s); f:close()
  local h = assert(io.popen("sha256sum " .. p)):read("*l"):sub(1, 12); return h, #s
end
local function diff(a, b, path, acc, seen)
  if #acc >= tonumber(os.getenv("FP_DIFF_MAX") or "12") then return end
  if type(a) ~= "table" or type(b) ~= "table" then
    if a ~= b and not (a ~= a and b ~= b) then acc[#acc + 1] = path .. ": " .. tostring(a) .. " -> " .. tostring(b) end
    return
  end
  if seen[a] then return end; seen[a] = true
  local ks = {}; for k in pairs(a) do ks[k] = true end; for k in pairs(b) do ks[k] = true end
  local l = {}; for k in pairs(ks) do l[#l + 1] = k end
  table.sort(l, function(x, y) return tostring(x) < tostring(y) end)
  for _, k in ipairs(l) do diff(a[k], b[k], path .. "." .. tostring(k), acc, seen) end
end
local function copy(v, seen) seen = seen or {}; if type(v) ~= "table" then return v end; if seen[v] then return seen[v] end
  local r = {}; seen[v] = r; for k, x in pairs(v) do r[copy(k, seen)] = copy(x, seen) end; return r end

local runs, first_in, first_out = 0, nil, nil
local gb, gs = G.begin, G.step
G.begin = function(input)
  local st = gb(input); st.__fp = {t = 0}; return st
end
-- sampler
local samp = {}; local sampling = os.getenv("SAMPLE"); local TARGET = tonumber(os.getenv("TARGET") or "1360")
local function hook()
  local lvl, prev = 2, nil
  while true do
    local i = debug.getinfo(lvl, "Sl"); if not i then return end
    if i.linedefined == TARGET and i.short_src:find("groups.lua", 1, true) then
      local key = prev and ("call@" .. prev) or ("self@" .. tostring(i.currentline))
      samp[key] = (samp[key] or 0) + 1; samp.__bb = (samp.__bb or 0) + 1; return
    end
    if i.short_src:find("groups.lua", 1, true) or i.short_src:find("logic/bp", 1, true) then prev = (i.short_src:match("[^/]+$")) .. ":" .. i.linedefined end
    lvl = lvl + 1
  end
end
G.step = function(s, b)
  local was = s.done
  if sampling then debug.sethook(function() samp.__all = (samp.__all or 0) + 1; hook() end, "", 1000) end
  local t = os.clock(); local r = gs(s, b); local d = os.clock() - t
  if sampling then debug.sethook() end
  if s.__fp then s.__fp.t = s.__fp.t + d end
  if not was and s.done and s.__fp then
    runs = runs + 1
    local inp = s.work.input; local grid = inp.grid; inp.grid = nil
    local ih, il = sha(inp); local oh, ol = sha(s.result)
    inp.grid = grid
    local gw = grid and (tostring(grid.width or grid.w) .. "x" .. tostring(grid.height or grid.h)) or "?"
    local ss = {}; for k, v in pairs(inp.split_steps or {}) do ss[#ss + 1] = k .. "=" .. v end; table.sort(ss)
    io.stderr:write(string.format("GROUPS run=%d tick=%s grid_index=%s grid=%s ring_bump=%s split=%s in=%s(%d) out=%s(%d) blocks=%d ms=%.0f\n",
      runs, tostring(_G.__ckpt_tick), tostring(_G.__ckpt_last_state and _G.__ckpt_last_state.cursor and _G.__ckpt_last_state.cursor.grid_index),
      gw, tostring(inp.ring_bump), table.concat(ss, ";"), ih, il, oh, ol,
      #((s.result.candidates or {})[1] or {blocks = {}}).blocks, s.__fp.t * 1000))
    if not first_out then first_in, first_out = copy(inp), copy(s.result); first_in.grid = nil
    else
      local a = {}; local g2 = inp.grid; inp.grid = nil; diff(first_in, inp, "in", a, {}); inp.grid = g2
      for _, l in ipairs(a) do io.stderr:write("  DIFF " .. l .. "\n") end
      local o = {}; diff(first_out, s.result, "out", o, {})
      for _, l in ipairs(o) do io.stderr:write("  DIFF " .. l .. "\n") end
    end
    if sampling and samp.__bb then
      local l = {}; for k, v in pairs(samp) do if k:sub(1, 2) ~= "__" then l[#l + 1] = {k, v} end end
      table.sort(l, function(x, y) return x[2] > y[2] end)
      io.stderr:write(string.format("  SAMPLES groups_all=%d build_block=%d\n", samp.__all or 0, samp.__bb))
      for i = 1, math.min(12, #l) do io.stderr:write(string.format("  SAMPLE %s %d (%.0f%%)\n", l[i][1], l[i][2], 100 * l[i][2] / samp.__bb)) end
      samp = {}
    end
  end
  return r
end
_G.__fp = {sha = sha, copy = copy, diff = diff}
io.stderr:write("FP probe live\n")

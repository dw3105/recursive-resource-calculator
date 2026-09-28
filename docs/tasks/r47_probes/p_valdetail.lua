return function(name, src)
  if name ~= "logic.bp.search" then return src end
  local needle = "local function record_rejection(state, errors, stage)"
  local add = [[
    do
      local function ser(v, d) d = d or 0; if type(v) ~= "table" then return tostring(v) end; if d > 2 then return "{..}" end
        local p = {}; local n = 0; for k, x in pairs(v) do n = n + 1; if n > 12 then p[#p+1] = "..."; break end; p[#p+1] = tostring(k) .. "=" .. ser(x, d + 1) end; return "{" .. table.concat(p, ",") .. "}" end
      io.stderr:write(string.format("REJ stage=%s n=%d\n", tostring(stage), #(errors or {})))
      for _, e in ipairs(errors or {}) do io.stderr:write("  E ", tostring(e.code), " ids=", ser(e.ids), " d=", ser(e.detail), "\n") end
      if stage == "validate" and os.getenv("VALEXIT") then os.exit(0) end
    end]]
  local a, b = src:find(needle, 1, true); assert(a)
  src = src:sub(1, b) .. "\n" .. add .. src:sub(b + 1)
  local tail = [[

do local orig = Search.step; local n = 0
  Search.step = function(c, b) n = n + 1; local st = c.state or c; local ph = st.phase; local t = os.clock(); local r = orig(c, b); local dt = os.clock() - t
    if dt > 0.2 then io.stderr:write(string.format("SLOW tick=%d %.3f s phase=%s->%s\n", n, dt, tostring(ph), tostring(st.phase))) end
    return r end end
return Search
]]
  local c, d = src:find("\nreturn Search%s*$"); assert(c, "no return Search")
  return src:sub(1, c - 1) .. tail
end

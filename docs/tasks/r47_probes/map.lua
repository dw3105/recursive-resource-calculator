-- lua5.2 map.lua <val ckpt> x0 y0 x1 y1 : ascii map of validate candidate; legend printed
package.path = "./?.lua;" .. package.path
local Graph = require "tools.lib.graph_dump"
local st = Graph.load(arg[1]).state
local c = st.work.validate_candidate
local x0, y0, x1, y1 = tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
local cell, legend, letters, nextl = {}, {}, {}, 0
local ARROW = {[0] = "^", [4] = ">", [8] = "v", [12] = "<"}
local function letter(fl) if not fl then return "?" end; if not letters[fl] then nextl = nextl + 1; letters[fl] = string.char(96 + nextl); legend[#legend+1] = letters[fl] .. "=" .. fl end; return letters[fl] end
for _, e in ipairs(c.entities) do
  local n = tostring(e.name or e.kind)
  local x, y = e.x, e.y
  if (x == nil or n:find("belt") or n:find("pipe") or n:find("splitter") or n:find("underground")) and e.position then x, y = math.floor(e.position.x), math.floor(e.position.y) end
  local w, h = e.w or 1, e.h or 1
  if n:find("belt") or n:find("underground") or n:find("splitter") then w, h = 1, 1 end
  local d = e.dir or e.direction or 0
  local s
  if n:find("underground") then s = "U" .. letter(e.flow_id)
  elseif n:find("splitter") then s = "S" .. letter(e.flow_id)
  elseif n:find("transport%-belt") then s = (ARROW[d] or "?") .. letter(e.flow_id)
  elseif n:find("pipe") then s = "=" .. letter(e.flow_id)
  elseif n:find("inserter") then s = "I" .. (ARROW[d] or "?")
  elseif n:find("pole") or n:find("substation") then s = "++"
  elseif n:find("beacon") then s = "bb"
  else s = "##" end
  for i = 0, w - 1 do for j = 0, h - 1 do cell[(x + i) .. "," .. (y + j)] = s end end
end
io.write("     "); for x = x0, x1 do io.write(string.format("%-2d", x % 100)) end; io.write("\n")
for y = y0, y1 do io.write(string.format("%4d ", y)); for x = x0, x1 do io.write(cell[x .. "," .. y] or ". ") end; io.write("\n") end
print(table.concat(legend, "  "))

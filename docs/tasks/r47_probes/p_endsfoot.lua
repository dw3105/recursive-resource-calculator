-- ends.lua occupies: splitter footprint from its centre position (route stores splitters by centre)
return function(name, src) if name ~= "logic.bp.ends" then return src end
 local old = "        if d == Grid.NORTH or d == Grid.SOUTH then return y == ey and (x == ex or x == ex+1) end\n        return x == ex and (y == ey or y == ey+1)"
 local new = "        local px, py = e.position and e.position.x or e.x, e.position and e.position.y or e.y\n        if d == Grid.NORTH or d == Grid.SOUTH then local x0 = math.floor(px - 0.5); return y == ey and (x == x0 or x == x0+1) end\n        local y0 = math.floor(py - 0.5); return x == ex and (y == y0 or y == y0+1)"
 local a, b = src:find(old, 1, true); assert(a, "ends occupies anchor"); io.stderr:write("PATCH endsfoot on\n"); return src:sub(1, a-1) .. new .. src:sub(b+1) end

-- Ends.turn_heads: index entities by occupied tile and by anchor tile once per call (same answers, no O(n^2))
return function(name, src)
  if name ~= "logic.bp.ends" then return src end
  local a = src:find("local function tile_accepts(entities, x, y, dir, need)", 1, true); assert(a)
  local b = src:find("return Ends", a, true); assert(b)
  local body = [==[
local function build_index(entities)
    local occ, anchor = {}, {}
    local function push(t, x, y, e) local k = x .. "," .. y; local l = t[k]; if not l then l = {}; t[k] = l end; l[#l + 1] = e end
    for _, e in ipairs(entities) do
        local k = kind(e); local ex, ey = tile(e)
        if ex then
            push(anchor, ex, ey, e)
            if k then
                push(occ, ex, ey, e)
                if k == "splitter" then for ddx = -1, 1 do for ddy = -1, 1 do if ddx ~= 0 or ddy ~= 0 then push(occ, ex + ddx, ey + ddy, e) end end end end
            end
        end
    end
    return occ, anchor
end
local function tile_accepts(index, x, y, dir, need)
    for _, e in ipairs(index[x .. "," .. y] or {}) do
        if occupies(e,x,y) and accepts(e,dir) and not includes(flows(e),need) then return true end
    end
    return false
end

function Ends.turn_heads(route_result)
    local entities=route_result and route_result.entities or {}
    local occ, anchor = build_index(entities)
    local turned=0
    for _, e in ipairs(entities) do
        if kind(e)=="belt" and not e.ug_role then
            local d=direction(e); local x,y=tile(e); local need=flows(e)
            if d ~= nil and x ~= nil and tile_accepts(occ,x+DX[d],y+DY[d],d,need) then
                local candidates={(d+12)%16,(d+4)%16}
                for _, h in ipairs(candidates) do
                    local fx,fy=x+DX[h],y+DY[h]
                    local bad=tile_accepts(occ,fx,fy,h,need)
                    if not bad then
                        for _, n in ipairs({{x+1,y},{x-1,y},{x,y+1},{x,y-1}}) do
                            for _, f in ipairs(anchor[n[1] .. "," .. n[2]] or {}) do
                                local fk=kind(f)
                                if f ~= e and fronts(f,direction(f),x,y) then
                                    local ffx,ffy=tile(f)
                                    if ffx == x+DX[h] and ffy == y+DY[h] then bad=true; break end
                                end
                                if f ~= e and fk and fronts(f,direction(f),x,y) and not includes(flows(f),need) then bad=true; break end
                            end
                            if bad then break end
                        end
                    end
                    if not bad then
                        e.dir=h; if e.direction ~= nil then e.direction=h end
                        turned=turned+1; break
                    end
                end
            end
        end
    end
    return turned
end
]==]
  return src:sub(1, a - 1) .. body .. src:sub(b)
end

--Turn a route's terminal belts away from foreign transport that would accept their items.
local Grid = require "logic.bp.grid"
local Ends = {}

local DX = {[Grid.NORTH]=0,[Grid.EAST]=1,[Grid.SOUTH]=0,[Grid.WEST]=-1}
local DY = {[Grid.NORTH]=-1,[Grid.EAST]=0,[Grid.SOUTH]=1,[Grid.WEST]=0}
local function kind(e)
    local n = tostring(e.name or e.kind or e.type or "")
    if n:find("splitter", 1, true) then return "splitter" end
    if n:find("underground", 1, true) or e.ug_role then return "underground" end
    if n:find("transport-belt", 1, true) or n == "belt" then return "belt" end
end
local function tile(e)
    local x, y = e.x, e.y
    if x == nil and e.position then x = e.position.x end
    if y == nil and e.position then y = e.position.y end
    if x == nil or y == nil then return nil end
    return math.floor(x), math.floor(y)
end
local function flows(e)
    local out = {}
    if type(e.flow_ids) == "table" then
        for k, v in pairs(e.flow_ids) do
            local id = type(k) == "number" and v or (v and k or nil)
            if id ~= nil then out[id] = true end
        end
    elseif e.flow_id ~= nil then out[e.flow_id] = true end
    return out
end
local function includes(have, need)
    for id in pairs(need) do if not have[id] then return false end end
    return true
end
local function direction(e) return e.dir or e.direction end
local function fronts(e, d, tx, ty)
    local x,y=tile(e); return x ~= nil and d ~= nil and x+DX[d] == tx and y+DY[d] == ty
end
local function occupies(e, x, y)
    local k=kind(e); local ex,ey=tile(e); if not k or not ex then return false end
    if k == "splitter" then
        local d=direction(e)
        -- Normal splitter footprint is perpendicular to its facing.
        if d == Grid.NORTH or d == Grid.SOUTH then return y == ey and (x == ex or x == ex+1) end
        return x == ex and (y == ey or y == ey+1)
    end
    return x == ex and y == ey
end
local function accepts(e, incoming_dir)
    local k=kind(e); local d=direction(e)
    if k == "belt" then return d ~= nil and d ~= (incoming_dir + 8) % 16 end
    if k == "splitter" then return d == incoming_dir end
    if k == "underground" then
        if e.ug_role == "output" or e.type == "output" then return false end
        return e.ug_role == "input" or e.type == "input" or (d ~= nil and d ~= (incoming_dir + 8) % 16)
    end
    return false
end
local function tile_accepts(entities, x, y, dir, need)
    for _, e in ipairs(entities) do
        if occupies(e,x,y) and accepts(e,dir) and not includes(flows(e),need) then return true end
    end
    return false
end

function Ends.turn_heads(route_result)
    local entities=route_result and route_result.entities or {}
    local turned=0
    for _, e in ipairs(entities) do
        if kind(e)=="belt" and not e.ug_role then
            local d=direction(e); local x,y=tile(e); local need=flows(e)
            if d ~= nil and x ~= nil and tile_accepts(entities,x+DX[d],y+DY[d],d,need) then
                -- Grid directions increase clockwise (north, east, south, west).
                local candidates={(d+12)%16,(d+4)%16}
                for _, h in ipairs(candidates) do
                    local fx,fy=x+DX[h],y+DY[h]
                    local bad=tile_accepts(entities,fx,fy,h,need)
                    if not bad then
                        -- Preserve all current feeders, and do not create a new foreign side feed.
                        for _, f in ipairs(entities) do
                            local fk=kind(f)
                            if f ~= e and fronts(f,direction(f),x,y) then
                                local fx,fy=tile(f)
                                -- A feeder may not sit immediately in front of the rotated belt and point
                                -- into its head; it would be a head-on feed after the turn.
                                if fx == x+DX[h] and fy == y+DY[h] then bad=true; break end
                            end
                            if f ~= e and fk and fronts(f,direction(f),x,y) and not includes(flows(f),need) then bad=true; break end
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
return Ends

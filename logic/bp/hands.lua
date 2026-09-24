local Hands = {}
local function finite(v, fallback) if type(v)=="number" and v==v then return v end return fallback end
local function copy(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function every_port_copy(materialized)
    local result = {}
    for _, port in ipairs(materialized.ports or {}) do result[#result + 1] = port end
    for _, block in ipairs(materialized.blocks or {}) do
        for _, port in ipairs(block.ports or {}) do result[#result + 1] = port end
    end
    return result
end

--The player placed v4 on 2026-09-23 and boxed two belts that bent only to reach a hand grouping had fixed
--before any belt existed.  Each hand that serves one port may move one tile along its machine face; route.lua
--improve_routes tries the move and keeps it only when the layout gets smaller.  Only unrotated placements
--carry world port tiles (Groups.materialize), so only those are offered.
function Hands.offer_slides(materialized, grid)
    local by_id, taken, served = {}, {}, {}
    for _, entity in ipairs(materialized.entities or {}) do
        by_id[tostring(entity.id)] = entity
        if entity.x ~= nil and entity.y ~= nil then
            for x = entity.x, entity.x + finite(entity.w, 1) - 1 do
                for y = entity.y, entity.y + finite(entity.h, 1) - 1 do taken[x .. ":" .. y] = true end
            end
        end
    end
    local function hand_of(port)
        if port.inserter_id == nil then return nil end
        return by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)]
    end
    for _, port in ipairs(materialized.ports or {}) do
        local hand = hand_of(port)
        if hand then served[hand] = (served[hand] or 0) + 1 end
    end
    for _, port in ipairs(materialized.ports or {}) do
        local hand = hand_of(port)
        local machine = hand and by_id[tostring(hand.machine_id)]
        if hand and machine and served[hand] == 1 and port.x ~= nil and port.y ~= nil and port.attach_dx ~= nil
            and hand.x ~= nil and machine.x ~= nil and finite(hand.w, 1) == 1 and finite(hand.h, 1) == 1 then
            local nx, ny = port.x - hand.x, port.y - hand.y
            if math.abs(nx) + math.abs(ny) == 1 then
                local options = {}
                for _, step in ipairs(nx ~= 0 and {{0, -1}, {0, 1}} or {{-1, 0}, {1, 0}}) do
                    local hx, hy = hand.x + step[1], hand.y + step[2]
                    local reach_x, reach_y = hx - nx, hy - ny
                    local on_face = reach_x >= machine.x and reach_x < machine.x + finite(machine.w, 1)
                        and reach_y >= machine.y and reach_y < machine.y + finite(machine.h, 1)
                    if on_face and not taken[hx .. ":" .. hy] and hx >= 0 and hy >= 0 and hx < grid.w and hy < grid.h then
                        options[#options + 1] = {dx = step[1], dy = step[2]}
                    end
                end
                if #options > 0 then
                    for _, twin in ipairs(every_port_copy(materialized)) do
                        if twin.port_id == port.port_id then twin.slide_options, twin.hand_x, twin.hand_y = options, hand.x, hand.y end
                    end
                end
            end
        end
    end
end

--Move each hand the route kept a slide for, with its port tile and pickup/drop points.
function Hands.place(materialized, route_result)
    local by_port = {}
    for _, slide in ipairs(route_result and route_result.port_slides or {}) do by_port[tostring(slide.port_id)] = slide end
    if next(by_port) == nil then return {} end
    local by_id = {}
    for _, entity in ipairs(materialized.entities or {}) do by_id[tostring(entity.id)] = entity end
    local ports = every_port_copy(materialized)
    for _, port in ipairs(ports) do
        local slide = by_port[tostring(port.port_id or port.id)]
        if slide then
            port.x, port.y = port.x + slide.dx, port.y + slide.dy
            port.attach_dx, port.attach_dy = port.attach_dx + slide.dx, port.attach_dy + slide.dy
            port.slide_options = nil
        end
    end
    for _, port in ipairs(materialized.ports or {}) do
        local slide = by_port[tostring(port.port_id or port.id)]
        local hand = slide and port.inserter_id ~= nil
            and (by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)])
        if hand then
            local dx, dy = slide.dx, slide.dy
            local old_x, old_y = hand.x, hand.y
            hand.x, hand.y = hand.x + dx, hand.y + dy
            for _, field in ipairs({"position", "pickup_position", "drop_position"}) do
                local point = hand[field]
                if type(point) == "table" and point.x ~= nil then hand[field] = {x = point.x + dx, y = point.y + dy} end
            end
            for _, other in ipairs(ports) do
                for _, rect in ipairs(other._occupied or {}) do
                    if rect.x == old_x and rect.y == old_y and finite(rect.w, 1) == 1 and finite(rect.h, 1) == 1 then
                        rect.x, rect.y = rect.x + dx, rect.y + dy
                    end
                end
            end
        end
    end
    local hands = {}
    for _, entity in ipairs(materialized.entities or {}) do
        if entity.kind == "inserter" or entity.type == "inserter" or tostring(entity.name or ""):find("inserter", 1, true) then hands[#hands + 1] = entity end
    end
    return hands
end


function Hands.free_cell(materialized, x, y)
    local hands, ports = materialized.entities or {}, materialized.ports or {}
    for _, hand in ipairs(hands) do
        if hand.x == x and hand.y == y then
            for _, port in ipairs(ports) do
                if tostring(port.inserter_id) == tostring(hand.id):gsub("^m:", "") then
                    local machine
                    for _, e in ipairs(hands) do if tostring(e.id)==tostring(hand.machine_id) then machine=e end end
                    if not machine then return false end
                    local dx,dy=port.x-hand.x,port.y-hand.y
                    local steps=dx~=0 and {{0,-1},{0,1}} or {{-1,0},{1,0}}
                    for _,d in ipairs(steps) do
                        local nx,ny=x+d[1],y+d[2]
                        local occupied=false
                        for _,e in ipairs(hands) do if e~=hand and e.x==nx and e.y==ny then occupied=true end end
                        local pickup=hand.pickup_position or {}; local drop=hand.drop_position or {}
                        if not occupied and pickup.x and drop.x then
                            local shiftx,shifty=nx-x,ny-y
                            hand.x,hand.y=nx,ny; hand.position={x=nx+0.5,y=ny+0.5}
                            hand.pickup_position={x=pickup.x+shiftx,y=pickup.y+shifty}; hand.drop_position={x=drop.x+shiftx,y=drop.y+shifty}
                            port.x=port.x+shiftx; port.y=port.y+shifty
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end
return Hands

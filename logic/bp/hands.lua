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
        local kind = tostring(entity.kind or entity.type or "")
        local name = tostring(entity.name or "")
        local is_hand = kind == "inserter" or name:find("inserter", 1, true) ~= nil
        if not is_hand and entity.x ~= nil and entity.y ~= nil then
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
    -- A hop changes the machine face served by a single inserter. Keep the option payload plain data so the
    -- router can snapshot, try and resume it across ticks without retaining closures.
    for _, port in ipairs(materialized.ports or {}) do
        local hand = hand_of(port)
        local machine = hand and by_id[tostring(hand.machine_id)]
        if hand and machine and served[hand] == 1 and not port.row_port and port.x ~= nil and port.y ~= nil
            and hand.x ~= nil and hand.y ~= nil and machine.x ~= nil and port.attach_dx ~= nil
            and finite(hand.w, 1) == 1 and finite(hand.h, 1) == 1 then
            local vx, vy = port.x - hand.x, port.y - hand.y
            local current_dir
            if vx == 0 and vy == -1 then current_dir = 0 elseif vx == 1 and vy == 0 then current_dir = 4
            elseif vx == 0 and vy == 1 then current_dir = 8 elseif vx == -1 and vy == 0 then current_dir = 12 end
            if current_dir then
                local candidates, slide_tiles = {}, {}
                for _, twin in ipairs(every_port_copy(materialized)) do
                    if twin.port_id == port.port_id then
                        for _, slide in ipairs(twin.slide_options or {}) do
                            slide_tiles[(hand.x + slide.dx) .. ":" .. (hand.y + slide.dy)] = true
                        end
                    end
                end
                local faces = {
                    {dir=0, dx=0, dy=-1, x0=machine.x, x1=machine.x + finite(machine.w, 1) - 1, y=machine.y-1},
                    {dir=8, dx=0, dy=1, x0=machine.x, x1=machine.x + finite(machine.w, 1) - 1, y=machine.y+finite(machine.h,1)},
                    {dir=12, dx=-1, dy=0, y0=machine.y, y1=machine.y + finite(machine.h,1)-1, x=machine.x-1},
                    {dir=4, dx=1, dy=0, y0=machine.y, y1=machine.y + finite(machine.h,1)-1, x=machine.x+finite(machine.w,1)},
                }
                local function free(x,y)
                    --The search's roboport grid carries no `cells` (Grid.robo_grid); `taken` already holds every entity.
                    return x >= 0 and y >= 0 and x < grid.w and y < grid.h and not taken[x .. ":" .. y]
                        and (grid.cells == nil or grid.cells[y * grid.w + x + 1] == nil
                            or grid.cells[y * grid.w + x + 1] == 0)
                end
                for _, face in ipairs(faces) do
                    if face.x0 then
                        for hx=face.x0,face.x1 do
                            local hy=face.y
                            local px,py=hx+face.dx,hy+face.dy
                            if not (hx==hand.x and hy==hand.y)
                                and free(hx,hy) and free(px,py) then
                                candidates[#candidates+1]={hand_x=hx,hand_y=hy,port_x=px,port_y=py,
                                    turns=((face.dir-current_dir)%16)/4}
                            end
                        end
                    else
                        for hy=face.y0,face.y1 do
                            local hx=face.x
                            local px,py=hx+face.dx,hy+face.dy
                            if not (hx==hand.x and hy==hand.y)
                                and free(hx,hy) and free(px,py) then
                                candidates[#candidates+1]={hand_x=hx,hand_y=hy,port_x=px,port_y=py,
                                    turns=((face.dir-current_dir)%16)/4}
                            end
                        end
                    end
                end
                table.sort(candidates,function(a,b)
                    local ad,bd=math.abs(a.hand_x-hand.x)+math.abs(a.hand_y-hand.y),math.abs(b.hand_x-hand.x)+math.abs(b.hand_y-hand.y)
                    if ad~=bd then return ad<bd end
                    if a.hand_y~=b.hand_y then return a.hand_y<b.hand_y end
                    return a.hand_x<b.hand_x
                end)
                for _, twin in ipairs(every_port_copy(materialized)) do
                    if twin.port_id==port.port_id then twin.hop_options,twin.hand_x,twin.hand_y=candidates,hand.x,hand.y end
                end
            end
        end
    end
end

--Move each hand the route kept a slide for, with its port tile and pickup/drop points.
function Hands.place(materialized, route_result)
    local function inserters()
        local result = {}
        for _, entity in ipairs(materialized.entities or {}) do
            if entity.kind == "inserter" or entity.type == "inserter"
                or tostring(entity.name or ""):find("inserter", 1, true) then result[#result + 1] = entity end
        end
        return result
    end
    local by_port = {}
    for _, slide in ipairs(route_result and route_result.port_slides or {}) do by_port[tostring(slide.port_id)] = slide end
    if next(by_port) == nil then return inserters() end
    local by_id = {}
    for _, entity in ipairs(materialized.entities or {}) do by_id[tostring(entity.id)] = entity end
    local ports = every_port_copy(materialized)
    for _, port in ipairs(ports) do
        local slide = by_port[tostring(port.port_id or port.id)]
        if slide then
            if slide.hop then
                local hop=slide.hop
                local dx,dy=hop.port_x-port.x,hop.port_y-port.y
                port.x,port.y=hop.port_x,hop.port_y
                port.attach_dx,port.attach_dy=port.attach_dx+dx,port.attach_dy+dy
                local rotate=function(dir) return dir==nil and nil or (dir+4*hop.turns)%16 end
                port.travel_dir,port.normal_dir=rotate(port.travel_dir),rotate(port.normal_dir)
                --A hopped port leaves the block's own boundary ring; validate checks it against its hand instead.
                port.hopped=true
            else
                port.x, port.y = port.x + slide.dx, port.y + slide.dy
                port.attach_dx, port.attach_dy = port.attach_dx + slide.dx, port.attach_dy + slide.dy
            end
            port.slide_options = nil
            port.hop_options = nil
        end
    end
    for _, port in ipairs(materialized.ports or {}) do
        local slide = by_port[tostring(port.port_id or port.id)]
        local hand = slide and port.inserter_id ~= nil
            and (by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)])
        if hand then
            local old_x, old_y = hand.x, hand.y
            local dx,dy
            if slide.hop then
                local hop=slide.hop
                dx,dy=hop.hand_x-hand.x,hop.hand_y-hand.y
                hand.x,hand.y=hop.hand_x,hop.hand_y
                if hand.dir ~= nil then hand.dir=(hand.dir+4*hop.turns)%16 end
                if hand.direction ~= nil then hand.direction=(hand.direction+4*hop.turns)%16 end
                hand.position={x=hand.x+0.5,y=hand.y+0.5}
                --The machine tile is the hand's mirror of its port tile: no guess about what normal_dir points at.
                local outward_x,outward_y=hop.port_x-hop.hand_x,hop.port_y-hop.hand_y
                local machine_x,machine_y=hand.x-outward_x,hand.y-outward_y
                local port_point={x=port.x+0.5,y=port.y+0.5}
                local machine_point={x=machine_x+0.5,y=machine_y+0.5}
                if port.role=="out" then hand.pickup_position,hand.drop_position=machine_point,port_point
                else hand.pickup_position,hand.drop_position=port_point,machine_point end
            else
                dx, dy = slide.dx, slide.dy
                hand.x, hand.y = hand.x + dx, hand.y + dy
                for _, field in ipairs({"position", "pickup_position", "drop_position"}) do
                    local point = hand[field]
                    if type(point) == "table" and point.x ~= nil then hand[field] = {x = point.x + dx, y = point.y + dy} end
                end
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
    return inserters()
end


function Hands.free_cell(materialized, x, y)
    local entities, ports = materialized.entities or {}, materialized.ports or {}
    local by_id = {}
    for _, entity in ipairs(entities) do by_id[tostring(entity.id)] = entity end
    local function same_run(px, py, port)
        px, py = math.floor(px or -999), math.floor(py or -999)
        for _, block in ipairs(materialized.blocks or {}) do
            for _, run in ipairs(block.belt_runs or {}) do
                local belongs = false
                for _, tile in ipairs(run.tiles or {}) do
                    if tile.x == px and tile.y == py then belongs = true; break end
                end
                if belongs and (not port.flow_id or not run.flows or #run.flows == 0) then return true end
                if belongs then for _, flow in ipairs(run.flows or {}) do
                    if flow == port.flow_id then return true end
                end end
            end
        end
        return false
    end
    for _, hand in ipairs(entities) do
        if hand.x == x and hand.y == y then
            local port
            for _, value in ipairs(ports) do
                if tostring(value.inserter_id) == tostring(hand.id):gsub("^m:", "") then port = value; break end
            end
            local machine = port and by_id[tostring(hand.machine_id)]
            if not port or not machine then return false end
            local nx, ny = port.x - hand.x, port.y - hand.y
            if math.abs(nx) + math.abs(ny) ~= 1 then return false end
            local pickup, drop = hand.pickup_position or {}, hand.drop_position or {}
            local steps = nx ~= 0 and {{0, -1}, {0, 1}} or {{-1, 0}, {1, 0}}
            for _, delta in ipairs(steps) do
                local tx, ty = x + delta[1], y + delta[2]
                local occupied = false
                for _, entity in ipairs(entities) do
                    if entity ~= hand and tx >= (entity.x or math.huge) and tx < (entity.x or 0) + finite(entity.w, 1)
                        and ty >= (entity.y or math.huge) and ty < (entity.y or 0) + finite(entity.h, 1) then occupied = true end
                end
                local dx, dy = tx - x, ty - y
                local new_pickup = {x = (pickup.x or -999) + dx, y = (pickup.y or -999) + dy}
                local new_drop = {x = (drop.x or -999) + dx, y = (drop.y or -999) + dy}
                local drop_inside = new_drop.x >= machine.x and new_drop.x < machine.x + finite(machine.w, 1)
                    and new_drop.y >= machine.y and new_drop.y < machine.y + finite(machine.h, 1)
                if not occupied and same_run(new_pickup.x, new_pickup.y, port) and drop_inside then
                    hand.x, hand.y = tx, ty
                    hand.position = {x = tx + 0.5, y = ty + 0.5}
                    if pickup.x then hand.pickup_position = new_pickup end
                    if drop.x then hand.drop_position = new_drop end
                    port.x, port.y = port.x + dx, port.y + dy
                    return true
                end
            end
        end
    end
    return false
end

return Hands

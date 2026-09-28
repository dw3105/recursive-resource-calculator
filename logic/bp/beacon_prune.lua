--Remove beacons that add no required same-signature coverage after routing has fixed the layout.
local BeaconPrune = {}

local function entity_name(entity)
    return entity.name or entity.entity or entity.prototype
end

local function box(entity)
    local x, y = entity.x, entity.y
    local w, h = entity.w, entity.h
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    return {left = x, top = y, right = x + w, bottom = y + h}
end

local function reaches(beacon, machine, catalog)
    local b, m = box(beacon), box(machine)
    if not b or not m then return false end
    local spec = catalog and catalog.beacon and catalog.beacon[entity_name(beacon)] or {}
    local sw = beacon.supply_w
    if type(sw) ~= "number" then sw = spec.supply_w or 0 end
    local sh = beacon.supply_h
    if type(sh) ~= "number" then sh = spec.supply_h or sw end
    return m.right > b.left - sw and m.left < b.right + sw
        and m.bottom > b.top - sh and m.top < b.bottom + sh
end

local function required_for(beacon)
    local result = {}
    for _, id in ipairs(beacon.required_for or {}) do result[id] = true end
    return result
end

function BeaconPrune.share(entities, route_entities, catalog)
    entities = entities or {}
    local occupied = {}
    local function mark(entity, value)
        if type(entity.x) == "number" and type(entity.y) == "number" then
            local w, h = entity.w, entity.h
            if type(w) == "number" and type(h) == "number" then
                for x = entity.x, entity.x + w - 1 do
                    for y = entity.y, entity.y + h - 1 do occupied[x .. ":" .. y] = value end
                end
            else
                occupied[entity.x .. ":" .. entity.y] = value
            end
        elseif type(entity.position) == "table" and type(entity.position.x) == "number"
            and type(entity.position.y) == "number" then
            occupied[math.floor(entity.position.x) .. ":" .. math.floor(entity.position.y)] = value
        end
    end
    for _, entity in ipairs(entities) do mark(entity, entity) end
    for _, entity in ipairs(route_entities or {}) do
        if type(entity.position) == "table" and type(entity.position.x) == "number"
            and type(entity.position.y) == "number" then
            occupied[math.floor(entity.position.x) .. ":" .. math.floor(entity.position.y)] = entity
        else
            mark(entity, entity)
        end
    end

    local machines, beacons = {}, {}
    for _, entity in ipairs(entities) do
        if entity.kind == "machine" then machines[entity.id] = entity end
        if entity.kind == "beacon" then beacons[#beacons + 1] = entity end
    end
    table.sort(beacons, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local moved = 0
    for _, beacon in ipairs(beacons) do
        if beacon.signature and type(beacon.required_for) == "table" and not beacon._gone then
            for _, other in ipairs(beacons) do
                if other ~= beacon and not other._gone and other.signature == beacon.signature
                    and type(other.required_for) == "table" then
                    local shared_required = false
                    local own_required = required_for(beacon)
                    for _, id in ipairs(other.required_for) do if own_required[id] then shared_required = true; break end end
                    -- legalcopilot-dev, lua5.2, 2026-09-28: M1 coverage fell from 3 to 2 when same-machine beacons shared.
                    if not shared_required then
                    local already_reaches = true
                    for _, id in ipairs(other.required_for) do
                        if not machines[id] or not reaches(beacon, machines[id], catalog) then
                            already_reaches = false
                            break
                        end
                    end
                    if not already_reaches then
                        local best
                        for dy = -2, 2 do
                            for dx = -2, 2 do
                                if not best then
                                    local candidate = {x = beacon.x + dx, y = beacon.y + dy,
                                        w = beacon.w, h = beacon.h, supply_w = beacon.supply_w,
                                        supply_h = beacon.supply_h, name = entity_name(beacon)}
                                    local free = true
                                    for x = candidate.x, candidate.x + candidate.w - 1 do
                                        for y = candidate.y, candidate.y + candidate.h - 1 do
                                            local occupant = occupied[x .. ":" .. y]
                                            if occupant and occupant ~= beacon then free = false end
                                        end
                                    end
                                    if free then
                                        local covers = true
                                        for _, id in ipairs(beacon.required_for) do
                                            if not machines[id] or not reaches(candidate, machines[id], catalog) then covers = false; break end
                                        end
                                        if covers then
                                            for _, id in ipairs(other.required_for) do
                                                if not machines[id] or not reaches(candidate, machines[id], catalog) then covers = false; break end
                                            end
                                        end
                                        if covers then best = candidate end
                                    end
                                end
                            end
                        end
                        if best then
                            mark(beacon, nil)
                            local dx, dy = best.x - beacon.x, best.y - beacon.y
                            beacon.x, beacon.y = best.x, best.y
                            if type(beacon.cx) == "number" then beacon.cx = beacon.cx + dx end
                            if type(beacon.cy) == "number" then beacon.cy = beacon.cy + dy end
                            if type(beacon.position) == "table" then
                                beacon.position = {x = beacon.position.x + dx, y = beacon.position.y + dy}
                            end
                            mark(beacon, beacon)
                            for _, field in ipairs({"required_for", "covered_members", "member_ids", "members"}) do
                                if type(beacon[field]) == "table" then
                                    for _, value in ipairs(other[field] or {}) do beacon[field][#beacon[field] + 1] = value end
                                end
                            end
                            other._gone = true
                            moved = moved + 1
                            break
                        end
                    end
                    end
                end
            end
        end
    end
    if moved > 0 then
        local kept = {}
        for _, entity in ipairs(entities) do if not entity._gone then kept[#kept + 1] = entity end end
        for index = #entities, 1, -1 do entities[index] = nil end
        for index, entity in ipairs(kept) do entities[index] = entity end
    end
    return moved
end

function BeaconPrune.run(entities, catalog, route_entities)
    entities = entities or {}
    BeaconPrune.share(entities, route_entities, catalog)
    local machines, beacons, needs = {}, {}, {}
    for _, entity in ipairs(entities) do
        if entity.kind == "machine" then machines[entity.id] = entity end
        if entity.kind == "beacon" then beacons[#beacons + 1] = entity end
    end

    for _, beacon in ipairs(beacons) do
        if beacon.signature and type(beacon.required_for) == "table" then
            for _, id in ipairs(beacon.required_for) do
                needs[id] = needs[id] or {}
                local by_signature = needs[id]
                by_signature[beacon.signature] = (by_signature[beacon.signature] or 0) + 1
            end
        end
    end

    table.sort(beacons, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local removed, removed_set = {}, {}
    for _, candidate in ipairs(beacons) do
        local req = required_for(candidate)
        if candidate.signature and next(req) ~= nil then
            local safe = true
            for machine_id, machine in pairs(machines) do
                local needed = needs[machine_id] and needs[machine_id][candidate.signature] or 0
                if needed > 0 and reaches(candidate, machine, catalog) then
                    local available = 0
                    for _, other in ipairs(beacons) do
                        if other ~= candidate and not removed_set[other]
                            and other.signature == candidate.signature and reaches(other, machine, catalog) then
                            available = available + 1
                        end
                    end
                    if available < needed then safe = false; break end
                end
            end
            if safe then removed_set[candidate] = true; removed[#removed + 1] = candidate.id end
        end
    end

    if #removed > 0 then
        local kept = {}
        for _, entity in ipairs(entities) do if not removed_set[entity] then kept[#kept + 1] = entity end end
        for index = #entities, 1, -1 do entities[index] = nil end
        for index, entity in ipairs(kept) do entities[index] = entity end
    end
    return removed
end

return BeaconPrune

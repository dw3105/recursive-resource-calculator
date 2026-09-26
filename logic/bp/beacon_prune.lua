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

function BeaconPrune.run(entities, catalog)
    entities = entities or {}
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

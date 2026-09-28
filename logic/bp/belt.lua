-- Shared belt capacity rules. Map-edge item inputs may arrive already stacked.
local Belt = {}

function Belt.stack_max(catalog)
    local value = catalog and catalog.belt and catalog.belt.stack_max
    if type(value) == "number" and value == value and value > 0 and value ~= math.huge then
        return math.max(1, value)
    end
    return 4
end

function Belt.is_external_item(flow)
    if type(flow) ~= "table" or flow.is_fluid or flow.kind == "fluid" then return false end
    for _, producer in ipairs(flow.producers or {}) do
        if producer.step_id == "$external" or producer.step == "$external" then return true end
    end
    return false
end

function Belt.capacity(catalog, flow, kind)
    local belt = catalog and catalog.belt or {}
    local capacity = kind == "lane" and (belt.lane_items_per_second or belt.items_per_second)
        or belt.items_per_second
    if type(capacity) ~= "number" or capacity ~= capacity then return nil end
    if Belt.is_external_item(flow) then capacity = capacity * Belt.stack_max(catalog) end
    return capacity
end

return Belt

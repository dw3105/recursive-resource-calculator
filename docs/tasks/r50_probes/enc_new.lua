local Snapshot = {}
local format, concat, sort, tostring, pairs, type = string.format, table.concat, table.sort, tostring, pairs, type
local scalar_codes = {}
local function prefixed(value)
    return #value .. ":" .. value
end
local encode_value
encode_value = function(value, active)
    local value_type = type(value)
    if value_type == "string" then
        local code = scalar_codes[value]
        if not code then code = "s" .. prefixed(value); scalar_codes[value] = code end
        return code
    elseif value_type == "table" then
        if active[value] then error("snapshot fingerprint cannot encode a cyclic table", 3) end
        active[value] = true
        local codes, by_code, count = {}, {}, 0
        for key, child in pairs(value) do
            local key_code = encode_value(key, active)
            count = count + 1
            codes[count] = key_code
            by_code[key_code] = encode_value(child, active)
        end
        active[value] = nil
        sort(codes)
        local out = {"t", prefixed(tostring(count))}
        local n = 2
        for i = 1, count do
            local key_code = codes[i]
            local child_code = by_code[key_code]
            out[n + 1] = #key_code .. ":" .. key_code
            out[n + 2] = #child_code .. ":" .. child_code
            n = n + 2
        end
        return concat(out)
    elseif value == nil then
        return "n"
    elseif value_type == "boolean" then
        return value and "b1:1" or "b1:0"
    elseif value_type == "number" then
        return "d" .. prefixed(format("%.17g", value))
    end
    error("snapshot fingerprint cannot encode " .. value_type, 3)
end
function Snapshot.fingerprint(snapshot)
    return "rrc-snapshot-1:" .. encode_value({targets = snapshot.targets or {}, options = snapshot.options or {}, selection = snapshot.selection or {}}, {})
end
return Snapshot

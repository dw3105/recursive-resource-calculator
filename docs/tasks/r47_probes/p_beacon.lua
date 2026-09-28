-- beacon_prune: never merge two beacons that serve a shared machine (that machine loses one beacon)
return function(name, src) if name ~= "logic.bp.beacon_prune" then return src end
 local old = "                if other ~= beacon and not other._gone and other.signature == beacon.signature\n                    and type(other.required_for) == \"table\" then"
 local new = [[                if other ~= beacon and not other._gone and other.signature == beacon.signature
                    and type(other.required_for) == "table" and not (function()
                        local mine = {}; for _, id in ipairs(beacon.required_for) do mine[id] = true end
                        for _, id in ipairs(other.required_for) do if mine[id] then return true end end
                        return false end)() then]]
 local a, b = src:find(old, 1, true); assert(a, "beacon anchor"); io.stderr:write("PATCH beacon on\n")
 return src:sub(1, a - 1) .. new .. src:sub(b + 1) end

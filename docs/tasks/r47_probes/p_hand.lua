return function(name, src)
  if name ~= "logic.bp.seat" then return src end
  local a = "    local used, shared_ports, slides = {}, {}, {}\n"
  local s, e = src:find(a, 1, true); assert(s, "p_hand anchor missing")
  return src:sub(1, e) .. [[
    local p_hand_seated = {}
    for _, item in ipairs(list) do p_hand_seated[item.hand] = true end
    for _, e in ipairs(materialized.entities or {}) do
        local is_hand = e.kind == "inserter" or e.type == "inserter" or tostring(e.name or ""):find("inserter", 1, true)
        if is_hand and not p_hand_seated[e] and e.x ~= nil and e.y ~= nil then
            for x = e.x, e.x + finite(e.w, 1) - 1 do
                for y = e.y, e.y + finite(e.h, 1) - 1 do used[tostring(x) .. ":" .. tostring(y)] = true end
            end
        end
    end
    for _, p in ipairs(materialized.ports or {}) do
        local h = p.inserter_id and (by_id["m:" .. tostring(p.inserter_id)] or by_id[tostring(p.inserter_id)])
        if h and not p_hand_seated[h] and p.x ~= nil and p.y ~= nil then used[tostring(p.x) .. ":" .. tostring(p.y)] = true end
    end
    io.stderr:write("p_hand live\n")
]] .. src:sub(e + 1)
end

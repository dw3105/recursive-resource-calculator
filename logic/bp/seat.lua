local Hands = require "logic.bp.hands"
local Seat = {}
local function port_tile(port) return port.x or port._world_x, port.y or port._world_y end

local function finite(v, fallback)
    if type(v) == "number" and v == v then return v end
    return fallback
end

function Seat.run(materialized, grid, flows, input_edge)
    local by_id = {}
    for _, e in ipairs(materialized.entities or {}) do by_id[tostring(e.id)] = e end

    local external = {}
    for _, f in ipairs(flows or {}) do
        for _, p in ipairs(f.producers or {}) do
            if p.step_id == "$external" then external[f.flow_id or f.full_name or f.id] = true end
        end
    end

    local list, machines_by_flow = {}, {}
    for _, port in ipairs(materialized.ports or {}) do
        local hand = port.inserter_id and
            (by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)])
        local machine = hand and by_id[tostring(hand.machine_id)]
        if hand and machine and port.role == "in" and port.kind ~= "fluid" and not port.row_port
            and port.hop_options and external[port.flow_id] then
            list[#list + 1] = {port = port, hand = hand, machine = machine}
            machines_by_flow[port.flow_id] = machines_by_flow[port.flow_id] or {}
            machines_by_flow[port.flow_id][machine] = true
        end
    end

    local per_machine_flow = {}
    for _, item in ipairs(list) do
        local key = tostring(item.machine.id) .. "|" .. tostring(item.port.flow_id)
        per_machine_flow[key] = (per_machine_flow[key] or 0) + 1
    end
    local eligible = {}
    for _, item in ipairs(list) do
        local key = tostring(item.machine.id) .. "|" .. tostring(item.port.flow_id)
        if per_machine_flow[key] == 1 then eligible[#eligible + 1] = item end
    end
    list = eligible

    local function machine_count(flow_id)
        local n = 0
        for _ in pairs(machines_by_flow[flow_id] or {}) do n = n + 1 end
        return n
    end
    local function box_distance(x, y, m)
        local dx = math.max(m.x - x, 0, x - (m.x + finite(m.w, 1) - 1))
        local dy = math.max(m.y - y, 0, y - (m.y + finite(m.h, 1) - 1))
        return dx + dy
    end
    local function edge_distance(x, y)
        if input_edge == "top" then return y end
        if input_edge == "right" then return grid.w - 1 - x end
        if input_edge == "bottom" then return grid.h - 1 - y end
        return x
    end

    table.sort(list, function(a, b)
        local a_shared, b_shared = machine_count(a.port.flow_id) >= 2, machine_count(b.port.flow_id) >= 2
        if a_shared ~= b_shared then return a_shared end
        if tostring(a.machine.id) ~= tostring(b.machine.id) then
            return tostring(a.machine.id) < tostring(b.machine.id)
        end
        return tostring(a.port.flow_id) < tostring(b.port.flow_id)
    end)

    local used, shared_ports, slides = {}, {}, {}
    local seated = {}
    for _, item in ipairs(list) do seated[item.hand] = true end
    -- legalcopilot-dev, lua5.2, 2026-09-28: 1 of 181 hands moved on the 104x154 sheet; reserve unseated hand and port tiles.
    for _, hand in ipairs(materialized.entities or {}) do
        local kind = tostring(hand.kind or hand.type or "")
        if (kind == "inserter" or tostring(hand.name or ""):find("inserter", 1, true)) and not seated[hand] then
            used[tostring(hand.x) .. ":" .. tostring(hand.y)] = true
            local inserter_id = tostring(hand.id):gsub("^m:", "")
            for _, port in ipairs(materialized.ports or {}) do
                if tostring(port.inserter_id) == inserter_id then
                    local x, y = port_tile(port)
                    used[tostring(x) .. ":" .. tostring(y)] = true
                end
            end
        end
    end
    for _, item in ipairs(list) do
        local port, hand, machine = item.port, item.hand, item.machine
        local shared = machine_count(port.flow_id) >= 2
        local port_x, port_y = port_tile(port)
        local options = {{hand_x = hand.x, hand_y = hand.y, port_x = port_x, port_y = port_y,
            turns = 0, stay = true}}
        for _, option in ipairs(port.hop_options) do options[#options + 1] = option end
        local best, best_key
        for _, option in ipairs(options) do
            local hand_key = tostring(option.hand_x) .. ":" .. tostring(option.hand_y)
            local port_key = tostring(option.port_x) .. ":" .. tostring(option.port_y)
            if not used[hand_key] and not used[port_key] then
                local k2 = 0
                if shared then
                    k2 = math.huge
                    for other in pairs(machines_by_flow[port.flow_id]) do
                        if other ~= machine then
                            k2 = math.min(k2, box_distance(option.port_x, option.port_y, other))
                        end
                    end
                else
                    for _, shared_port in ipairs(shared_ports[machine] or {}) do
                        k2 = k2 - (math.abs(shared_port.x - option.port_x) + math.abs(shared_port.y - option.port_y))
                    end
                end
                local key = {edge_distance(option.port_x, option.port_y), k2,
                    option.stay and 0 or 1, option.hand_y, option.hand_x}
                local better = best_key == nil
                if best_key then
                    for i = 1, #key do
                        if key[i] ~= best_key[i] then better = key[i] < best_key[i]; break end
                    end
                end
                if better then best, best_key = option, key end
            end
        end
        if best then
            used[tostring(best.hand_x) .. ":" .. tostring(best.hand_y)] = true
            used[tostring(best.port_x) .. ":" .. tostring(best.port_y)] = true
            if shared then
                shared_ports[machine] = shared_ports[machine] or {}
                shared_ports[machine][#shared_ports[machine] + 1] = {x = best.port_x, y = best.port_y}
            end
            if not best.stay then
                slides[#slides + 1] = {port_id = port.port_id, hop = best}
            end
        end
    end
    if #slides > 0 then Hands.place(materialized, {port_slides = slides}) end
    return #slides
end

function Seat.approach_open(_state)
    return true
end

return Seat

return function(src)
  local old = [[
        local x, y = port_position(work, port)
        local direction = port_travel_direction(work, port)
        local dx, dy]]
  local new = [[
        local x, y = port_position(work, port)
        local direction = port_travel_direction(work, port)
        if x ~= nil and y ~= nil and not (port.kind == "fluid" or port.is_fluid == true or port.fluid_pinned == true) then
            local wanted = port.flow_id or port.full_name
            for _, info in ipairs(work.infos) do
                if transport_kind(info) == "belt" then
                    local tx, ty = tile_of(info)
                    local flow = info.entity.flow_id or info.entity.full_name
                    if tx == math.floor(x) and ty == math.floor(y) and flow == wanted then
                        direction = entity_direction(info) or direction
                        break
                    end
                end
            end
        end
        local dx, dy]]
  local s, e = src:find(old, 1, true); assert(s, "valD")
  return src:sub(1, s - 1) .. new .. src:sub(e + 1)
end

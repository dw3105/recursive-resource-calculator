return function(src)
  local old = [[
    local sink = sink_key(demand.sink, work, demand.sink_port_id)
    local first_segment]]
  local new = [[
    for i = 2, #path - 1 do
        if is_crossing_step(path[i - 1], path[i]) and is_crossing_step(path[i], path[i + 1]) then
            return reject("route-discontinuous")
        end
    end
    local sink = sink_key(demand.sink, work, demand.sink_port_id)
    local first_segment]]
  local s, e = src:find(old, 1, true); assert(s, "E9")
  return src:sub(1, s - 1) .. new .. src:sub(e + 1)
end

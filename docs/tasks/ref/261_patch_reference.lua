return function(src)
  local old = [[
                    for _, e in ipairs(state.work.power.result and state.work.power.result.entities or {}) do
                        if e.kind == "pole" or e.type == "pole" then poles[#poles + 1] = {x=e.x,y=e.y,w=e.w or 1,h=e.h or 1} end
                    end
]]
  local new = old .. [[
                    local tidy_obstacles = {}
                    for _, r in ipairs(poles) do tidy_obstacles[#tidy_obstacles + 1] = r end
                    for _, e in ipairs(state.work.materialized.entities or {}) do
                        if (e.kind == "beacon" or e.type == "beacon") and not e._gone and type(e.x) == "number" then
                            tidy_obstacles[#tidy_obstacles + 1] = {x = e.x, y = e.y, w = e.w or 1, h = e.h or 1, owner = "beacon:" .. tostring(e.id)}
                        end
                    end
]]
  local s, e = src:find(old, 1, true); assert(s, "BP1")
  src = src:sub(1, s - 1) .. new .. src:sub(e + 1)
  local o2 = "state.work.route_state = Route.tidy_begin(state.work.route, {obstacles = poles})"
  local s2, e2 = src:find(o2, 1, true); assert(s2, "BP2")
  return src:sub(1, s2 - 1) .. "state.work.route_state = Route.tidy_begin(state.work.route, {obstacles = tidy_obstacles})" .. src:sub(e2 + 1)
end

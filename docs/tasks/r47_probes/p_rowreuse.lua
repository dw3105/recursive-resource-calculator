-- route: a path may not END on an existing belt that crosses a row feed port in another heading
return function(name, src) if name ~= "logic.bp.route" then return src end
 local old = "        if segment then\n            if segment.fixed and outgoing ~= nil and outgoing ~= segment.direction then return reject(\"occupied\") end\n"
 local new = [[        if segment then
            if index == #path and demand.kind ~= "pipe" and demand.sink and demand.sink.row_port
                and demand.sink.role == "in" and demand.sink.travel_dir ~= nil
                and cell.x == demand.sink.x and cell.y == demand.sink.y
                and not segment.splitter and not segment.underground
                and segment.direction ~= demand.sink.travel_dir then return reject("occupied") end
            if segment.fixed and outgoing ~= nil and outgoing ~= segment.direction then return reject("occupied") end
]]
 local a, b = src:find(old, 1, true); assert(a, "rowreuse anchor"); io.stderr:write("PATCH rowreuse on\n")
 return src:sub(1, a - 1) .. new .. src:sub(b + 1) end

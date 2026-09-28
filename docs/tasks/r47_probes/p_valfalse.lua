-- validate: pipe beside a same-fluid pipe-to-ground span is fine; head-on belt ends are not a loop
return function(name, src) if name ~= "logic.bp.validate" then return src end
 local function rep(a, b) local i, j = src:find(a, 1, true); assert(i, a); src = src:sub(1, i - 1) .. b .. src:sub(j + 1) end
 rep("        local source_flow = source.entity.flow_id\n        for _, candidate in ipairs(work.infos) do",
     "        if transport_kind(source) == \"pipe\" or transport_kind(sink) == \"pipe\" then return nil end\n        local source_flow = source.entity.flow_id\n        for _, candidate in ipairs(work.infos) do")
 rep("                    if next_key and tiles[next_key] then\n                        if colour[next_key] == 1 then",
     "                    if next_key and tiles[next_key] and not (tiles[key].ug ~= \"input\"\n                        and tiles[next_key].d == Grid.dir_opposite(tiles[key].d)) then\n                        if colour[next_key] == 1 then")
 io.stderr:write("PATCH valfalse on\n")
 return src end

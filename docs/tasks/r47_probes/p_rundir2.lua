-- RunDir.choose: an out port's exit tile lies along its travel direction, not its normal
return function(name, src) if name ~= "logic.bp.run_dir" then return src end
 local old = "                                local vx, vy = Grid.dir_vector(q.dir)\n"
 local new = old .. "                                if role == \"out\" and p.travel_dir ~= nil then\n                                    vx, vy = Grid.dir_vector(Grid.rotate_dir(p.travel_dir, placement.dir))\n                                end\n"
 local a, b = src:find(old, 1, true); assert(a, "rundir2 anchor"); io.stderr:write("PATCH rundir2 on\n")
 return src:sub(1, a - 1) .. new .. src:sub(b + 1) end

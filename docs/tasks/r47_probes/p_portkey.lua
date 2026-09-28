-- validate collect_ports: key ports by id + step/block + member (row port ids repeat across blocks)
return function(name, src) if name ~= "logic.bp.validate" then return src end
 local function rep(a, b) local i,j = src:find(a,1,true); assert(i, a); src = src:sub(1,i-1)..b..src:sub(j+1) end
 rep("if id == nil or seen[id] then return end", 'if id == nil then return end; local key = tostring(id).."\\0"..tostring(port.step_id or port.block_id).."\\0"..tostring(port.member_id); if seen[key] then return end')
 rep("seen[id] = true; local copy = copy_table(port)", "seen[key] = true; local copy = copy_table(port)")
 if os.getenv("REKEY") then
  local c = "local ops = math.max(0, math.floor(finite(budget.ops, 1))); local work = state._work"
  rep(c, c.." if not work._rekeyed then work._rekeyed = true; work.ports = collect_ports(work.root); work.port_by_id = port_index(work.ports) end")
 end
 io.stderr:write("PATCH portkey on\n")
 return src end

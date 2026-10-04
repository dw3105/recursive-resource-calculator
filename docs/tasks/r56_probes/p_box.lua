-- LUA_INIT=@p_box.lua: in-memory patch of logic/bp/groups.lua candidate_inserter: machine world boxes computed once
-- per call instead of once per candidate tile x direction x machine (groups.lua:536-538). Then loads fp.lua.
package.path = "./?.lua;" .. package.path
local f = assert(io.open("logic/bp/groups.lua", "r")); local src = f:read("*a"); f:close()
local n1, n2 = 1, 1
if not os.getenv("NOBOX") then
src, n1 = src:gsub("    local occupied = {}\n", function() return "    local occupied = {}; local __bx = {}\n" end, 1)
src, n2 = src:gsub([[
                                local spec = lookup_entity%(catalog, member.name, "machine"%)
                                local box = Geometry.world_box%(member, spec%)
]], function() return [[
                                local box = __bx[member]; if not box then box = Geometry.world_box(member, lookup_entity(catalog, member.name, "machine")); __bx[member] = box end
]] end, 1)
end
assert(n1 == 1 and n2 == 1, "p_box: patch did not apply " .. n1 .. " " .. n2)
if os.getenv("TIMEMACH") then
  local n3
  src, n3 = src:gsub("        else append_inserters%(block, spec.step, machine, catalog, input, flows%) end\n", function() return
    "        else local __t=os.clock(); append_inserters(block, spec.step, machine, catalog, input, flows); local __d=os.clock()-__t; local M=_G.__mach or {n=0,sum=0,max=0}; _G.__mach=M; M.n=M.n+1; M.sum=M.sum+__d; if __d>M.max then M.max=__d; M.at=tostring(machine.id) end end\n" end, 1)
  assert(n3 == 1, "TIMEMACH patch did not apply")
end
if os.getenv("ROT") then
  local a, b
  src, a = src:gsub("    for direction_index, direction in ipairs%(directions%) do\n        for y = machine.y %- radius", function() return
    "    for direction_index, direction in ipairs(directions) do\n        local __pdx, __pdy = Grid.rotate_vector(pickup_offset.x, pickup_offset.y, direction); local __ddx, __ddy = Grid.rotate_vector(drop_offset.x, drop_offset.y, direction)\n        for y = machine.y - radius" end, 1)
  src, b = src:gsub("                    local _, _, pickup_x, pickup_y, drop_x, drop_y =\n                        transfer_cells%(x, y, iw, ih, direction, pickup_offset, drop_offset%)\n", function() return
    "                    local __cx, __cy = x + iw / 2, y + ih / 2; local pickup_x, pickup_y, drop_x, drop_y = cell_of(__cx + __pdx), cell_of(__cy + __pdy), cell_of(__cx + __ddx), cell_of(__cy + __ddy)\n" end, 1)
  assert(a == 1 and b == 1, "ROT patch did not apply " .. a .. " " .. b)
end
if os.getenv("TIMEHAND") then
  local c
  src, c = src:gsub("        local placement = candidate_inserter%(block, machine, hand.role, index, iw, ih, catalog, input,\n            transfer_source_member, target_member, source_cell, target_cell, port_bound, face_column, face%)\n", function() return
    "        local __t = os.clock(); local placement = candidate_inserter(block, machine, hand.role, index, iw, ih, catalog, input,\n            transfer_source_member, target_member, source_cell, target_cell, port_bound, face_column, face); local __d = os.clock() - __t; local H = _G.__hand or {n=0,max=0,over=0}; _G.__hand = H; H.n = H.n + 1; if __d > 0.016 then H.over = H.over + 1 end; if __d > H.max then H.max = __d; H.at = tostring(machine.id) .. ' members=' .. #(block.members or {}) .. ' inserters=' .. #(block.inserters or {}) end\n" end, 1)
  assert(c == 1, "TIMEHAND patch did not apply")
end
if os.getenv("TIMEBUCKET") then
  local c
  src, c = src:gsub('        local block = build_block%(group, work.catalog, relevant_ports%(group, work.ports, work.flows%), work.flows, input, "block:" .. table.concat%(ids, "%+"%)%)\n', function() return
    '        local __t = os.clock(); local block = build_block(group, work.catalog, relevant_ports(group, work.ports, work.flows), work.flows, input, "block:" .. table.concat(ids, "+")); local __d = os.clock() - __t; local B = _G.__bucket or {n=0,over=0,list={}}; _G.__bucket = B; B.n = B.n + 1; if __d > 0.016 then B.over = B.over + 1; B.list[#B.list+1] = string.format("%s=%.0f", table.concat(ids, "+"), __d*1000) end\n' end, 1)
  assert(c == 1, "TIMEBUCKET patch did not apply")
end
package.preload["logic.bp.groups"] = function() return assert(load(src, "@logic/bp/groups.lua"))() end
io.stderr:write("P_BOX patch live box=" .. tostring(not os.getenv("NOBOX")) .. " rot=" .. tostring(os.getenv("ROT") ~= nil) .. "\n")
dofile((os.getenv("FP_LUA") or "fp.lua"))

local H=require "tests.harness"
local Groups=require "logic.bp.groups"
local G=require "logic.bp.grid"
local function run(n,long)
 local catalog={entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},inserter={name="inserter",tile_w=1,tile_h=1}},inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}},belt={items_per_second=15}}
 if long then catalog.long_inserter={name="long-inserter",pickup_offset={x=0,y=2},drop_offset={x=0,y=-2}} end
 local ins,flows={},{}; for i=1,n do ins[i]={flow_id="i"..i}; flows[i]={flow_id="i"..i} end
 local s=Groups.begin({catalog=catalog,plan={steps={{step_id="s",machine="assembler",machine_count=3,recipe="r",inputs=ins,outputs={{flow_id="o"}}}},flows=flows}})
 for _=1,10 do if s.done then break end; Groups.step(s,{ops=10}) end
 return s.result and s.result.candidates[1],s.result and s.result.failures
end
local function key(x,y) return math.floor(x)..":"..math.floor(y) end
local function in_rect(r,x,y) return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
--Every cell of the block holds at most one thing: machine, hand, belt tile, feed tile or far rear port tile.
local function no_overlap(b)
 local used={}
 local function take(x,y,what) local k=key(x,y); H.equal(used[k],nil,what.." at "..k.." collides with "..tostring(used[k])); used[k]=what end
 for _,m in ipairs(b.machines) do for x=m.x,m.x+m.w-1 do for y=m.y,m.y+m.h-1 do take(x,y,"machine") end end end
 for _,h in ipairs(b.inserters) do take(h.x,h.y,"hand "..h.id) end
 for _,r in ipairs(b.belt_runs) do
  for _,t in ipairs(r.tiles) do take(t.x,t.y,"belt "..r.role..(r.far and ":far" or "")) end
  for _,f in ipairs(r.feeds or {}) do take(f.side_tile.x,f.side_tile.y,"feed "..f.flow_id) end
 end
 for k in pairs(used) do local x,y=k:match("(-?%d+):(-?%d+)"); x,y=tonumber(x),tonumber(y)
  H.equal(x>=0 and y>=0 and x<b.w and y<b.h,true,"cell "..k.." inside block "..b.w.."x"..b.h) end
 --A port tile lies outside or on the block edge (like the near run's rear port); it only must not collide.
 for _,p in ipairs(b.ports) do if p.far and p.rear then take(p.attach_dx,p.attach_dy,"rear port "..p.port_id) end end
end
local function far_runs(b) local r={} for _,v in ipairs(b.belt_runs) do if v.far then r[#r+1]=v end end return r end
local function tile_of(run,x,y) for _,t in ipairs(run.tiles) do if t.x==math.floor(x) and t.y==math.floor(y) then return true end end return false end
local function check_long(b,run)
 local m_by={} for _,m in ipairs(b.machines) do m_by[m.id]=m end
 local n=0
 for _,h in ipairs(b.inserters) do if h.long and tile_of(run,h.pickup_position.x,h.pickup_position.y) then
  n=n+1
  local m=m_by[h.machine_id]
  H.equal(math.abs(math.floor(h.pickup_position.y)-h.y),2,"long pickup two tiles out")
  H.equal(math.abs(math.floor(h.drop_position.y)-h.y),2,"long drop two tiles in")
  H.equal(in_rect(m,h.drop_position.x,h.drop_position.y),true,"long drop inside its machine")
  H.equal(h.y==m.y-1 or h.y==m.y+m.h,true,"long hand touches its machine face")
 end end
 return n
end
H.test("3 inputs: near belt 2 flows, far belt 1 flow, long hands reach it, nothing overlaps",function()
 local c=run(3,true); H.equal(c.id,"one","candidate"); local b=c.blocks[1]; H.equal(b.row~=nil,true,"row")
 local near; for _,r in ipairs(b.belt_runs) do if r.role=="in" and not r.far then near=r end end
 H.deep_equal(near.flows,{"i1","i2"},"near flows"); local far=far_runs(b); H.equal(#far,1,"one far run"); H.deep_equal(far[1].flows,{"i3"},"far flows")
 local plain,lng=0,0
 for _,h in ipairs(b.inserters) do if h.long then lng=lng+1; H.equal(h.name,"long-inserter","catalog name") elseif h.role=="input" then plain=plain+1; H.deep_equal(h.flow_ids,{"i1","i2"},"plain hand flows") end end
 H.equal(plain,3,"plain input hands"); H.equal(lng,3,"long hands"); H.equal(check_long(b,far[1]),3,"every long hand reads far belt")
 no_overlap(b)
 local placed=Groups.materialize(b,{x=0,y=0,dir=G.EAST}); H.equal(#placed.belt_runs,#b.belt_runs,"materializes far run")
end)
H.test("4+ inputs: never a row with far belts (unsupported, as before round 29); fallback long-hand facts at 3", function()
 for _,n in ipairs({4,5}) do
  local c=run(n,true)
  for _,b in ipairs(c and c.blocks or {}) do H.equal(#far_runs(b),0,n.." inputs: no far belt") end
 end
 local b3=run(3,false).blocks[1]
 local found=false
 for _,h in ipairs(b3.inserters) do if h.long then found=true; H.equal(h.name,"long-handed-inserter","fallback name"); H.equal(h.pickup_offset.y,2,"fallback pickup"); H.equal(h.drop_offset.y,-2,"fallback drop") end end
 H.equal(found,true,"3 inputs: long hands with fallback facts")
end)
H.done("test_groups_long_hands")

local H=require "tests.harness"
local Grid=require "logic.bp.grid"
local Route=require "logic.bp.route"
local function input()
 return {grid=Grid.new(10,6),catalog={belt={belt="basic-belt",underground="basic-underground",splitter="basic-splitter",items_per_second=10,lane_items_per_second=5,underground_max_distance=5}},blocks={
 {block_id="p",machines={{step_id="p"}},x=7,y=1,w=1,h=1,ports={{port_id="p-out",role="out",kind="item",flow_id="f",rate_per_second=1,attach_dx=0,attach_dy=1,normal_dir=Grid.NORTH,travel_dir=Grid.SOUTH}}},
 {block_id="c",machines={{step_id="c"}},x=1,y=2,w=1,h=1,ports={{port_id="c-in",role="in",kind="item",flow_id="f",rate_per_second=1,attach_dx=1,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.WEST}}}},flows={{flow_id="f",producers={{step_id="p",share_per_second=1}},consumers={{step_id="c",share_per_second=1}}}}}
end
local function routed()
 local s=Route.begin(input()); local n=0; while not s.done and n<1000 do n=n+1; Route.step(s,{ops=100000}) end; return s
end
for _,shape in ipairs(H.shapes()) do
 H.test(shape.." free cell buries a straight belt tile",function()
  local s=routed(); H.equal(s.ok,true,"route succeeds")
  H.equal(Route.free_cell(s,5,2),true,"middle tile is freed")
  local underground=0; for _,e in ipairs(s.result.entities) do if e.ug_role then underground=underground+1 end end
  H.equal(underground,2,"underground pair emitted")
  local carries=false; for _,segment in ipairs(s.result.segments) do if segment.length==2 then for _,a in ipairs(segment.allocations) do if a.flow_id=="f" then carries=true end end end end
  H.equal(carries,true,"underground segment retains the routed flow")
  H.equal(#s.result.bindings,1,"route binding remains connected")
 end)
 H.test(shape.." cannot free a port-adjacent or turn tile",function()
  local s=routed()
  H.equal(Route.free_cell(s,7,2),false,"port-adjacent tile refused")
  H.equal(Route.free_cell(s,4,1),false,"empty/turn-side tile refused")
 end)
end
H.done("test_route_free_cell")

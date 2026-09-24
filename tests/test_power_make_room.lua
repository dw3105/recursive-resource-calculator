local H=require "tests.harness"
local Power=require "logic.bp.power"
local function run(input)
 local s=Power.begin(input); local n=0; while not s.done and n<30000 do n=n+1; Power.step(s,{ops=1000}) end
 H.equal(s.done,true,"power completes"); return s.result
end
local base={grid_w=7,grid_h=7,consumers={{id="m",rect={x=3,y=3,w=1,h=1}}},pole={name="pole",tile_w=1,tile_h=1,supply_w=0.5,supply_h=0.5,wire_reach=9},limits={max_poles=2}}
local function occupied()
 return {{rect={x=3,y=3,w=1,h=1},owner="belt",kind="belt"}}
end
for _,shape in ipairs(H.shapes()) do
 H.test(shape.." make_room can clear a belt cell for pole coverage",function()
  local a={}; for k,v in pairs(base) do a[k]=v end; a.occupied=occupied()
  local no=run(a); H.equal(#no.uncovered,1,"without callback remains uncovered")
  local calls={}; a.make_room=function(x,y) calls[#calls+1]={x,y}; return true end
  local yes=run(a); H.equal(#yes.uncovered,0,"callback frees pole location")
  local found=false; for _,e in ipairs(yes.entities) do if e.x==3 and e.y==3 then found=true end end
  H.equal(found,true,"pole is placed on freed cell")
  H.equal(#calls>0,true,"callback invoked")
 end)
 H.test(shape.." refused make_room leaves the consumer uncovered",function()
  local a={}; for k,v in pairs(base) do a[k]=v end; a.occupied=occupied(); a.make_room=function() return false end
  local result=run(a); H.equal(#result.uncovered,1,"consumer remains uncovered")
  H.equal(#result.entities,0,"no blocked spot selected")
 end)
end
H.done("test_power_make_room")

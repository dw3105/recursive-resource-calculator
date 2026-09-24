local H=require "tests.harness"
local Groups=require "logic.bp.groups"
local catalog={entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},inserter={name="inserter",tile_w=1,tile_h=1}},inserter={name="inserter"},belt={items_per_second=15}}
local function plan()
 return {steps={{step_id="a",machine="assembler",machine_count=3,recipe="r",inputs={{flow_id="i"}},outputs={{flow_id="o"}},groups={}},{step_id="b",machine="assembler",machine_count=2,recipe="s",inputs={{flow_id="i2"}},outputs={{flow_id="o2"}},groups={}}}}
end
local function finish(input) local s=Groups.begin(input); for _=1,20 do if s.done then break end; Groups.step(s,{ops=10}) end; return s.result end
H.test("one candidate groups each step once and carries ring bump",function()
 local p=plan(); local base=finish({plan=p,catalog=catalog}); local bumped=finish({plan=p,catalog=catalog,ring_bump=1})
 H.equal(#base.candidates,1,"one candidate"); H.equal(base.candidates[1].id,"one","stable id")
 H.equal(#base.candidates[1].blocks,2,"one block per step")
 for bi,b in ipairs(base.candidates[1].blocks) do for i,z in ipairs(b.buffer_zones) do H.equal(bumped.candidates[1].blocks[bi].buffer_zones[i].ring,z.ring+1,"bumped ring") end end
end)
H.done("test_groups_one")

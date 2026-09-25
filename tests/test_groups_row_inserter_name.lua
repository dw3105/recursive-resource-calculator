local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Fixture = require "tests.fixtures.row_block"

local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
    inserter={name="fast-inserter",tile_w=1,tile_h=1}},
    inserter={name="fast-inserter",items_per_second=15},
    long_inserter={name="long-handed-inserter"}, belt={items_per_second=15}}
local copper, gear, pack = Fixture.COPPER, Fixture.GEAR, Fixture.PACK
local plan = {steps={{step_id="science",machine="assembler",machine_count=4,recipe="automation-science-pack",
    inputs={{flow_id=copper,rate_per_second=4},{flow_id=gear,rate_per_second=4}},
    outputs={{flow_id=pack,rate_per_second=4}}}},flows={{flow_id=copper},{flow_id=gear},{flow_id=pack}},ports={}}

for _,shape in ipairs(H.shapes()) do
 H.test(shape.." row hands use the picked catalog inserter",function()
  local s=Groups.begin({plan=plan,catalog=catalog,_force_multi_flow_hands=true})
  for _=1,8 do if s.done then break end; Groups.step(s,{ops=1}) end
  local row
  for _,candidate in ipairs(s.result.candidates) do
   for _,block in ipairs(candidate.blocks) do if block.row then row=block end end
  end
  H.equal(row~=nil,true,"row block exists")
  if row then
   H.equal(#row.inserters>0,true,"row hands exist")
   for _,hand in ipairs(row.inserters) do H.equal(hand.name,"fast-inserter","picked name used for every row hand") end
  end
 end)
end
H.done("test_groups_row_inserter_name")

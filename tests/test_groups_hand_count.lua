local H=require "tests.harness"
local Groups=require "logic.bp.groups"
for _,shape in ipairs(H.shapes()) do
 H.test(shape.." flow rate creates enough individual hands and ports",function()
  local catalog={entity={assembler={name="assembler",tile_w=3,tile_h=3},inserter={name="inserter",tile_w=1,tile_h=1}},
   inserter={name="inserter",items_per_second=4.62}}
  local plan={steps={{step_id="s",machine="assembler",machine_count=1,recipe="r",
   inputs={{flow_id="item/cable",rate_per_second=15},{flow_id="item/slow",rate_per_second=3}}}},
   flows={{flow_id="item/cable"},{flow_id="item/slow"}}}
  local s=Groups.begin({catalog=catalog,plan=plan})
  for _=1,100 do if s.done then break end; Groups.step(s,{ops=10}) end
  local b=s.result.candidates[1].blocks[1]; local count={}
  for _,h in ipairs(b.inserters) do
   count[h.flow_id]=(count[h.flow_id] or 0)+1
   H.equal(h.rate_per_second<=4.62+1e-9,true,"each hand stays within measured capacity")
  end
  H.equal(count["item/cable"],4,"15/s needs four hands")
  H.equal(count["item/slow"],1,"3/s needs one hand")
  local ports={}
  for _,p in ipairs(b.ports) do if p.flow_id then ports[p.flow_id]=(ports[p.flow_id] or 0)+1 end end
  H.equal(ports["item/cable"],4,"each cable hand has its own port")
  H.equal(ports["item/slow"],1,"slow flow has its own port")
  local tiles={}
  for _,p in ipairs(b.ports) do if p.inserter_id then
   local k=tostring(p.attach_dx)..":"..tostring(p.attach_dy)
   H.equal(tiles[k],nil,"each port uses a free face tile"); tiles[k]=true
  end end
 end)
end
H.done("test_groups_hand_count")

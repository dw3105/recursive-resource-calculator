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
H.test("3 inputs create far input run and long hands",function()
 local c=run(3,true); H.equal(c.id,"one","candidate"); local b=c.blocks[1]; H.equal(b.row~=nil,true,"row")
 local nr,nf,plain,lng=0,0,0,0
 for _,r in ipairs(b.belt_runs) do if r.role=="in" then nr=nr+1 end; if r.far then nf=nf+1 end end
 for _,h in ipairs(b.inserters) do if h.long then lng=lng+1 else plain=plain+1 end end
 H.equal(nr,2,"two input runs"); H.equal(nf,1,"far marker"); H.equal(plain,6,"plain hands"); H.equal(lng,3,"long hands")
 local h; for _,v in ipairs(b.inserters) do if v.long then h=v end end
 local ok=false; for _,r in ipairs(b.belt_runs) do if r.far then for _,t in ipairs(r.tiles) do  if math.floor(h.pickup_position.x)==t.x and math.floor(h.pickup_position.y)==t.y then ok=true end end end end
 H.equal(ok,true,"long pickup on far belt"); local m=b.machines[1]; H.equal(h.drop_position.y>=m.y and h.drop_position.y<m.y+m.h,true,"drop in machine")
 local placed=Groups.materialize(b,{x=0,y=0,dir=G.EAST}); H.equal(#placed.belt_runs,#b.belt_runs,"materializes far run")
end)
H.test("5 inputs far run output face and 7 inputs fail",function()
 local c=run(5,false); local farout=false; for _,r in ipairs(c.blocks[1].belt_runs) do if r.far and r.role=="out" then farout=true end end; H.equal(farout,true,"far output run")
 local fallback=run(3,false); local found=false; for _,h in ipairs(fallback.blocks[1].inserters) do if h.long then found=true; H.equal(h.name,"long-handed-inserter","fallback prototype name"); H.equal(h.pickup_offset.y,2,"fallback pickup offset"); H.equal(h.drop_offset.y,-2,"fallback drop offset") end end; H.equal(found,true,"fallback long hands")
 local seven,failures=run(7,false); H.equal(seven,nil,"no candidate for row input limit"); H.equal(failures[1].code,"BP_P_NO_FIT","failure code"); H.equal(failures[1].name,"row-inputs","failure name")
end)
H.done("test_groups_long_hands")

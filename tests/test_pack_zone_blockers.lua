local H=require 'tests.harness'
local Grid=require 'logic.bp.grid'
local Pack=require 'logic.bp.pack'
local function run(input)
 local s=Pack.begin(input); while not s.done do Pack.step(s,{ops=100000}) end; return s
end
local function block() return {block_id='m',w=2,h=2,allowed_dirs={Grid.NORTH},buffer_zones={{x=0,y=0,w=2,h=2,ring=0,key='m'}}} end
H.test('zone blocker skips the only tight origin',function()
 local s=run{area=Grid.rect(0,0,4,2),zone_blockers={Grid.rect(0,0,1,1)},blocks={block()}}
 H.equal(s.ok,true); H.equal(s.result.placements[1].x,1)
end)
H.test('zone blockers can make placement impossible',function()
 local s=run{area=Grid.rect(0,0,2,2),zone_blockers={Grid.rect(0,0,2,2)},blocks={block()}}
 H.equal(s.ok,false); H.equal(s.errors[1].code,'BP_P_NO_FIT')
end)
H.test('the whole ring keeps clear of a blocker, not only the machine footprint',function()
 local b={block_id='m',w=2,h=2,allowed_dirs={Grid.NORTH},buffer_zones={{x=0,y=0,w=2,h=2,ring=2,key='m'}}}
 local s=run{area=Grid.rect(0,0,12,2),zone_blockers={Grid.rect(0,0,1,1)},blocks={b}}
 H.equal(s.ok,true); H.equal(s.result.placements[1].x,3,'ring 2 from x=3 is the first clear origin')
end)
H.done('test_pack_zone_blockers')

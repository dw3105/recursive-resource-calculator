local H=require 'tests.harness'
local Grid=require 'logic.bp.grid'
local Pack=require 'logic.bp.pack'
local function run(input) local s=Pack.begin(input); while not s.done do Pack.step(s,{ops=100000}) end; return s end
H.test('links place the consumer beside producer output',function()
 local a={block_id='a',w=2,h=2,allowed_dirs={Grid.NORTH},ports={{port_id='out',role='out',attach_dx=2,attach_dy=0}}}
 local b={block_id='b',w=2,h=2,allowed_dirs={Grid.NORTH}}
 local s=run{area=Grid.rect(0,0,12,8),blocks={a,b},links={{a={block_id='a',port_id='out'},b={block_id='b'}}}}
 H.equal(s.ok,true); H.equal(s.result.placements[2].x,3)
end)
H.test('allowed rotation puts the linked port beside its partner',function()
 local a={block_id='a',w=2,h=2,allowed_dirs={Grid.NORTH},ports={{port_id='out',role='out',attach_dx=2,attach_dy=0,inserter_id='a:hand'}}}
 local b={block_id='b',w=2,h=1,allowed_dirs={Grid.NORTH,Grid.EAST},ports={{port_id='in',role='in',attach_dx=0,attach_dy=-1,inserter_id='b:hand'}}}
 local s=run{area=Grid.rect(0,0,10,8),blocks={a,b},links={{a={block_id='a',port_id='out'},b={block_id='b',port_id='in'}}}}
 H.equal(s.ok,true); H.equal(s.result.placements[2].dir,Grid.EAST)
end)
H.test('edge links pull block left',function()
 local s=run{area=Grid.rect(0,0,12,8),blocks={{block_id='a',w=2,h=2}},links={{a={block_id='a'},b={edge='left'}}}}
 H.equal(s.result.placements[1].x,0)
end)
H.test('no links retain legacy placements',function()
 local input={area=Grid.rect(0,0,12,8),blocks={{block_id='a',w=2,h=2},{block_id='b',w=3,h=2}}}
 local a,b=run(input),run{area=input.area,blocks=input.blocks,links={}}
 H.deep_equal(a.result.placements,b.result.placements)
end)
H.done('test_pack_links')

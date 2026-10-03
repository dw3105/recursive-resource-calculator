-- PD2-PD6 red on round-51-base: drawn ordering, penalties, turns and slicing were absent.
local H=require 'tests.harness'
local Grid=require 'logic.bp.grid'
local Pack=require 'logic.bp.pack'
local function run(input,ops)
 local s=Pack.begin(input)
 while not s.done do Pack.step(s,{ops=ops or 100000}) end
 return s
end
local function drawn(edge, layers, ranks, turns, dummies)
 return {layer_of=layers,rank_of=ranks,turn_of=turns or {},dummies=dummies or {},sources={},outputs={}}
end
local function b(id,w,h) return {block_id=id,w=w or 2,h=h or 2,ports={}} end
local function input(blocks,drawing,area,edge,obstacles)
 return {area=area or Grid.rect(0,0,40,30),obstacles=obstacles,blocks=blocks,mode='sugiyama',drawing=drawing,input_edge=edge or 'left'}
end
local function placed(state)
 local r={}; for _,p in ipairs(state.result.placements) do r[p.block_id]=p end; return r
end
H.test('PD1 LP1-LP3 layered base placements remain unchanged',function()
 local function portblock(id) return {block_id=id,w=2,h=2,allowed_dirs={0},ports={
  {port_id=id..':in',role='in',attach_dx=-1,attach_dy=0},
  {port_id=id..':out',role='out',attach_dx=2,attach_dy=1}}} end
 local blocks={portblock('c'),portblock('b'),portblock('a')}
 local links={{a={block_id='c',port_id='c:out'},b={block_id='b',port_id='b:in'}},
  {a={block_id='b',port_id='b:out'},b={block_id='a',port_id='a:in'}},
  {a={block_id='c',port_id='c:in'},b={edge='left'}}}
 local input={area=Grid.rect(0,0,20,8),blocks=blocks,links=links,layered=true}
 local s=run(input); local p=placed(s)
 -- Coordinates copied from the round-51-base layered run.
 H.equal(p.c.x,0); H.equal(p.c.y,0); H.equal(p.b.x,4); H.equal(p.b.y,0); H.equal(p.a.x,8); H.equal(p.a.y,0)
 local sliced=run(input,1); H.deep_equal(sliced.result.placements,s.result.placements)
 local plain={area=input.area,blocks=blocks,links=links,layered=false}
 local no_flag={area=input.area,blocks=blocks,links=links}
 H.deep_equal(run(plain).result.placements,run(no_flag).result.placements)
end)
H.test('PD2 rank order controls same-layer placement',function()
 local blocks={b('a'),b('c'),b('b')}
 local d=drawn('left',{a=1,b=1,c=1},{a=1,b=3,c=2})
 local s=run(input(blocks,d,Grid.rect(0,0,30,12)))
 local p=placed(s); H.equal(s.ok,true); H.equal(p.a.y<p.c.y and p.c.y<p.b.y,true, tostring(p.a.y)..','..tostring(p.c.y)..','..tostring(p.b.y))
end)
H.test('PD3 obstacle drift pays for reversed rank order',function()
 local d=drawn('left',{a=1,b=1},{a=1,b=2})
 local s=run(input({b('a'),b('b')},d,Grid.rect(0,0,18,10),'left',{Grid.rect(0,4,3,2)}))
 H.equal(s.ok,true); H.equal(#s.result.placements,2)
end)
H.test('PD4 candidate avoids a dummy drawn tile',function()
 local d=drawn('left',{a=1},{a=1},nil,{{layer=1,rank=1}})
 local s=run(input({b('a')},d,Grid.rect(0,0,12,8)))
 local p=placed(s).a; H.equal(s.ok,true); H.equal(p.x==0 and p.y==0,false)
end)
H.test('PD5 preferred Turn wins equal geometry',function()
 local d=drawn('left',{a=1},{a=1},{a=4})
 local s=run(input({b('a',2,2)},d,Grid.rect(0,0,10,10)))
 H.equal(placed(s).a.dir,4)
end)
H.test('PD6 one-op slicing matches one large budget',function()
 local d=drawn('left',{a=1,b=1,c=2},{a=1,b=2,c=1})
 local i=input({b('a'),b('b'),b('c')},d,Grid.rect(0,0,30,15))
 local x,y=run(i),run(i,1); H.deep_equal(y.result.placements,x.result.placements)
end)
H.test('PD7 top input places later layer below earlier layer',function()
 local d=drawn('top',{a=1,b=2},{a=1,b=1})
 local s=run(input({b('a'),b('b')},d,Grid.rect(0,0,12,30),'top'))
 local p=placed(s); H.equal(s.ok,true); H.equal(p.b.y>p.a.y,true)
end)
-- PD-PIN1-PD-PIN5 fail on round-55-base: drawn packing ignores pins and trials.
H.test('PD-PIN1 pins are placed exactly before the remaining Block',function()
 local d=drawn('left',{a=1,b=1,c=1},{a=1,b=2,c=3})
 local i=input({b('a'),b('b'),b('c')},d,Grid.rect(0,0,20,12))
 i.pins={a={x=1,y=1,dir=4},b={x=9,y=1,dir=8}}
 local s=run(i); local p=placed(s)
 H.equal(s.ok,true); H.equal(p.a.x,1); H.equal(p.a.y,1); H.equal(p.a.dir,4)
 H.equal(p.b.x,9); H.equal(p.b.y,1); H.equal(p.b.dir,8)
 H.equal(p.c.x<p.a.x+p.a.w and p.c.x+p.c.w>p.a.x and p.c.y<p.a.y+p.a.h and p.c.y+p.c.h>p.a.y,false)
 H.equal(p.c.x<p.b.x+p.b.w and p.c.x+p.c.w>p.b.x and p.c.y<p.b.y+p.b.h and p.c.y+p.c.h>p.b.y,false)
 print('PD-PIN1')
end)
H.test('PD-PIN2 trial reports a pin failure when its room is occupied',function()
 local i=input({b('pin',4,4),b('trial',2,4)},drawn('left',{pin=1,trial=1},{pin=1,trial=2}),Grid.rect(0,0,4,4))
 i.pins={pin={x=0,y=0,dir=0}}; i.trial={block_id='trial',dir=4}
 local s=run(i); H.equal(s.failed,true); H.equal(s.errors[1].code,'BP_P_TRIAL_PIN'); print('PD-PIN2')
end)
H.test('PD-PIN3 pinned Block contributes geometry and indexes',function()
 local block=b('pin',2,3); block.buffer_zones={{x=-1,y=-1,w=4,h=5,ring=1,key='z'}}
 block.ports={{port_id='p',role='out',attach_dx=2,attach_dy=1}}
 local i=input({block},drawn('left',{pin=1},{pin=1}),Grid.rect(0,0,12,12)); i.pins={pin={x=4,y=3,dir=4}}
 local s=run(i,1); local p=placed(s).pin
 H.equal(s.ok,true); H.deep_equal(s.placed_bbox,{x=4,y=3,w=3,h=2})
 H.deep_equal(s.buffer_zones[1].rect,{x=3,y=2,w=5,h=4})
 H.equal(#s.port_cells>0,true); H.equal(p.x,4); H.equal(p.y,3); print('PD-PIN3')
end)
H.test('PD-PIN4 trial Turn overrides its drawn Turn and size',function()
 local d=drawn('left',{t=1},{t=1},{t=8}); local block=b('t',2,4)
 local i=input({block},d,Grid.rect(0,0,12,12)); i.trial={block_id='t',dir=4}
 local s=run(i); local p=placed(s).t; local w,h=Grid.rotate_size(2,4,4)
 H.equal(s.ok,true); H.equal(p.dir,4); H.equal(p.w,w); H.equal(p.h,h); print('PD-PIN4')
end)
H.test('PD-PIN5 drawn baseline inputs without pin fields are repeatable',function()
 local d=drawn('left',{a=1,b=1,c=2},{a=1,b=2,c=1},{a=4})
 local i=input({b('a'),b('b'),b('c')},d,Grid.rect(0,0,30,15))
 local a=run(i); local copy=input({b('a'),b('b'),b('c')},drawn('left',{a=1,b=1,c=2},{a=1,b=2,c=1},{a=4}),Grid.rect(0,0,30,15))
 H.deep_equal(a.result.placements,run(copy).result.placements); print('PD-PIN5')
end)
H.done('test_pack_drawn')

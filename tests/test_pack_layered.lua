local H=require 'tests.harness'
local Grid=require 'logic.bp.grid'
local Pack=require 'logic.bp.pack'
local function run(input,ops) local s=Pack.begin(input); local steps=0
 while not s.done do Pack.step(s,{ops=ops or 100000}); steps=steps+1 end; return s,steps end
local function block(id) return {block_id=id,w=2,h=2,allowed_dirs={Grid.NORTH},
 ports={{port_id=id..':in',role='in',attach_dx=-1,attach_dy=0},{port_id=id..':out',role='out',attach_dx=2,attach_dy=1}}} end
local function chain(layered)
 --Listed consumer first: layered pack must still put the raw-input end on the left.
 local a,b,c=block('a'),block('b'),block('c')
 return {area=Grid.rect(0,0,20,8),blocks={a,b,c},layered=layered,links={
  {a={block_id='c',port_id='c:out'},b={block_id='b',port_id='b:in'}},
  {a={block_id='b',port_id='b:out'},b={block_id='a',port_id='a:in'}},
  {a={block_id='c',port_id='c:in'},b={edge='left'}}}}
end
local function by_id(s) local t={} for _,p in ipairs(s.result.placements) do t[tostring(p.block_id)]=p end return t end
H.test('LP1 layered pack puts each block right of the block that feeds it',function()
 local s=run(chain(true)); H.equal(s.ok,true)
 local p=by_id(s)
 H.equal(p.c.x<p.b.x,true,'c feeds b, so c is left of b'); H.equal(p.b.x<p.a.x,true,'b feeds a, so b is left of a')
end)
H.test('LP2 a layered pick sliced into tiny ticks lands where one big tick lands',function()
 local big=run(chain(true)); local small,steps=run(chain(true),5)
 H.equal(steps>3*#big.result.placements,true,'the ring walk spans many ticks')
 H.deep_equal(small.result.placements,big.result.placements)
end)
H.test('LP3 without layered the pack keeps its MaxRects placements',function()
 local a=run(chain(nil)); local b=run(chain(false))
 H.deep_equal(a.result.placements,b.result.placements)
 H.equal(a.stats.scans>0,true,'MaxRects scanned free regions')
end)
H.done('test_pack_layered')

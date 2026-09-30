-- SD1-SD3 red on round-51-base: search had no draw phase or drawn edge metadata.
local H=require 'tests.harness'
local D=require 'tests.fixtures.search_doubles'
local Search=require 'logic.bp.search'
local Pack=require 'logic.bp.pack'
local Groups=require 'logic.bp.groups'
local FlowDraw=require 'logic.bp.flow_draw'
local Orient=require 'logic.bp.orient'
H.test('SD1 sugiyama search visits draw before pack and finishes sliced',function()
 local old=Pack.mode; Pack.mode='sugiyama'
 local ok,log=D.run({},function()
  local s=Search.begin(D.input())
  local saw_draw,saw_pack=false,false
  for _=1,30000 do
   if s.done then break end
   if s.phase=='draw' then saw_draw=true elseif s.phase=='pack' and saw_draw then saw_pack=true end
   Search.step(s,{ops=1})
  end
  H.equal(saw_draw,true); H.equal(saw_pack,true); H.equal(s.done,true); H.equal(s.ok,true)
  H.equal(#(s.work.pack.result and s.work.pack.result.placements or {}),1)
  return s
 end)
 Pack.mode=old
 H.equal(ok.done,true)
end)
H.test('SD2 external links carry flow id and direction',function()
 local old=Pack.mode; Pack.mode='layered'
 local oldstep=Groups.step
 local state,log=D.run({},function()
  Groups.step=function(stage,budget)
   if budget.ops>0 then budget.ops=budget.ops-1; stage.result={candidates={{id='cand',blocks={{id='one',block_id='one',w=1,h=1,ports={
    {port_id='i',step_id='one',flow_id='f',role='in'}, {port_id='o',step_id='one',flow_id='f',role='out'}
   }}}}}}; stage.done,stage.ok=true,true end
   return stage
  end
  local i=D.input({plan_result={steps={},flows={
   {flow_id='f',producers={{step_id='$external'},{step_id='one'}},consumers={{step_id='one'},{step_id='$external'}}}},ports={}}})
  return D.finish(Search,Search.begin(i))
 end)
 Groups.step=oldstep
 Pack.mode=old
 local found_in,found_out=false,false
 for _,l in ipairs(log.pack[1].links) do
  if l.ext=='in' and l.flow_id=='f' then found_in=true end
  if l.ext=='out' and l.flow_id=='f' then found_out=true end
 end
 H.equal(found_in,true); H.equal(found_out,true); H.equal(state.ok,true)
end)
H.test('SD3 layered mode never enters draw phase',function()
 local old=Pack.mode; Pack.mode='layered'
 local state=D.run({},function()
  local s=Search.begin(D.input()); local saw=false
  for _=1,30000 do if s.done then break end; if s.phase=='draw' then saw=true end; Search.step(s,{ops=1}) end
  return {done=s.done,saw=saw}
 end)
 Pack.mode=old
 H.equal(state.done,true); H.equal(state.saw,false)
end)
--Round 51 integration (magenta drawn ended BP_FAIL_NO_LAYOUT through the MaxRects fallback, 2026-09-30): a rejected
--drawn candidate falls back to today's layered pack, never straight to MaxRects. Red without drawn_off in search.
H.test('SD4 rejected drawn candidate falls back to layered, then MaxRects',function()
 local old=Pack.mode; Pack.mode='sugiyama'
 local seen=D.run({validate_fails=2},function()
  local inner, modes = Pack.begin, {}
  Pack.begin=function(input) modes[#modes+1]=(input.mode or 'plain')..':'..tostring(input.layered); return inner(input) end
  D.finish(Search,Search.begin(D.input()))
  Pack.begin=inner
  return modes
 end)
 Pack.mode=old
 H.equal(seen[1],'sugiyama:true','first pack is drawn')
 H.equal(seen[2],'plain:true','after the drawn reject: layered, not MaxRects')
 H.equal(seen[3],'plain:false','after the layered reject: MaxRects')
end)
--SD5-SD8 red on base 2026-09-30: drawing received no real orientation feed and search chose orientations after it.
H.test('SD5 draw nodes receive only buildable Turn and Flip port geometry',function()
 local old=Pack.mode; Pack.mode='sugiyama'
 local oldbegin,oldstep=FlowDraw.begin,FlowDraw.step; local captured
 FlowDraw.begin=function(i) captured=i; return {done=true,ok=true,result={turn_of={fluid=0,item=0},mirror_of={}}} end
 FlowDraw.step=function(s) return s end
 local function groupstep(s,b)
  if b.ops>0 then b.ops=b.ops-1; local function block(id,kind,x)
   return {id=id,block_id=id,w=2,h=2,ports={{port_id=id..'p',step_id=id,flow_id=id,role='in',kind=kind,attach_dx=x,attach_dy=0}}}
  end
  s.result={candidates={{id='c',blocks={block('fluid','fluid',-1),block('item','item',-1)}}}}; s.done,s.ok=true,true end; return s
 end
 local oldreorient=Groups.reorient
 Groups.reorient=function(_,b,o) if o.mirror then local c={}; for k,v in pairs(b) do c[k]=v end; c.ports={{port_id=b.ports[1].port_id,role='in',kind='fluid',attach_dx=b.w,attach_dy=0}}; return c end return b end
 local state=D.run({},function() Groups.step=groupstep; return D.finish(Search,Search.begin(D.input())) end)
 Groups.reorient=oldreorient; FlowDraw.begin=oldbegin; FlowDraw.step=oldstep; Pack.mode=old
 local by={}; for _,n in ipairs(captured.nodes) do by[n.id]=n end
 local nf,ni=0,0; for _ in pairs(by.fluid.orients) do nf=nf+1 end; for _ in pairs(by.item.orients) do ni=ni+1 end
 H.equal(nf,8); H.equal(ni,4); H.equal(by.fluid.orients['0|0'].ports.fluidp.side,1); H.equal(by.fluid.orients['4|0'].ports.fluidp.side,2)
end)
H.test('SD6 applies the drawing Flip and passes its Turn to drawn pack',function()
 local old=Pack.mode; Pack.mode='sugiyama'; local oldbegin,oldstep=FlowDraw.begin,FlowDraw.step
 FlowDraw.begin=function() return {done=true,ok=true,result={turn_of={b=8},mirror_of={b=1}}} end; FlowDraw.step=function(s) return s end
 local oldreorient=Groups.reorient; local mirrored
 Groups.reorient=function(_,b,o) if o.mirror then mirrored=true; local n={}; for k,v in pairs(b) do n[k]=v end; n.mirror_variant=true; return n end return b end
 local dirs,block_mirror
 local result,log=D.run({},function()
  Groups.step=function(s,b)
   if b.ops>0 then
    b.ops=b.ops-1
    local port={port_id='p',step_id='one',flow_id='f',role='in',kind='fluid',attach_dx=-1,attach_dy=0}
    local block={id='b',block_id='b',w=2,h=2,ports={port}}
    s.result={candidates={{id='c',blocks={block}}}}
    s.done,s.ok=true,true
   end
   return s
  end
  local begin=Pack.begin
  Pack.begin=function(input) dirs=input.blocks[1].allowed_dirs; block_mirror=input.blocks[1].mirror_variant; return begin(input) end
  return D.finish(Search,Search.begin(D.input()))
 end)
 Groups.reorient=oldreorient; FlowDraw.begin=oldbegin; FlowDraw.step=oldstep; Pack.mode=old
 H.equal(mirrored,true); H.equal(block_mirror,true); H.deep_equal(dirs,{8}); H.equal(log.pack[1].links~=nil,true); H.equal(result.ok,true)
end)
H.test('SD7 drawn diagnostics export scoring and pack override counters',function()
 local old=Pack.mode; Pack.mode='sugiyama'; local oldbegin,oldstep=FlowDraw.begin,FlowDraw.step
 FlowDraw.begin=function() return {done=true,ok=true,result={crossings=2,score=3,ug_pred=2,turn_of={b=0},mirror_of={}}} end; FlowDraw.step=function(s) return s end
 local s=D.run({},function() return D.finish(Search,Search.begin(D.input())) end)
 FlowDraw.begin=oldbegin; FlowDraw.step=oldstep; Pack.mode=old
 H.equal(type(s.result.search.draw.ug_pred),'number'); H.equal(type(s.result.search.draw.dir_overrides),'number')
end)
H.test('SD8 drawn path never calls Orient.choose',function()
 local old=Pack.mode; Pack.mode='sugiyama'; local choose,calls=Orient.choose,0
 Orient.choose=function(...) calls=calls+1; return choose(...) end
 D.run({},function() return D.finish(Search,Search.begin(D.input())) end)
 Orient.choose=choose; Pack.mode=old; H.equal(calls,0)
end)
H.done('test_search_draw_phase')

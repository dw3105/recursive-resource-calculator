-- SD1-SD3 red on round-51-base: search had no draw phase or drawn edge metadata.
local H=require 'tests.harness'
local D=require 'tests.fixtures.search_doubles'
local Search=require 'logic.bp.search'
local Pack=require 'logic.bp.pack'
local Groups=require 'logic.bp.groups'
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
H.done('test_search_draw_phase')

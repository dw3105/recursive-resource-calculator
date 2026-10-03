-- TT1-TT12 red on round-55-base: a valid drawn sheet never tries another Turn. 2026-10-03.
local H=require 'tests.harness'
local D=require 'tests.fixtures.search_doubles'
local Search=require 'logic.bp.search'
local Pack=require 'logic.bp.pack'
local MaterialCost=require 'logic.bp.material_cost'

H.test('TT1 cheaper turned drawn Block wins',function()
 local old_mode, old_cost, old_flow=Pack.mode,MaterialCost.blueprint,MaterialCost.by_flow
 Pack.mode='sugiyama'
 MaterialCost.blueprint=function(_,entities) return entities[1] and entities[1].x==0 and 100 or 80,0 end
 MaterialCost.by_flow=function() return {f=1} end
 local state=D.run({},function(log)
  local s=Search.begin(D.input()); local ticks=0
  while not s.done and ticks<3000 do ticks=ticks+1; Search.step(s,{ops=1000}) end
  H.equal(s.done,true,'stuck phase '..tostring(s.phase))
  return s
 end)
 Pack.mode,MaterialCost.blueprint,MaterialCost.by_flow=old_mode,old_cost,old_flow
 H.equal(state.ok,true); H.equal(state.result.search.trial.won,1); print('TT1')
end)

H.done('test_turn_trial')

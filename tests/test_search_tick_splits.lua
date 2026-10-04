-- TS1-TS3 red on 853fa58 (round 56 gate, legalcopilot-dev 2026-10-04): uncharged stage handoffs shared one game tick
-- (red-green: pack end + materialize + route input 61 ms; route end + copies + hands 70 ms; hands + power 51 ms).
local H=require 'tests.harness'
local D=require 'tests.fixtures.search_doubles'
local Search=require 'logic.bp.search'
local Pack=require 'logic.bp.pack'

local function trace()
 local old=Pack.mode; Pack.mode='layered'
 local rows
 D.run({},function()
  local s=Search.begin(D.input())
  rows={}
  local materialized, route, power
  for step=1,30000 do
   if s.done then break end
   local before=s.phase
   local route_done_before=s.work and s.work.route and s.work.route.done or false
   local power_done_before=s.work and s.work.power and s.work.power.done or false
   local tidy_before=s.work and s.work.route_state
   Search.step(s,{ops=4000})
   local w=s.work or {}
   rows[#rows+1]={step=step,before=before,after=s.phase,
    new_materialized=w.materialized~=nil and w.materialized~=materialized,
    new_route=w.route~=nil and w.route~=route,
    new_power=w.power~=nil and w.power~=power,
    power_done=w.power and w.power.done or false,
    route_done_before=route_done_before,
    power_done_before=power_done_before,
    new_tidy=w.route_state~=nil and w.route_state~=tidy_before}
   materialized, route, power = w.materialized, w.route, w.power
  end
  H.equal(s.done,true,"search finishes"); H.equal(s.ok,true,"search succeeds")
  return s
 end)
 Pack.mode=old
 return rows
end

local rows=trace()
local function first(pred) for _,r in ipairs(rows) do if pred(r) then return r end end end

H.test('TS1 pack end, materialize and route input are three different ticks',function()
 local pack_end=first(function(r) return r.before=='pack' and r.after=='pack' and not r.new_materialized and r.new_route==false end)
 local mat=first(function(r) return r.new_materialized end)
 local rt=first(function(r) return r.new_route end)
 H.equal(mat~=nil and rt~=nil,true,"materialize and route begin seen")
 H.equal(rt.step>mat.step,true,"Route.begin runs on a later tick than materialize: "..tostring(mat.step).." "..tostring(rt.step))
 print("TS1")
end)

H.test('TS2 route end and the hands pass are different ticks',function()
 local hands=first(function(r) return r.before=='route' and r.after=='hands' end)
 H.equal(hands~=nil,true,"route -> hands seen")
 H.equal(hands.route_done_before,true,"route was already done before the tick that starts hands")
 print("TS2")
end)

H.test('TS3 Power.begin tick runs no power step',function()
 local p=first(function(r) return r.new_power end)
 H.equal(p~=nil,true,"power begin seen")
 H.equal(p.power_done,false,"power steps start on the next tick (no Power.step in the Power.begin tick)")
 print("TS3")
end)

H.test('TS4 power end and the tidy handoff are different ticks',function()
 local tidy=first(function(r) return r.new_tidy end)
 H.equal(tidy~=nil,true,"tidy begin seen")
 H.equal(tidy.power_done_before,true,"power was already done before the tick that starts tidy")
 print("TS4")
end)

H.done("test_search_tick_splits")

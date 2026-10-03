-- TT1-TT12 red on round-55-base: a valid drawn sheet never tries another Turn. 2026-10-03.
local H=require 'tests.harness'
local D=require 'tests.fixtures.search_doubles'
local Search=require 'logic.bp.search'
local Pack=require 'logic.bp.pack'
local MaterialCost=require 'logic.bp.material_cost'
local Groups=require 'logic.bp.groups'
local Route=require 'logic.bp.route'
local Validate=require 'logic.bp.validate'

local function run_case(opts,configure,mode)
 local old_mode,old_cost,old_flow=Pack.mode,MaterialCost.blueprint,MaterialCost.by_flow
 Pack.mode=mode or 'sugiyama'; MaterialCost.blueprint=function(_,entities) return entities[1] and (entities[1].x==0 and 100 or 80) or 100,0 end
 MaterialCost.by_flow=function() return {f=1} end
 local state,log=D.run(opts or {},function(log)
  local pb,ps,mat=Pack.begin,Pack.step,Groups.materialize
  Pack.begin=function(input) local p=pb(input); p.trialdir=input.trial and input.trial.dir; p.trial=input.trial; return p end
  Pack.step=function(p,b) local r=ps(p,b); if p.done and p.ok then for _,v in ipairs(p.result.placements) do v.dir=p.trialdir or 0 end end; return r end
  Groups.materialize=function(block,placement) local value=mat(block,placement); value.entities[1].x=placement.dir or 0; return value end
  if configure then configure(log) end
  local s=Search.begin(D.input()); local ticks=0
  while not s.done and ticks<3000 do ticks=ticks+1; Search.step(s,{ops=1000}); if opts and opts.observe then opts.observe(s) end end
  Pack.begin,Pack.step,Groups.materialize=pb,ps,mat
  H.equal(s.done,true,'stuck phase '..tostring(s.phase))
  return s
 end)
 Pack.mode,MaterialCost.blueprint,MaterialCost.by_flow=old_mode,old_cost,old_flow
 return state,log
end

H.test('TT1 cheaper turned drawn Block wins',function()
 local state=run_case()
 H.equal(state.ok,true); H.equal(state.result.search.trial.won,1); H.equal(state.incumbent.candidate.placements[1].dir,4); print('TT1')
end)

H.test('TT2 invalid trial preserves incumbent',function()
 local state=run_case({},function()
  MaterialCost.blueprint=function() return 100,0 end
  local step,n=Validate.step,0
  Validate.step=function(s,b) n=n+1; if n==2 then s.done,s.ok,s.errors=true,false,{{code='BP_V_TEST_TRIAL'}}; return s end; return step(s,b) end
 end)
 H.equal(state.ok,true); H.equal(state.incumbent.candidate.placements[1].dir,0); H.equal(state.result.search.trial.rows[1].result,'fail'); H.equal(state.result.search.trial.rows[1].code,'BP_V_TEST_TRIAL'); print('TT2')
end)

H.test('TT3 lane overload does not restart grid during trial',function()
 local state,log=run_case({},function()
  MaterialCost.blueprint=function() return 100,0 end
  local step,n=Validate.step,0
  Validate.step=function(s,b) n=n+1; if n==2 then s.done,s.ok,s.errors=true,false,{{code='BP_V_LANE_OVERLOAD'}}; return s end; return step(s,b) end
 end)
 H.equal(state.ok,true); H.equal(state.incumbent.candidate.placements[1].dir,0); H.equal(#log.route,4); print('TT3')
end)

H.test('TT4 collector route does not nest collector trial',function()
 local state,log=run_case({},function()
  local begin,n=Route.begin,0
  Route.begin=function(input) n=n+1; local s=begin(input); s.work={collectors_used=n==1}; return s end
 end)
 H.equal(state.ok,true); H.equal(#log.route,5); print('TT4')
end)

H.test('TT5 budget at trial publishes incumbent',function()
 local oldstep=Search.step; local entered=false
 Search.step=function(s,b) local r=oldstep(s,b); if s.work.trial and not entered then entered=true; s.max_ops=s.ops_used+1 end; return r end
 local state=run_case(); Search.step=oldstep
 H.equal(state.ok,true); H.equal(state.errors,nil); print('TT5')
end)

H.test('TT6 collector-first accepted result enters trial',function()
 local state=run_case({},function()
  local begin=Route.begin
  Route.begin=function(input) local s=begin(input); s.work={collectors_used=true}; return s end
 end)
 H.equal(state.ok,true); H.equal(state.result.search.trial.tried>0,true); print('TT6')
end)

H.test('TT7 fluid machine can flip and non-fluid block has three poses',function()
 local function collect(fluid)
  local tried,oldstep=0,Search.step
  Search.step=function(s,b) if not s.incumbent and s.phase=='validate' and s.work.validate and s.work.validate.done then s.step_count=10000 end; return oldstep(s,b) end
  local oldreorient=Groups.reorient
  local state=run_case({},function()
   local gs=Groups.step; Groups.step=function(s,b) local r=gs(s,b); if s.done then local block=s.result.candidates[1].blocks[1]; if fluid then block.ports[1].kind='fluid'; block.machines={{name='fixture',can_flip=true,dir=0}} end end; return r end
   if fluid then Groups.reorient=function(_,block,o) local v={}; for k,x in pairs(block) do v[k]=x end; v.machines={{name='fixture',can_flip=true,dir=o.dir,mirror=o.mirror}}; return v end end
   local pb=Pack.begin; Pack.begin=function(input) if input.trial then tried=tried+1 end; return pb(input) end
  end)
  Search.step=oldstep; Groups.reorient=oldreorient; return state,tried
 end
 local plain,nplain=collect(false); local fluid,nfluid=collect(true)
 H.equal(plain.ok,true); H.equal(nplain,3); H.equal(fluid.ok,true); H.equal(nfluid,7); print('TT7')
end)

H.test('TT8 bounded trial records ticks',function()
 local state=run_case()
 local t=state.result.search.trial
 H.equal(t.ticks<=t.ticks_before,true); H.equal(type(t.ticks),'number'); print('TT8')
end)

H.test('TT9 material tie uses production area',function()
 local function tie(area)
  local state=run_case({},function()
   MaterialCost.blueprint=function() return 100,0 end
   local step,n=Validate.step,0
   Validate.step=function(s,b) local r=step(s,b); if s.done and s.ok then n=n+1; s.result.score.production_area=n==1 and 100 or area end; return r end
  end)
  return state
 end
 local smaller=tie(90); local larger=tie(110)
 H.equal(smaller.result.search.trial.won,1); H.equal(larger.result.search.trial.won,0); print('TT9')
end)

H.test('TT10 layered pack skips trial',function()
 local old=Pack.mode; Pack.mode='layered'
 local state=run_case(nil,nil,'layered'); Pack.mode=old
 H.equal(state.result.search.trial,nil); print('TT10')
end)

H.test('TT11 trial progress labels pack route validate',function()
 local seen={}
 local state=run_case({},function(log)
  local begin=Pack.begin; Pack.begin=function(input) local s=begin(input); if input.trial then seen.pack=true end; return s end
  local rb=Route.begin; Route.begin=function(input) local s=rb(input); seen.route=true; return s end
  local vb,n=Validate.begin,0; Validate.begin=function(input) n=n+1; local s=vb(input); if n>1 then seen.validate=true end; return s end
 end)
 H.equal(state.ok,true); H.equal(seen.pack,true); H.equal(seen.route,true); H.equal(seen.validate,true); print('TT11')
end)

H.test('TT12 trial pin failure advances',function()
 local state=run_case({},function()
  local begin,step=Pack.begin,Pack.step; local n=0
  Pack.begin=function(input) n=n+1; local s=begin(input); s.pin=input.trial~=nil and n==2; return s end
  Pack.step=function(s,b) if s.pin and b.ops>0 then b.ops=b.ops-1; s.done,s.ok,s.errors=true,false,{{code='BP_P_TRIAL_PIN'}}; return s end; return step(s,b) end
 end)
 H.equal(state.ok,true); H.equal(state.result.search.trial.rows[1].result,'pin'); H.equal(state.result.search.trial.tried>1,true); print('TT12')
end)

--TT13 (integrator, 2026-10-03): red on lane 306 head 5e9045a, which set stage "trial" on every route/validate of a
--normal run, so the bar jumped past validate before any trial existed.
H.test('TT13 stage trial only while a trial runs',function()
 local bad,seen_trial={},false
 local state=run_case({observe=function(s)
  local running=s.work and s.work.trial and s.work.trial.running
  if s.progress and s.progress.stage=='trial' then if running then seen_trial=true else bad[#bad+1]=tostring(s.phase) end end
 end})
 H.equal(state.ok,true); H.deep_equal(bad,{},'stage trial outside a trial'); H.equal(seen_trial,true,'stage trial during a trial'); print('TT13')
end)

--TT14 (integrator, 2026-10-03): rule and pose name the same thing (pack dir / mirror); red on 5e9045a, whose rule
--read the machine dir.
H.test('TT14 rule pose is the incumbent pack dir',function()
 local state=run_case({observe=function(s)
  if s.work and not s.work.trial and s.work.candidate then
   for _,b in ipairs(s.work.candidate.blocks or {}) do b.turn=8; b.machines=b.machines or {{}}; for _,m in ipairs(b.machines) do m.dir=8 end end
  end
 end})
 local rows=state.result.search.trial.rows
 H.equal(#rows>0,true); H.equal(rows[1].rule,'0/0'); H.equal(rows[1].pose~=rows[1].rule,true); print('TT14')
end)

--TT15 (integrator, 2026-10-03): red on 2b3fd83. red-1s drawn: ticks_before=186, one try ran to 466 because the
--stop rule ran only between tries. A try still running when the cap is reached is cut; the incumbent is delivered.
H.test('TT15 a try running past the cap is cut at the cap',function()
 local state=run_case({},function()
  local rb,n=Route.begin,0
  Route.begin=function(input) n=n+1; local s=rb(input); if n>=2 then s.done=false; s.endless=true end; return s end
  local rs=Route.step; Route.step=function(s,b) if s.endless then b.ops=0; return s end; return rs(s,b) end
 end)
 local t=state.result.search.trial
 H.equal(state.ok,true); H.equal(t.ticks<=t.ticks_before+1,true,'ticks '..tostring(t.ticks)..' cap '..tostring(t.ticks_before))
 H.equal(t.rows[#t.rows].result,'cut'); print('TT15')
end)

--TS1-TS6 red on round-55-wave2-base: trials tidy every pose and do not screen by pre-tidy material. 2026-10-03.
H.test('TS1 screen poses skip tidy and only finalist tidies',function()
 local state,log=run_case()
 local screened=0; for _,row in ipairs(state.result.search.trial.rows) do if row.result=='screened' then screened=screened+1 end end
 H.equal(#log.tidy,2); H.equal(screened,3); print('TS1')
end)
H.test('TS2 lowest screened pose is final',function()
 local state=run_case({},function() MaterialCost.blueprint=function(_,entities) local d=entities[1] and entities[1].x or 0; return d==4 and 70 or d==8 and 90 or d==12 and 95 or 100,0 end end)
 H.equal(state.result.search.trial.finalist,'b 4/0'); print('TS2')
end)
H.test('TS3 screen worse than incumbent skips final',function()
 local state=run_case({},function() MaterialCost.blueprint=function(_,entities) local d=entities[1] and entities[1].x or 0; return d==0 and 10 or 20,0 end end)
 local screened=0; for _,row in ipairs(state.result.search.trial.rows) do if row.result=='screened' then screened=screened+1 end end
 H.equal(screened,3); H.equal(state.result.search.trial.finalist,nil); H.equal(state.ok,true); print('TS3')
end)
H.test('TS4 route failure is recorded while screen advances',function()
 local state=run_case({},function()
  local begin,n=Route.begin,0; Route.begin=function(input) n=n+1; local s=begin(input); if input.trial then n=n+1; if n==3 then s.force_error=true end end; return s end
  local step=Route.step; Route.step=function(s,b) if s.force_error then s.done,s.ok,s.errors=true,false,{{code='BP_R_TEST_SCREEN'}}; return s end; return step(s,b) end
 end)
 local found=false; for _,row in ipairs(state.result.search.trial.rows) do if row.code=='BP_R_TEST_SCREEN' and row.result=='fail' then found=true end end
 H.equal(found,true); print('TS4')
end)
H.test('TS5 cap during screen cuts and delivers incumbent',function()
 local state=run_case({},function()
  local rb,n=Route.begin,0; Route.begin=function(input) n=n+1; local s=rb(input); if input.trial and n>=3 then s.done=false; s.endless=true end; return s end
  local rs=Route.step; Route.step=function(s,b) if s.endless then b.ops=0; return s end; return rs(s,b) end
 end)
 local screened=0; for _,row in ipairs(state.result.search.trial.rows) do if row.result=='screened' then screened=screened+1 end end
 H.equal(state.ok,true); H.equal(screened>0,true); H.equal(state.result.search.trial.finalist,nil); H.equal(state.result.search.trial.rows[#state.result.search.trial.rows].result,'cut'); print('TS5')
end)
H.test('TS6 accepted incumbent retains pre-tidy material',function()
 local state=run_case(); H.equal(type(state.incumbent.pre_tidy_material),'number'); print('TS6')
end)
H.done('test_turn_trial')

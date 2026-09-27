-- Profile a real golden generation run. Usage: lua5.2 tools/golden_profile.lua <case|prepared.json> <out.json> [--ops 2000] [--cap seconds]
local function read(path) local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s end
local function esc(s) return '"'..tostring(s):gsub('[%z\1-\31"\\]', function(c) local m={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}; return m[c] or string.format('\\u%04x',c:byte()) end)..'"' end
local function enc(v) local t=type(v); if t=='nil' then return 'null' elseif t=='boolean' then return tostring(v) elseif t=='number' then if v~=v or v==math.huge or v==-math.huge then return 'null' end; return string.format('%.8g',v) elseif t=='string' then return esc(v) elseif t=='table' then local n=0; for k in pairs(v) do if type(k)~='number' then n=-1; break else n=n+1 end end; local a={}; if n>=0 then for i=1,n do a[i]=enc(v[i]) end; return '['..table.concat(a,',')..']' end; for k,x in pairs(v) do a[#a+1]=esc(k)..':'..enc(x) end; table.sort(a); return '{'..table.concat(a,',')..'}' end; return 'null' end
local input, out=arg[1],arg[2]; if not input or not out then error('usage: golden_profile.lua <case|prepared.json> <out.json>') end
local ops,cap=2000,nil; for i=3,#arg do if arg[i]=='--ops' then ops=tonumber(arg[i+1]); i=i+1 elseif arg[i]=='--cap' then cap=tonumber(arg[i+1]); i=i+1 end end
local root=(debug.getinfo(1,'S').source:sub(2):match('^(.*)/tools/[^/]+$') or '.')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local case=input
if input:match('%.json$') then case=input:match('([^/]+)/[^/]+%.json$') or input:match('([^/]+)%.json$') end
local prep=input; if not input:match('%.json$') then prep=root..'/tests/golden/cases/'..input..'/prepared_input.json' end
local M={}; local names={plan='Plan',groups='Groups',pack='Pack',route='Route',power='Power',validate='Validate',hands='Hands',serialize='Serialize'}
local function instrument(path, edits)
  local source=read(root..'/'..path)
  for needle,replacement in pairs(edits) do local pattern=needle:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])','%%%1');local count=0;source=source:gsub(pattern,function(line) count=count+1;return replacement end);assert(count==1,'expected exactly one instrumentation site: '..needle..' got '..count) end
  return assert(load(source,'@'..root..'/'..path))()
end
package.preload['logic.bp.route']=function() return instrument('logic/bp/route.lua',{
  ['    work.current = begin_search(work, demand, amount)']='    if _G.__gp_route_demand then _G.__gp_route_demand(work, demand) end\n    work.current = begin_search(work, demand, amount)',
  ['local function fail_demand(state, work, demand, code, detail)']='local function fail_demand(state, work, demand, code, detail)\n    if _G.__gp_demand_fail then _G.__gp_demand_fail(demand, code) end',
  ['local function restart_with_priority(state, work, demand)']='local function restart_with_priority(state, work, demand)\n    if _G.__gp_restart then _G.__gp_restart(demand) end'}) end
package.preload['logic.bp.search']=function() return instrument('logic/bp/search.lua',{
  ['local function set_phase(state, phase)']='local function set_phase(state, phase)\n    if _G.__gp_phase then _G.__gp_phase(state, phase) end',
  ['local function start_grid(state)']='local function start_grid(state)\n    if _G.__gp_grid then _G.__gp_grid(state) end',
  ['local function record_rejection(state, errors, stage)']='local function record_rejection(state, errors, stage)\n    if _G.__gp_reject then _G.__gp_reject(state, errors, stage) end',
  ['local function record_valid_attempt(state, score)']='local function record_valid_attempt(state, score)\n    if _G.__gp_valid then _G.__gp_valid(state) end'}) end
local demand_times={}
for key,name in pairs(names) do local mod=require('logic.bp.'..key); for fn,f in pairs(mod) do if type(f)=='function' then local k=name..'.'..fn; M[k]={n=0,cpu=0,worst=0}; mod[fn]=function(...) local args={...};local t=os.clock(); local a,b,c,d,e=f(...); local dt=os.clock()-t; local x=M[k]; x.n=x.n+1;x.cpu=x.cpu+dt;if dt>x.worst then x.worst=dt end
  if name=='Route' and fn=='step' then local state=args[1];local w=state and state.work;local demand=w and w.demands and w.demands[state.cursor and state.cursor.demand_index or 0];if demand then local id=tostring(demand.flow_id or demand.flow and (demand.flow.flow_id or demand.flow.id) or 'unknown');local z=demand_times[id] or {flow_id=id,kind=demand.kind or demand.flow and demand.flow.kind or '',cpu=0,expansions=0,outcome='pending'};demand_times[id]=z;z.cpu=z.cpu+dt;z.expansions=z.expansions+(w.counters and w.counters.expansions or 0)-(z._last or 0);z._last=w.counters and w.counters.expansions or 0;if demand.unroutable then z.outcome=demand.unroutable elseif demand.remaining and demand.remaining<=1e-8 then z.outcome='routed' end end end
  return a,b,c,d,e end end end end
local Search=require('logic.bp.search'); local original=Search.step; local stages={};for _,k in ipairs({'groups','pack','route','tidy','hands','power','validate','serialize'}) do stages[k]={calls=0,cpu=0,worst=0} end
local result={calls=M,phases={},grids={},stages=stages,rejections={},route_demands_top={},route={demands_attempted=0,restarts=0,expansions=0,abandoned={},crossings_placed=0,runs=0},search={stop_reason='',bound_reason='',grid_trials=0,attempts=0},first_valid=nil,ticks=0,cpu_total=0,ops_used=0,capped=false,worst_tick={cpu=0,tick=0,phase='',parts={}},ops_per_step=ops,case=case,git_head='unknown',ok=false,error_codes={}}
local head=io.popen('git rev-parse HEAD 2>/dev/null'); if head then result.git_head=(head:read('*l') or 'unknown');head:close() end
local perphase={}; local start=os.clock(); local stopped=false; local oldstep;local active_tick_start=start
_G.__gp_valid=function() if not result.first_valid then result.first_valid={tick=result.ticks+1,cpu=result.cpu_total+os.clock()-active_tick_start} end end
_G.__gp_phase=function() end
_G.__gp_grid=function(state) local raw=state.work.grid_specs[state.cursor.grid_index];if not raw then return end;local i=state.cursor.grid_index;result.grids[i]=result.grids[i] or {nth=i,grid_index=i,w=raw.w or raw.cols or 0,h=raw.h or raw.rows or 0,attempt=state.work.attempt or 0,layered=raw.layered==true,start_tick=result.ticks+1,cpu=0,ops=0,outcome_stage='groups',reject_codes={}} end
_G.__gp_reject=function(state,errors,stage) local g=result.grids[state.cursor.grid_index or 1];if g then for _,e in ipairs(errors or {}) do local code=type(e)=='table' and (e.code or e.reason) or e;if code then g.reject_codes[#g.reject_codes+1]=tostring(code) end end;g.outcome_stage=stage or state.phase end end
_G.__gp_route_demand=function(work,demand) local id=tostring(demand.flow_id or demand.flow and (demand.flow.flow_id or demand.flow.id) or 'unknown');local z=demand_times[id] or {flow_id=id,kind=demand.kind or demand.flow and demand.flow.kind or '',cpu=0,expansions=0,outcome='pending'};demand_times[id]=z end
_G.__gp_demand_fail=function(demand,code) local id=tostring(demand.flow_id or demand.flow and (demand.flow.flow_id or demand.flow.id) or 'unknown');local z=demand_times[id] or {flow_id=id,kind=demand.kind or '',cpu=0,expansions=0,outcome='pending'};demand_times[id]=z;z.outcome=code end
_G.__gp_restart=function() result.route.restarts=result.route.restarts+1 end
Search.step=function(container,budget) local state=container.state or container; if state.done then return original(container,budget) end
  if stopped or (cap and os.clock()-start>=cap) then result.capped=true; stopped=true; state.done=true;state.ok=false;state.phase='failed';state.errors={{code='PROFILE_CPU_CAP'}};return container end
  budget=budget or {}; budget.ops=ops; local ph=state.phase or 'unknown'; local call_before={};for k,v in pairs(M) do call_before[k]=v.cpu end;local t=os.clock();active_tick_start=t; local before=state.ops_used or 0; local ret=original(container,budget); local dt=os.clock()-t; result.ticks=result.ticks+1; result.cpu_total=result.cpu_total+dt; result.ops_used=result.ops_used+math.max(0,(state.ops_used or 0)-before)
  local p=result.phases[ph] or {name=ph,entries=0,ticks=0,cpu=0,ops=0}; result.phases[ph]=p;p.entries=p.entries+1;p.ticks=p.ticks+1;p.cpu=p.cpu+dt;p.ops=p.ops+math.max(0,(state.ops_used or 0)-before)
  local parts={}; for k,v in pairs(M) do local old=call_before[k] or 0;local delta=v.cpu-old;if delta>0 then parts[k]=delta end end
  if dt>result.worst_tick.cpu then result.worst_tick={cpu=dt,tick=result.ticks,phase=ph,parts=parts} end
  if state.cursor and state.cursor.grid_index then result.search.grid_trials=math.max(result.search.grid_trials or 0,state.work and state.work.grid_trials or state.cursor.grid_index) end
  if state.work then
    result.search={stop_reason=state.work.stop_reason or '',bound_reason=state.work.bound_reason or '',grid_trials=result.search and result.search.grid_trials or 0,attempts=state.work.rejection_attempts or 0}
    local rejection_count=state.work.rejection_attempts or 0; result._rejection_seen=result._rejection_seen or 0; for i=result._rejection_seen+1,#(state.work.rejections or {}) do local r=state.work.rejections[i];local x=result.rejections[r.code] or {count=0,stages={}};result.rejections[r.code]=x;x.count=x.count+1;x.stages[r.stage or 'unknown']=(x.stages[r.stage or 'unknown'] or 0)+1 end;result._rejection_seen=#(state.work.rejections or {}); result.search.attempts=rejection_count
    local g=state.work.grid; if g then local index=state.cursor.grid_index or 1; local x=result.grids[index] or {nth=index,grid_index=index,w=g.w or g.cols or 0,h=g.h or g.rows or 0,attempt=state.cursor.candidate_index or state.work.attempt or 0,layered=g.layered==true,start_tick=result.ticks,cpu=0,ops=0,reject_codes={}}; result.grids[index]=x;x.cpu=x.cpu+dt;x.ops=x.ops+math.max(0,(state.ops_used or 0)-before);x.outcome_stage=ph end
    local rw=state.work.route and state.work.route.work; if rw then for k,v in pairs(rw.counters or {}) do if k=='expansions' or k=='crossings_placed' or k=='restarts' or k=='demands_attempted' then result.route[k]=v elseif k=='searches_abandoned' then result.route.abandoned=v end end;result.route.runs=rw.counters and rw.counters.restarts or 0;result.route.demands_attempted=rw.counters and rw.counters.demands_attempted or 0 end
    if state.incumbent and not result.first_valid then result.first_valid={tick=result.ticks,cpu=result.cpu_total} end
  end
  if state.done and state.result and type(state.result.entities)=='table' then result.entities=#state.result.entities end
  if cap and os.clock()-start>=cap then result.capped=true;stopped=true end; return ret
end
local tmp=os.tmpname(); arg={[0]=root..'/tests/golden/generate.lua','--input',prep,'--output',tmp}; start=os.clock()
local ok,err=pcall(dofile,root..'/tests/golden/generate.lua'); local generated
if ok then generated=read(tmp); os.remove(tmp) else result.error=tostring(err) end
local phase_list={}; for _,p in pairs(result.phases) do phase_list[#phase_list+1]=p end; table.sort(phase_list,function(a,b)return a.name<b.name end);result.phases=phase_list
local grid_list={}; for _,g in pairs(result.grids) do grid_list[#grid_list+1]=g end;table.sort(grid_list,function(a,b)return a.nth<b.nth end);result.grids=grid_list
for name,v in pairs(M) do local st=names[name:match('^[^.]+')] or ''; local stage=(name=='Route.tidy_step' and 'tidy') or ({Plan='groups',Groups='groups',Pack='pack',Route='route',Power='power',Validate='validate',Hands='hands',Serialize='serialize'})[st]; if stage then local x=result.stages[stage];x.calls=x.calls+v.n;x.cpu=x.cpu+v.cpu;if v.worst>x.worst then x.worst=v.worst end end end
local phase_cpu={};for _,p in ipairs(result.phases) do phase_cpu[p.name]=p.cpu end;for stage,x in pairs(result.stages) do x.cpu=phase_cpu[stage] or 0 end
for _,d in pairs(demand_times) do d._last=nil;result.route_demands_top[#result.route_demands_top+1]=d end;table.sort(result.route_demands_top,function(a,b)return a.cpu>b.cpu end);while #result.route_demands_top>20 do table.remove(result.route_demands_top) end
result.route.runs=M['Route.begin'] and M['Route.begin'].n or 0
result._rejection_seen=nil
if generated then result.ok=generated:match('"ok":true')~=nil; for code in generated:gmatch('"code":"([^"]+)"') do result.error_codes[#result.error_codes+1]=code end; result.canonical_sha256=generated:match('"canonical_sha256":"([^"]+)"') end
if result.error then result.error_codes[1]=result.error end
local f=assert(io.open(out,'wb')); f:write(enc(result),'\n');f:close()

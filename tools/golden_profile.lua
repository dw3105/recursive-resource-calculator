-- Profile a real golden generation run. Usage: lua5.2 tools/golden_profile.lua <case|prepared.json> <out.json> [--ops 2000] [--cap seconds]
local function read(path) local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s end
local function esc(s) return '"'..tostring(s):gsub('[%z\1-\31"\\]', function(c) local m={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}; return m[c] or string.format('\\u%04x',c:byte()) end)..'"' end
local function enc(v) local t=type(v); if t=='nil' then return 'null' elseif t=='boolean' then return tostring(v) elseif t=='number' then if v~=v or v==math.huge or v==-math.huge then return 'null' end; return string.format('%.8g',v) elseif t=='string' then return esc(v) elseif t=='table' then local n=0; for k in pairs(v) do if type(k)~='number' then n=-1; break else n=n+1 end end; local a={}; if n>=0 then for i=1,n do a[i]=enc(v[i]) end; return '['..table.concat(a,',')..']' end; for k,x in pairs(v) do a[#a+1]=esc(k)..':'..enc(x) end; table.sort(a); return '{'..table.concat(a,',')..'}' end; return 'null' end
local input, out=arg[1],arg[2]; if not input or not out then error('usage: golden_profile.lua <case|prepared.json> <out.json>') end
local ops,cap=2000,nil; for i=3,#arg do if arg[i]=='--ops' then ops=tonumber(arg[i+1]); i=i+1 elseif arg[i]=='--cap' then cap=tonumber(arg[i+1]); i=i+1 end end
local root=(debug.getinfo(1,'S').source:sub(2):match('^(.*)/tools/[^/]+$') or '.')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local case=input:match('([^/]+)%.json$') and input:match('([^/]+)%.json$') or input
local prep=input; if not input:match('%.json$') then prep=root..'/tests/golden/cases/'..input..'/prepared_input.json' end
local M={}; local names={plan='Plan',groups='Groups',pack='Pack',route='Route',power='Power',validate='Validate',hands='Hands',serialize='Serialize'}
for key,name in pairs(names) do local mod=require('logic.bp.'..key); for fn,f in pairs(mod) do if type(f)=='function' then local k=name..'.'..fn; M[k]={n=0,cpu=0,worst=0}; mod[fn]=function(...) local t=os.clock(); local a,b,c,d,e=f(...); local dt=os.clock()-t; local x=M[k]; x.n=x.n+1;x.cpu=x.cpu+dt;if dt>x.worst then x.worst=dt end; return a,b,c,d,e end end end end
local Search=require('logic.bp.search'); local original=Search.step; local result={calls=M,phases={},grids={},stages={},rejections={},route_demands_top={},route={demands_attempted=0,restarts=0,expansions=0,abandoned={},crossings_placed=0,runs=0},first_valid=nil,ticks=0,cpu_total=0,ops_used=0,capped=false,worst_tick={cpu=0,tick=0,phase='',parts={}},ops_per_step=ops,case=case,git_head='unknown',ok=false,error_codes={}}
local head=io.popen('git rev-parse HEAD 2>/dev/null'); if head then result.git_head=(head:read('*l') or 'unknown');head:close() end
local perphase={}; local start=os.clock(); local stopped=false; local oldstep
Search.step=function(container,budget) local state=container.state or container; if state.done or stopped then return original(container,budget) end
  if cap and os.clock()-start>=cap then result.capped=true; stopped=true; return container end
  budget=budget or {}; budget.ops=ops; local ph=state.phase or 'unknown'; local t=os.clock(); local before=state.ops_used or 0; local ret=original(container,budget); local dt=os.clock()-t; result.ticks=result.ticks+1; result.cpu_total=result.cpu_total+dt; result.ops_used=result.ops_used+math.max(0,(state.ops_used or 0)-before)
  local p=result.phases[ph] or {name=ph,entries=0,ticks=0,cpu=0,ops=0}; result.phases[ph]=p;p.entries=p.entries+1;p.ticks=p.ticks+1;p.cpu=p.cpu+dt;p.ops=p.ops+math.max(0,(state.ops_used or 0)-before)
  local parts={}; for k,v in pairs(M) do if v.cpu>(parts[k] or 0) then parts[k]=v.cpu end end
  if dt>result.worst_tick.cpu then result.worst_tick={cpu=dt,tick=result.ticks,phase=ph,parts=parts} end
  if state.cursor and state.cursor.grid_index then result.search.grid_trials=math.max(result.search and result.search.grid_trials or 0,state.cursor.grid_index) end
  if state.work then
    result.search={stop_reason=state.work.stop_reason or '',bound_reason=state.work.bound_reason or '',grid_trials=result.search and result.search.grid_trials or 0,attempts=state.work.rejection_attempts or 0}
    for _,r in ipairs(state.work.rejections or {}) do local x=result.rejections[r.code] or {count=0,stages={}};result.rejections[r.code]=x;x.count=x.count+1;x.stages[r.stage or 'unknown']=(x.stages[r.stage or 'unknown'] or 0)+1 end
    local g=state.work.grid; if g then local index=state.cursor.grid_index or 1; local x=result.grids[index] or {nth=index,grid_index=index,w=g.w or g.cols or 0,h=g.h or g.rows or 0,attempt=state.work.attempt or 0,layered=false,start_tick=result.ticks,cpu=0,ops=0,reject_codes={}}; result.grids[index]=x;x.cpu=x.cpu+dt;x.ops=x.ops+math.max(0,(state.ops_used or 0)-before);x.outcome_stage=ph end
    local rw=state.work.route and state.work.route.work; if rw then for k,v in pairs(rw.counters or {}) do if k=='expansions' or k=='crossings_placed' then result.route[k]=v end end; result.route.restarts=rw.restarts or 0;result.route.runs=rw.runs or 0;result.route.demands_attempted=#(rw.demands or {});result.route.abandoned=rw.abandoned or {} end
    if state.incumbent and not result.first_valid then result.first_valid={tick=result.ticks,cpu=result.cpu_total} end
  end
  if cap and os.clock()-start>=cap then result.capped=true;stopped=true end; return ret
end
local tmp=os.tmpname(); arg={[0]=root..'/tests/golden/generate.lua','--input',prep,'--output',tmp}
local ok,err=pcall(dofile,root..'/tests/golden/generate.lua'); if ok then local txt=read(tmp); result.generated=txt; os.remove(tmp) else result.error=tostring(err) end
for name,p in pairs(result.phases) do result.phases[name]=p end
for name,v in pairs(M) do local st=names[name:match('^[^.]+')] or ''; local stage=({Plan='groups',Groups='groups',Pack='pack',Route='route',Power='power',Validate='validate',Hands='hands',Serialize='serialize'})[st]; if stage then local x=result.stages[stage] or {calls=0,cpu=0,worst=0};result.stages[stage]=x;x.calls=x.calls+v.n;x.cpu=x.cpu+v.cpu;if v.worst>x.worst then x.worst=v.worst end end end
for _,p in pairs(result.phases) do end
if result.generated then result.ok=result.generated:match('"ok":true')~=nil; for code in result.generated:gmatch('"code":"([^"]+)"') do result.error_codes[#result.error_codes+1]=code end; local n=result.generated:match('"entities":%[(.-)%]'); if n then result.entities=0;for _ in n:gmatch('{') do result.entities=result.entities+1 end end;result.canonical_sha256=result.generated:match('"canonical_sha256":"([^"]+)"') end
if result.error then result.error_codes[1]=result.error end
local f=assert(io.open(out,'wb')); f:write(enc(result),'\n');f:close()

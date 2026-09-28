-- Usage:
-- lua5.2 tools/ckpt.lua list <case|prepared.json> [--ops 2000]
-- lua5.2 tools/ckpt.lua save <case> <at-spec> <out.lua[.gz]> [--ops 2000]
-- lua5.2 tools/ckpt.lua resume <file> [--until <at-spec> | --at-tick N] [--save <out>] [--ops N] [--patch file.lua] [--output result.json]
-- lua5.2 tools/ckpt.lua uninterrupted <case> [--ops 2000]
-- lua5.2 tools/ckpt.lua save-all <case> <dir> [--ops 2000] [--patch f.lua]   one run, a checkpoint after EVERY phase
--   change (player rule 2026-09-28: every golden examined has snapshots after each step): <dir>/NNN_gG_aA_lL_<phase>.lua.gz
package.path = "./?.lua;" .. package.path
local guard_mode = arg[1]
if guard_mode == "save" or guard_mode == "save-all" or guard_mode == "list" or guard_mode == "uninterrupted" then
    require("tools.lib.slow_guard").check("ckpt " .. guard_mode, arg[2])
elseif guard_mode == "resume" then
    _G.__rrc_slow_guard_checked = true
end
local Graph = require "tools.lib.graph_dump"
local mode = table.remove(arg, 1)
local function opts(start)
    local r={}; local i=start
    while i<=#arg do local k=arg[i]; if k:sub(1,2)=="--" then r[k:sub(3)]=arg[i+1]; i=i+2 else i=i+1 end end
    return r
end
local function quote(s) return string.format("%q",s) end
local function sha(path)
    local p=assert(io.popen("sha256sum "..quote(path),"r")); local s=p:read("*l"); p:close(); return s:match("^(%w+)")
end
local function parse_spec(spec)
    local t={}; for part in (spec or ""):gmatch("[^,]+") do local k,v=part:match("^([^=]+)=(.*)$"); if k then t[k]=v end end; return t
end
local function main()
    local command=mode
    if command~="list" and command~="save" and command~="save-all" and command~="resume" and command~="uninterrupted" then error("usage: ckpt.lua list|save|save-all|resume|uninterrupted ...") end
    local case, at, out, snap
    if command=="list" or command=="uninterrupted" then case=arg[1]
    elseif command=="save" then case,at,out=arg[1],arg[2],arg[3]
    elseif command=="save-all" then case,out=arg[1],arg[2]; os.execute("mkdir -p "..quote(out))
    else snap=arg[1] end
    local o=opts(command=="save" and 4 or (command=="save-all" and 3 or 2)); local ops=tonumber(o.ops) or 2000
    local input_path
    if command=="resume" then
        local d=Graph.load(snap); local s=d.state and d or d
        case=s.meta.case; input_path=s.meta.input_path
    else
        input_path=case:match("%.json$") and case or ("tests/golden/cases/"..case.."/prepared_input.json")
    end
    local digest=sha(input_path); local events, step_index={},0; local stopped, listing=false,false
    local saved, resumed
    if command=="resume" then
        saved=Graph.load(snap)
        if not o.ops then ops=tonumber(saved.meta.ops_per_step) or ops end
        local env=saved.meta.env or {}
        if env.RRC_PACK~=os.getenv("RRC_PACK") or env.RRC_PACK_EXTRA~=os.getenv("RRC_PACK_EXTRA") then
            io.stderr:write("WARNING pack environment differs from checkpoint\n")
        end
    end
    local until_spec=o["until"] or (command=="save" and at)
    local criteria=parse_spec(until_spec)
    local nth=tonumber(criteria.nth) or 1; criteria.nth=nil
    local matches,route_demand_count=0,0
    local function event(kind,state,detail)
        local s=state or {}; local w=s.work or {}; if kind=="route-demand" then route_demand_count=route_demand_count+1 end; local c={kind=kind,phase=(kind=="phase" and detail or s.phase),grid=s.cursor and s.cursor.grid_index,
            attempt=w.attempt or s.progress and s.progress.attempt,layered=w.layered_off and 0 or 1,
            tick=step_index,ops=s.ops_used or 0,detail=detail}
        if kind=="route-demand" then c.demand=detail; c.route_demand=route_demand_count end
        events[#events+1]=c
        if command=="save-all" and kind=="phase" then _G.__ckpt_pending=c end
        local matched=true
        for k,v in pairs(criteria) do local key=k=="reject-code" and "detail" or k; local cv=c[key]; if k=="reject" then cv=kind=="reject" and detail end; if tostring(cv)~=v then matched=false end end
        if matched and next(criteria) then matches=matches+1; if matches==nth then stopped=true end end
    end
    _G.__ckpt=function(kind,state,detail) event(kind,state,detail) end
    package.preload["logic.bp.route"]=function()
        local f=assert(io.open("logic/bp/route.lua","r")); local src=f:read("*a"); f:close()
        local hooks={{"local function begin_search(work, demand, amount, order_index)","route-demand","demand"},
          {"local function fail_demand(state, work, demand, code, detail)","reject","code"},
          {"local function restart_with_priority(state, work, demand)","route-restart","demand"}}
        if o.patch then local fn=assert(loadfile(o.patch))(); src=assert(fn("logic.bp.route",src)) end
        for _,h in ipairs(hooks) do local a,b=src:find(h[1],1,true); assert(a,"missing Route hook "..h[1]);
            local expr=h[3]=="demand" and "demand and demand.flow_id" or "code"
            src=src:sub(1,b).." if _G.__ckpt then _G.__ckpt("..quote(h[2])..", state, "..expr..") end"..src:sub(b+1)
        end
        return assert(load(src,"@logic/bp/route.lua"))()
    end
    local result_path=o.output or os.tmpname()
    local native_require=require
    _G.require=function(name)
        if package.preload[name] then return native_require(name) end
        if type(name)=="string" and name:match("^logic%.bp%.") then
            if package.loaded[name]~=nil then return package.loaded[name] end
            local path=name:gsub("%.","/")..".lua"; local f=assert(io.open(path,"r")); local src=f:read("*a"); f:close()
            if o.patch then local fn=assert(loadfile(o.patch))(); src=assert(fn(name,src)) end
            local value=assert(load(src,"@"..path))(); package.loaded[name]=value; return value
        end
        return native_require(name)
    end
    package.preload["logic.bp.search"]=function()
        local f=assert(io.open("logic/bp/search.lua","r")); local src=f:read("*a"); f:close()
        local hooks={
          {"local function set_phase(state, phase)","phase"},
          {"local function record_rejection(state, errors, stage)","reject"},
          {"local function start_grid(state)","grid"},
          {"local function discard_candidate(state)","stage-begin"}}
        if o.patch then local fn=assert(loadfile(o.patch))(); src=assert(fn("logic.bp.search",src)) end
        for _,h in ipairs(hooks) do local a,b=src:find(h[1],1,true); assert(a,"missing Search hook "..h[1]); local call=(h[2]=="phase" and "phase" or (h[2]=="reject" and "errors and errors[1] and (errors[1].code or errors[1].reason)" or "nil")); src=src:sub(1,b).." if _G.__ckpt then _G.__ckpt("..quote(h[2])..", state, "..call..") end"..src:sub(b+1) end
        local loader=assert(load(src,"@logic/bp/search.lua")); local Search=loader()
        local begin,step=Search.begin,Search.step
        Search.begin=function(input) if saved then resumed=true; return saved.state end; return begin(input) end
        Search.step=function(st,b) step_index=step_index+1; _G.__ckpt_tick=step_index; local r=step(st,{ops=ops}); _G.__ckpt_last_state=st;
            if o["at-tick"] and step_index>=tonumber(o["at-tick"]) then stopped=true end
            if command=="save-all" and _G.__ckpt_pending then
                local c=_G.__ckpt_pending; _G.__ckpt_pending=nil; _G.__ckpt_saves=(_G.__ckpt_saves or 0)+1
                local name=string.format("%s/%03d_g%s_a%s_l%s_%s.lua.gz",out,_G.__ckpt_saves,tostring(c.grid),tostring(c.attempt or 0),tostring(c.layered),tostring(c.phase))
                local meta={case=case,input_path=input_path,input_sha256=digest,git_head=assert(io.popen("git rev-parse HEAD","r")):read("*l"),tick=step_index,ops_per_step=ops,spec="save-all "..tostring(c.phase),
                  env={RRC_PACK=os.getenv("RRC_PACK"),RRC_PACK_EXTRA=os.getenv("RRC_PACK_EXTRA")},lua=_VERSION}
                Graph.dump({state=st,meta=meta},name); io.write(string.format("SAVED %s tick=%d cpu=%.0fs\n",name,step_index,os.clock())); io.flush()
            end
            if stopped and (command=="save" or (command=="resume" and o.save)) then
            local meta={case=case,input_path=input_path,input_sha256=digest,git_head=assert(io.popen("git rev-parse HEAD","r")):read("*l"),tick=step_index,ops_per_step=ops,spec=until_spec or at,
              env={RRC_PACK=os.getenv("RRC_PACK"),RRC_PACK_EXTRA=os.getenv("RRC_PACK_EXTRA")},lua=_VERSION}
            Graph.dump({state=st,meta=meta},o.save or out); io.write("SAVED "..tostring(o.save or out).." tick="..step_index.." event="..tostring(events[#events] and events[#events].kind).."\n"); os.exit(0)
        end; return r end
        return Search
    end
    if command=="resume" then step_index=(saved.meta.tick or 0); case=saved.meta.case end
    arg={[0]="tests/golden/generate.lua","--input",input_path,"--output",result_path}
    dofile("tests/golden/generate.lua")
    if command=="list" then for i,e in ipairs(events) do io.write(string.format("EV n=%d tick=%d ops=%s kind=%s phase=%s grid=%s attempt=%s layered=%s detail=%s\n",i,e.tick,e.ops,e.kind,e.phase or "",e.grid or "",e.attempt or "",e.layered or 0,tostring(e.detail or ""))) end; return end
    local path=result_path
    local rf=assert(io.open(path,"r")); local text=rf:read("*a"); rf:close()
    local ok=text:match('"ok":(true)')~=nil; local ticks=step_index
    local used=(_G.__ckpt_last_state and _G.__ckpt_last_state.ops_used) or 0; local sha_out=text:match('"canonical_sha256":"(%w+)"') or "unknown"
    local entities=0; for _ in text:gmatch('"entity_number"%s*:') do entities=entities+1 end; entities=math.floor(entities/2)
    io.write(string.format("RESUMED %s END ok=%s ticks=%d ops_used=%d sha=%s entities=%d\n",command, tostring(ok),ticks,used,sha_out,entities))
end
local ok,err=pcall(main); if not ok then io.stderr:write(tostring(err).."\n"); os.exit(1) end

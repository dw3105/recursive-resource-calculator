-- Census sweep is an integrator suite test. Do not run from a lane (2026-09-30).
package.path = "./?.lua;" .. package.path
local H=require "tests.harness"
local Slice=require "tools.turn_flip_slice"
local function exists(p) local f=io.open(p); if f then f:close(); return true end; return false end
local function q(s) return string.format("%q",s) end
local function case_names(path)
    local cmd="python3 -c 'import json,sys; print(\"\\n\".join(sorted(json.load(open(sys.argv[1]))[\"cases\"])))' "..q(path)
    local p=assert(io.popen(cmd,"r")); local out={}; for name in p:lines() do out[#out+1]=name end
    H.equal(p:close(),true,"could not list census cases"); return out
end
H.test("Turn and Flip census fixtures have no FAIL rows", function()
    local full=os.getenv("RRC_FULL_TURN_FLIP")=="1"
    local round_id=tonumber(os.getenv("RRC_ROUND")) or 56
    local versions=full and {"2.0","2.1"} or {"2.0"}; local found=false
    for _,ver in ipairs(versions) do
        local path="tests/fixtures/turn_flip_cases_"..ver..".json"
        if exists(path) then
            found=true
            local jobs=tonumber((io.popen("nproc"):read("*l")) or "") or 2
            local cases=case_names(path)
            local selected=Slice.pick(cases,round_id,full)
            local function run(fixture,turn,flip)
                local cmd="lua5.2 tools/turn_flip_census.lua "..q(fixture).." --jobs "..jobs
                if turn~=nil then cmd=cmd.." --turn "..turn.." --flip "..flip end
                local p=assert(io.popen(cmd,"r")); local out=p:read("*a"); local ok=p:close()
                local bad={}; for line in out:gmatch("CENSUS [^\n]+") do if line:find("result=FAIL",1,true) then bad[#bad+1]=line end end
                H.equal(ok,true,"census command failed: "..out); H.equal(#bad,0,table.concat(bad,"\n"))
                local total=0; for _ in out:gmatch("CENSUS ver[^\n]+") do total=total+1 end
                H.equal(total>0,true,"census printed no rows")
            end
            if full then
                run(path)
            else
                local groups={}
                for _,row in ipairs(selected) do
                    local key=row.turn..":"..row.flip; groups[key]=groups[key] or {turn=row.turn,flip=row.flip,cases={}}
                    groups[key].cases[#groups[key].cases+1]=row.case
                end
                for _,pose in ipairs(Slice.POSES) do
                    local group=groups[pose.turn..":"..pose.flip]
                    if group then
                        local tmp=os.tmpname()
                        local args={"python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d[\"cases\"]={k:d[\"cases\"][k] for k in sys.argv[3:]}; json.dump(d,open(sys.argv[2],\"w\"))'",q(path),q(tmp)}
                        for _,name in ipairs(group.cases) do args[#args+1]=q(name) end
                        local ok=os.execute(table.concat(args," ")); H.equal(ok,true,"could not prepare sliced census fixture")
                        run(tmp,group.turn,group.flip); os.remove(tmp)
                    end
                end
            end
        end
    end
    if not found then io.write("skip: no turn_flip fixtures\n") end
end)
H.done("test_turn_flip_census")

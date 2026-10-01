#!/usr/bin/env lua
package.path = "./?.lua;" .. package.path
local Row = require "tools.lib.census_row"
local fixture = arg[1]
if not fixture then io.stderr:write("usage: lua5.2 tools/turn_flip_census.lua <fixture.json> [filters]\n"); os.exit(2) end
local opts = {}; local i=2
while i<=#arg do
    local k,v=arg[i],arg[i+1]; if not v then io.stderr:write("missing value for "..k.."\n"); os.exit(2) end
    opts[k]=v; i=i+2
end
local function q(s) return string.format("%q",s) end
local function read(p) local f=io.open(p,"r"); if not f then return nil end; local s=f:read("*a"); f:close(); return s end
local function run(cmd) local p=io.popen(cmd.." 2>&1", "r"); local s=p:read("*a"); local ok,why,code=p:close(); return s,ok,(ok and 0 or code or 1) end
local list = "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[\"version\"]); [print(k) for k in sorted(d[\"cases\"]) ]' "..q(fixture)
--Integrator round 54: version 2.0.77 -> 2.0, so rows and the export dir match game_stage.sh $FV.
local p=assert(io.popen(list,"r")); local ver=p:read("*l"); ver=(ver or ""):match("^(%d+%.%d+)") or ver; local cases={}; for c in p:lines() do cases[#cases+1]=c end; p:close()
local rows,valid,forbidden,fail=0,0,0,0
for _,case in ipairs(cases) do if not opts["--case"] or opts["--case"]==case then
 for _,turn in ipairs({0,4,8,12}) do if not opts["--turn"] or tonumber(opts["--turn"])==turn then
  for _,flip in ipairs({0,1}) do if not opts["--flip"] or tonumber(opts["--flip"])==flip then
   local prefix=(os.getenv("TMPDIR") or "/tmp").."/turn_flip_"..case.."_"..turn.."_"..flip
   local input, result, bp = prefix..".json", prefix..".r.json", prefix..".bp.txt"
   local prep = "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); x=d[\"cases\"][sys.argv[2]]; x.setdefault(\"settings\",{})[\"force_turn_flip\"]={\"turn\":int(sys.argv[3]),\"flip\":sys.argv[4]==\"1\"}; json.dump(x,open(sys.argv[5],\"w\"))' "..q(fixture).." "..q(case).." "..turn.." "..flip.." "..q(input)
   os.execute(prep)
   local _,_,gen_code=run("lua5.2 tests/golden/generate.lua --input "..q(input).." --output "..q(result))
   local error_info=run("python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d.get(\"result\",{}); v=d.get(\"validation\") or {}; e=d.get(\"errors\") or r.get(\"errors\") or v.get(\"errors\") or []; print(e[0].get(\"code\",\"BP_FAIL_GENERATION\") if e else (\"-\" if d.get(\"ok\") and v.get(\"ok\") else \"BP_FAIL_GENERATION\"))' "..q(result))
   local code=error_info:match("([%w_%-]+)") or "-"
   local good=gen_code==0 and code=="-"
   local mixed,starved,bleed,dead,sha=0,0,0,0,"-"
   if good then
    local _,_,bpcode=run("python3 tools/blueprint_string.py "..q(result).." -o "..q(bp))
    if bpcode==0 then
     local sim=run("python3 tools/lane_sim.py "..q(bp).." --input "..q(input))
     mixed,starved,bleed,dead=sim:match("LANE%-SIM mixed=(%d+) starved=(%d+) bleed=(%d+) dead=(%d+)")
     mixed,starved,bleed,dead=tonumber(mixed) or 999,tonumber(starved) or 999,tonumber(bleed) or 999,tonumber(dead) or 999
     local hash=run("sha256sum "..q(bp)); sha=hash:match("^(%x+)") or "-"; sha=sha:sub(1,8)
     --Integrator round 54: a blueprint that dropped the forced Turn or Flip is not a valid row (foundry flip rows
     --shipped one sha for all four turns).
     if not run("python3 tools/turn_flip_pose.py "..q(bp).." "..turn.." "..flip.." "..q(input)):match("^POSE ok") then code="TF_POSE_WRONG" end
     if opts["--export"] and mixed==0 and starved==0 and bleed==0 and dead==0 then
      local dir=opts["--export"].."/"..ver; os.execute("mkdir -p "..q(dir))
      os.execute("cp "..q(bp).." "..q(dir.."/"..case.."_"..turn.."_"..flip..".bp.txt"))
      os.execute("python3 tools/sheet_ports.py "..q(result).." "..q(input).." -o "..q(dir.."/"..case.."_"..turn.."_"..flip..".ports.json"))
     end
    else good=false end
   end
   local classification=Row.classify(good,code,mixed,starved,bleed,dead,flip)
   local row=Row.format({ver=ver,case=case,turn=turn,flip=flip,result=classification,code=code,mixed=mixed,starved=starved,bleed=bleed,dead=dead,sha=sha})
   print(row); rows=rows+1; if classification=="valid" then valid=valid+1 elseif classification=="forbidden" then forbidden=forbidden+1 else fail=fail+1 end
  end end
 end end
end end
print(string.format("CENSUS-SUMMARY rows=%d valid=%d forbidden=%d fail=%d",rows,valid,forbidden,fail))

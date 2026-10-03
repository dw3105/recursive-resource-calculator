--TR1-TR3 red on round-55-base (2026-10-03): no formatter or CLI exists.
package.path="./?.lua;"..package.path
local Rows=require "tools.turn_trial_rows"
local expected={
"TRIAL case=x block=b1 rule=0/1 pose=1/0 result=won code=- material=12.3 area=9",
"TRIAL case=x block=b2 rule=1/0 pose=0/1 result=fail code=BP_X material=8.0 area=4",
"TRIAL case=x block=b3 rule=0/0 pose=0/0 result=pin code=- material=- area=-",
"TRIALSUM case=x tried=3 won=1 fails=1 ticks_before=10 ticks=20"}
local trial={ticks_before=10,ticks=20,tried=3,won=1,fails=1,rows={
{block="b1",rule="0/1",pose="1/0",result="won",material=12.34,area=9},
{block="b2",rule="1/0",pose="0/1",result="fail",code="BP_X",material=8,area=4},
{block="b3",rule="0/0",pose="0/0",result="pin"}}}
local lines=Rows.format("x",trial); for i,v in ipairs(expected) do assert(lines[i]==v, tostring(lines[i])) end
assert(#Rows.format("x",nil)==0)
local temp=os.tmpname()..".r.json"; local f=assert(io.open(temp,"w")); f:write('{"result":{"search":{"trial":{"ticks_before":10,"ticks":20,"tried":3,"won":1,"fails":1,"rows":[{"block":"b1","rule":"0/1","pose":"1/0","result":"won","material":12.34,"area":9},{"block":"b2","rule":"1/0","pose":"0/1","result":"fail","code":"BP_X","material":8,"area":4},{"block":"b3","rule":"0/0","pose":"0/0","result":"pin"}]}}}}'); f:close()
local pipe=assert(io.popen("lua5.2 tools/turn_trial_rows.lua "..temp,"r")); local got=pipe:read("*a"); pipe:close(); os.remove(temp)
assert(got==table.concat(expected,"\n").."\n",got); print("TR1 TR2 TR3")

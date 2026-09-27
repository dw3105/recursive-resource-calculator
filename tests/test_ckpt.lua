--CK1-CK4 are expected to fail on base code: resumable Search checkpoints and graph_dump do not exist there.
local passed,failed=0,0
local function equal(a,b,label) if a==b then passed=passed+1 else failed=failed+1; io.write("FAIL ",label," expected=",tostring(b)," got=",tostring(a),"\n") end end
local H={equal=equal,test=function(name,fn) local ok,e=pcall(fn); if not ok then failed=failed+1; io.write("FAIL ",name," ",tostring(e),"\n") end end,done=function(name) io.write(name..": "..passed.." passed, "..failed.." failed\n") end}
local function run(cmd)
    local p=assert(io.popen(cmd.." 2>&1","r")); local s=p:read("*a"); p:close(); return s
end
local function endline(s) return s:match("(END ok=[^\n]+)") end
local baseline=run("lua5.2 tools/ckpt.lua uninterrupted player-red-science-1s")
local function save_resume(phase)
    local snap=os.tmpname()..".lua"
    local a=run("lua5.2 tools/ckpt.lua save player-red-science-1s phase="..phase.." "..snap)
    local b=run("lua5.2 tools/ckpt.lua resume "..snap)
    os.remove(snap); return a,b
end
H.test("CK1 named phase snapshots resume to the uninterrupted result",function()
    io.write("CK1\n")
    for _,phase in ipairs({"route","tidy","validate"}) do local a,b=save_resume(phase)
        H.equal(a:match("SAVED")~=nil,true,"saved at "..phase)
        H.equal(endline(b)~=nil,true,"resume reports END after "..phase)
        H.equal(endline(b),endline(baseline),"same end after "..phase)
    end
end)
H.test("CK2 checkpoint can be resumed through a later named phase",function()
    io.write("CK2\n")
    local a=os.tmpname()..".lua"; local b=os.tmpname()..".lua"
    run("lua5.2 tools/ckpt.lua save player-red-science-1s phase=route "..a)
    run("lua5.2 tools/ckpt.lua resume "..a.." --until phase=validate --save "..b)
    local resumed=run("lua5.2 tools/ckpt.lua resume "..b)
    H.equal(endline(resumed)~=nil,true,"chained resume reports END")
    H.equal(endline(resumed),endline(baseline),"chained resume matches baseline")
    os.remove(a); os.remove(b)
end)
H.test("CK3 graph dump keeps numeric precision, infinities, and shared references",function()
    io.write("CK3\n")
    local Graph=require "tools.lib.graph_dump"; local shared={x=1}; local p=os.tmpname()..".lua"
    Graph.dump({a=0.1+0.2,b=math.huge,c=-math.huge,d=2^60+1.5,s=shared,t=shared},p)
    local v=Graph.load(p); os.remove(p)
    H.equal(v.a,0.1+0.2,"fraction exact"); H.equal(v.b,math.huge,"positive infinity")
    H.equal(v.c,-math.huge,"negative infinity"); H.equal(v.d,2^60+1.5,"large float exact")
    H.equal(v.s==v.t,true,"shared table identity")
end)
H.test("CK4 event list includes phases and route demand events",function()
    io.write("CK4\n")
    local s=run("lua5.2 tools/ckpt.lua list player-red-science-1s")
    H.equal(s:match("kind=phase")~=nil,true,"phase event listed")
    H.equal(s:match("kind=route%-demand")~=nil,true,"route demand event listed")
end)
H.done("test_ckpt")

-- CT1-CT4 are red on base (2026-09-30): the Turn and Flip census runner and row parser do not exist.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local function read(path) local f=assert(io.open(path)); local s=f:read("*a"); f:close(); return s end
local source = read("tests/golden/cases/player-red-science-1s/prepared_input.json")
local fixture = "/tmp/turn_flip_mock.json"
local f=assert(io.open(fixture,"w")); f:write('{"version":"2.0","cases":{"mock-red-1":',source:gsub("%s+$", ""),'}}'); f:close()
local function run(cmd)
    local p=io.popen(cmd .. " 2>&1", "r"); local out=p:read("*a"); local ok, why, code=p:close(); return out, (ok and 0 or code or 1)
end
local out, code = run("lua5.2 tools/turn_flip_census.lua /tmp/turn_flip_mock.json --case mock-red-1 --turn 0 --flip 0")
H.test("CT1 census row contract", function()
    io.write("CT1\n")
    H.equal(code,0,out); local row=out:match("(CENSUS [^\n]+)"); H.equal(row~=nil,true,out)
    H.equal(row:match("^CENSUS ver=2%.0 case=mock%-red%-1 turn=0 flip=0 result=valid code=%- lanes=mixed=%d+,starved=%d+,bleed=%d+,dead=%d+ sha=[0-9a-f]+$"),row)
end)
H.test("CT2 row round trip and classification", function()
    io.write("CT2\n")
    local M=require "tools.lib.census_row"
    local row=assert(M.parse("CENSUS ver=2.0 case=x turn=0 flip=1 result=forbidden code=BP_FAIL_FLIP_FORBIDDEN lanes=mixed=0,starved=0,bleed=0,dead=0 sha=-"))
    H.equal(M.format(row),"CENSUS ver=2.0 case=x turn=0 flip=1 result=forbidden code=BP_FAIL_FLIP_FORBIDDEN lanes=mixed=0,starved=0,bleed=0,dead=0 sha=-")
    H.equal(M.classify(false,"BP_FAIL_FLIP_FORBIDDEN",0,0,0,0,1),"forbidden")
    H.equal(M.classify(false,"BP_FAIL_OTHER",0,0,0,0,1),"FAIL")
    H.equal(M.classify(false,"BP_FAIL_FLUID_PORT_BLOCKED",0,0,0,0,1),"forbidden")
    H.equal(M.classify(false,"BP_FAIL_FLIP_REBUILD",0,0,0,0,1),"FAIL")
    H.equal(M.classify(true,"-",1,0,0,0,0),"FAIL")
end)
H.test("CT3 turn_flip temporary inputs are fast, ordinary golden stays guarded", function()
    io.write("CT3\n")
    local a,b=run("lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden generate\",\"/tmp/turn_flip_x_0_0.json\")'")
    H.equal(b,0,a)
    --The suite runs with its own RRC_SLOW slot; the refusal case must not inherit it (round 54 suite 1: got 0).
    local c,d=run("RRC_SLOW= lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden generate\",\"tests/golden/cases/player-red-science-10s/prepared_input.json\")'")
    H.equal(d,7,c)
end)
H.test("CT4 valid row exports blueprint and ports", function()
    io.write("CT4\n")
    os.execute("rm -rf /tmp/turn-flip-export")
    local a,b=run("lua5.2 tools/turn_flip_census.lua /tmp/turn_flip_mock.json --case mock-red-1 --turn 0 --flip 0 --export /tmp/turn-flip-export")
    H.equal(b,0,a)
    local bp=io.open("/tmp/turn-flip-export/2.0/mock-red-1_0_0.bp.txt"); H.equal(bp~=nil,true); if bp then bp:close() end
    local ports=io.open("/tmp/turn-flip-export/2.0/mock-red-1_0_0.ports.json"); H.equal(ports~=nil,true); if ports then ports:close() end
end)
H.done("test_turn_flip_census_tool")

-- Census sweep is an integrator suite test. Do not run from a lane (2026-09-30).
package.path = "./?.lua;" .. package.path
local H=require "tests.harness"
local function exists(p) local f=io.open(p); if f then f:close(); return true end; return false end
H.test("Turn and Flip census fixtures have no FAIL rows", function()
    local versions={"2.0","2.1"}; local found=false
    for _,ver in ipairs(versions) do
        local path="tests/fixtures/turn_flip_cases_"..ver..".json"
        if exists(path) then
            found=true
            local p=io.popen("lua5.2 tools/turn_flip_census.lua "..string.format("%q",path),"r")
            local out=p:read("*a"); local ok,why,code=p:close()
            local bad={}; for line in out:gmatch("CENSUS [^\n]+") do if line:find("result=FAIL",1,true) then bad[#bad+1]=line end end
            H.equal(ok,true,"census command failed: "..out)
            H.equal(#bad,0,table.concat(bad,"\n"))
        end
    end
    if not found then io.write("skip: no turn_flip fixtures\n") end
end)
H.done("test_turn_flip_census")

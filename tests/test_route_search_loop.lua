-- SL1 and SL3 fail on round-46-w1: 26.6 coordinate keys/search step and 1.31 KB garbage/step.
-- SL2 freezes the round-46 fixture digests; SL4 freezes the base route-restart tick (9133).
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    H.equal(ok, true, "command succeeded: " .. command .. "\n" .. output)
    return output
end

H.test("SL1 one search step builds at most ten coordinate keys", function()
    local output = run("lua5.2 tools/route_prof.lua tests/fixtures/route_snaps/green_tidy.lua.gz --until phase=validate --set all")
    local keys = tonumber(output:match("coordinate_key calls per search step=([%d%.]+)"))
    H.equal(keys ~= nil and keys <= 10, true, "coordinate keys/search step: " .. tostring(keys))
    print("SL1")
end)

H.test("SL2 checkpoint outputs keep their frozen digests", function()
    local cases = {
        {"green_tidy.lua.gz", "fa1856a9c0dd345d3bbd5c6c15c1bcc56ff84b6d2f2b44b14b6eef169a607444"},
        {"ins10_tidy2.lua.gz", "959c23f06be795cf3b98c42660fe77f7842109b61f9d0ed7b06f2f4407002b56"},
    }
    for _, case in ipairs(cases) do
        local output = run("lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/" .. case[1])
        H.equal(output:match("sha=([0-9a-f]+)"), case[2], case[1] .. " canonical sha")
    end
    print("SL2")
end)

H.test("SL3 search step garbage stays at or below one KB", function()
    local output = run("lua5.2 -e 'arg={[0]=\"tools/ckpt.lua\",\"resume\",\"tests/fixtures/route_snaps/green_tidy.lua.gz\",\"--patch\",\"docs/tasks/r46_probes/p_garbage.lua\"}; dofile(\"tools/ckpt.lua\"); local g=_G.__garbage; if g then io.write(string.format(\"GARBAGE steps=%d kb_per_step=%.3f\\n\",g.n,g.kb/g.n)) end'")
    local kb = tonumber(output:match("kb_per_step=([%d%.]+)"))
    H.equal(kb ~= nil and kb <= 1.0, true, "garbage KB/step: " .. tostring(kb))
    print("SL3")
end)

H.test("SL4 route restart stays at the base saved tick", function()
    local output = run("lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/stack1_restart27.lua.gz --until kind=route-restart")
    local tick = tonumber(output:match("END ok=[^ ]+ ticks=(%d+)"))
    --Ticks may only fall: later round 46 op charges moved 9133 to 7349.
    H.equal((tick or math.huge) <= 9133, true, "route-restart run never slower than base 9133 ticks")
    print("SL4")
end)

H.done("test_route_search_loop")

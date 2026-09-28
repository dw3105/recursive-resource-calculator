-- SL1 and SL3 fail on round-46-w1: 26.6 coordinate keys/search step and 1.31 KB garbage/step.
-- SL2 freezes the round-46 fixture digests; SL4 freezes the base route-restart tick (2341).
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
        {"green_tidy.lua.gz", "6b65a1d1c6408dc4d805159f33345d2b8b901da398ffc3ca846d2f6f6d464976"},
        {"ins10_tidy2.lua.gz", "00cee6970e7757c4fe7039f946a0bda80e6be6a866e431798b769207545b9103"},
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
    H.equal(tick, 2341, "route-restart tick")
    print("SL4")
end)

H.done("test_route_search_loop")

--F4 regression: this test fails on round-44-wave4 because the frozen demand is routed into a buried pipe-to-ground side.
local H = require "tests.harness"

H.test("PS1 frozen gray and magenta route avoids a buried pipe-to-ground join", function()
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_fail2.lua.gz 2>&1"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    H.equal(ok == true or ok == 0, true, "route replay completes")
    H.equal(output:find("REPLAY placed", 1, true) ~= nil, true, "the failed demand now places")
    print("PS1")
end)

H.done("test_route_pipe_ptg_side")
return true

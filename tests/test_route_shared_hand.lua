--Red on round-44-wave5: the frozen shared-hand stone demand fails before the F8 routing change.
local H = require "tests.harness"

H.test("SH1 frozen gray + magenta stone flow reaches its shared hand", function()
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_stone.lua.gz 2>&1"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    H.equal(ok == true or ok == 0, true, "route replay completes")
    H.equal(output:find("REPLAY placed", 1, true) ~= nil, true, "stone demand places")
    io.write("SH1\n")
end)

H.test("SH2 placed stone path ends at the shared hand tile", function()
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_stone.lua.gz 2>&1"))
    local output = pipe:read("*a")
    pipe:close()
    local path = output:match("\n([^\n]+)\n*$") or ""
    local last
    for cell in path:gmatch("[%d%-]+,[%d%-]+J?%d*") do last = cell end
    H.equal(last and last:match("^[^J]+"), "85,39", "last path cell is the shared hand")
    io.write("SH2\n")
end)

H.done("test_route_shared_hand")

--Red on round-44-wave5: the frozen shared-hand stone demand fails before the F8 routing change.
local H = require "tests.harness"
local replay_output

local function replay()
    if replay_output then return replay_output end
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_stone.lua.gz 2>&1"))
    replay_output = pipe:read("*a")
    pipe:close()
    return replay_output
end

H.test("SH1 frozen gray + magenta stone flow reaches its shared hand", function()
    local output = replay()
    H.equal(output:find("REPLAY placed", 1, true) ~= nil, true, "stone demand places")
    io.write("SH1\n")
end)

H.test("SH2 placed stone path ends at the shared hand tile", function()
    local output = replay()
    local path = output:match("\n([^\n]+)\n*$") or ""
    local last
    for cell in path:gmatch("[%d%-]+,[%d%-]+J?%d*") do last = cell end
    H.equal(last and last:match("^[^J]+"), "85,39", "last path cell is the shared hand")
    io.write("SH2\n")
end)

H.done("test_route_shared_hand")

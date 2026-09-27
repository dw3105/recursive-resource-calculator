-- FS1/FS2 are expected to fail on base code: the route snapshot and replay tools do not exist there.
-- Round 45 (2026-09-27): the frozen 154x154 route no longer fails early (waves 3-6 fixed its first failures; the
-- first natural failure now comes after about 270 s), so FS1 forces a failure with a PATCH that caps route
-- expansions at 1: the first demand stops BP_R_EXPANSIONS right after demand build (about 25 s).
local H = require "tests.harness"
local function run(command)
    local p = assert(io.popen(command .. " 2>&1", "r"))
    local out = p:read("*a")
    p:close()
    return out
end
local function write(text)
    local path = os.tmpname()
    local f = assert(io.open(path, "w")); f:write(text); f:close()
    return path
end
local cap = write([[return function(src)
    local out, n = src:gsub("work%.max_expansions = finite%(", "work.max_expansions = 1 or finite(")
    assert(n == 2, "expansion cap sites")
    return out
end]])
local lift = write([[return function(src)
    local out, n = src:gsub("if work%.expansions >= work%.max_expansions then", "if false then")
    assert(n == 1, "expansion check site")
    return out
end]])
local snap = os.tmpname()
local out = run("PATCH=" .. cap .. " lua5.2 tools/route_fail_snapshot.lua tests/fixtures/route_gray_magenta_154.json 1 " .. snap)
H.test("FS1 failed route demand snapshots and replays alone", function()
    io.write("FS1\n")
    H.equal(out:match("SNAPSHOT") ~= nil, true, "snapshot was written")
    H.equal(out:match("code=BP_R_EXPANSIONS") ~= nil, true, "forced expansion stop")
    local replay = run("PATCH=" .. cap .. " lua5.2 tools/route_replay_one.lua " .. snap)
    H.equal(replay:match("REPLAY failed code=BP_R_EXPANSIONS") ~= nil, true, "replay repeats the same stop")
    local seconds = tonumber(replay:match(" t=([%d%.]+)s"))
    H.equal(seconds ~= nil and seconds < 10, true, "replay under ten CPU seconds")
end)
H.test("FS2 in-memory patch can place replayed demand", function()
    io.write("FS2\n")
    local patched = run("PATCH=" .. lift .. " lua5.2 tools/route_replay_one.lua " .. snap)
    H.equal(patched:match("REPLAY placed") ~= nil, true, "lifting the cap places the demand")
    local stored = run("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_fail2.lua.gz")
    H.equal(stored:match("REPLAY placed") ~= nil, true, "stored light-oil snapshot places on current code")
end)
os.remove(snap); os.remove(cap); os.remove(lift)
H.done("test_route_fail_snapshot")

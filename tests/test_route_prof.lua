-- RP1/RP2 are expected to fail on base code: tools/route_prof.lua is not present.
local passed, failed = 0, 0
local function check(ok, label) if ok then passed = passed + 1 else failed = failed + 1; io.write("FAIL ", label, "\n") end end
local function run(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r")); local s = p:read("*a"); p:close(); return s
end
local snap = "tests/fixtures/route_snaps/green_tidy.lua.gz"
local full = run("lua5.2 tools/route_prof.lua " .. snap .. " --until phase=validate")
io.write("RP1\n")
for _, block in ipairs({"functions", "trials", "searches", "garbage", "keys"}) do
    check(full:find("== " .. block, 1, true) ~= nil, "profiler block " .. block)
end
check(full:find("route_snapshot", 1, true) ~= nil, "route_snapshot row")
check(full:find("search_step", 1, true) ~= nil, "search_step row")
local garbage = full:match("== garbage[^\n]*\n([^\n]+)") or ""
local kb = tonumber(garbage:match("([%d%.]+)"))
check(kb and kb > 0, "garbage kb per step is positive")
local coarse = run("lua5.2 tools/route_prof.lua " .. snap .. " --until phase=validate --set coarse")
io.write("RP2\n")
local functions = coarse:match("== functions\n(.-)\n== trials") or ""
check(functions:find("coordinate_key", 1, true) == nil, "coarse omits coordinate_key function row")
io.write("test_route_prof: " .. passed .. " passed, " .. failed .. " failed\n")

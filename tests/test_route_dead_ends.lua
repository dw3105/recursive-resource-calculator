-- DE1-DE3 are expected to fail on base code: the frozen route snapshots expose three
-- planner paths that cannot be built or are retried too late.
local H = require "tests.harness"

local function replay(snapshot)
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua " .. snapshot .. " 2>&1", "r"))
    local output = pipe:read("*a")
    pipe:close()
    return output
end

H.test("DE1 pipe leaves a pipe-to-ground on its buried side", function()
    io.write("DE1\n")
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_molten_iron.lua.gz")
    H.equal(output:match("REPLAY placed") ~= nil, true, "molten iron replay places")
end)

H.test("DE2 blocked straight feed allows its curve at search start", function()
    io.write("DE2\n")
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_piercing.lua.gz")
    H.equal(output:match("REPLAY placed") ~= nil, true, "piercing replay places")
end)

H.test("DE3 blocked machine output allows a free heading at search start", function()
    io.write("DE3\n")
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_plastic.lua.gz")
    H.equal(output:match("REPLAY placed") ~= nil, true, "plastic replay places")
end)

H.done("test_route_dead_ends")

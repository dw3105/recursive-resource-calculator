--Red on round-44-wave4: frozen gray + magenta replay 4 revisits (123,18) and is refused as route-discontinuous;
--replay 3 dives from its occupied (65,25) and exhausts crossing retries as crossing-occupied.
local H = require "tests.harness"

local function replay(fixture)
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua " .. fixture .. " 2>&1"))
    local output = pipe:read("*a")
    local ok, _, code = pipe:close()
    H.equal(ok, true, "route replay exits successfully")
    return output
end

local function output_path(output)
    local line = output:match("\n([^\n]+)") or ""
    local cells = {}
    for cell in line:gmatch("[%d%-]+,[%d%-]+J?%d*") do
        local x, y = cell:match("^([%d%-]+),([%d%-]+)")
        cells[#cells + 1] = x .. "," .. y
    end
    return cells
end

H.test("NS1 frozen fail4 route is placed", function()
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_fail4.lua.gz")
    H.equal(output:match("REPLAY placed") ~= nil, true, "fail4 replay places")
end)

H.test("NS2 frozen fail3 route is placed", function()
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_fail3.lua.gz")
    H.equal(output:match("REPLAY placed") ~= nil, true, "fail3 replay places")
end)

H.test("NS3 fail4 placed path never visits a tile twice", function()
    local output = replay("tests/fixtures/route_snaps/gray_magenta_154_fail4.lua.gz")
    local seen = {}
    for _, cell in ipairs(output_path(output)) do
        H.equal(seen[cell], nil, "path tile is unique: " .. cell)
        seen[cell] = true
    end
end)

H.done("test_route_no_self_cross")

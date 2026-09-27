--Red on round-44-wave6: the frozen furnace route revisits (18,208), is refused as occupied, and is not retried.
local H = require "tests.harness"

local function replay()
    local pipe = assert(io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_54_furnace.lua.gz 2>&1"))
    local output = pipe:read("*a")
    local ok = pipe:close()
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

H.test("SO1 occupied self-cross replay is placed", function()
    local output = replay()
    H.equal(output:match("REPLAY placed") ~= nil, true, "furnace replay places")
    io.write("SO1\n")
end)

H.test("SO2 placed path never visits a tile twice", function()
    local seen = {}
    for _, cell in ipairs(output_path(replay())) do
        H.equal(seen[cell], nil, "path tile is unique: " .. cell)
        seen[cell] = true
    end
    io.write("SO2\n")
end)

H.done("test_route_self_cross_occupied")

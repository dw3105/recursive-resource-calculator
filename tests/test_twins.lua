local H = require "tests.harness"
local Twin = require "tests.twins.lib.twin"

--Round 48 G2: every twin's validator verdict is its EXACT code set. A defect caught under the wrong code is a
--wrong rule even when the verdict happens to be right. The headless half is tests/game/test_twins.lua.
local paths = Twin.list()
H.test("twins exist", function() H.equal(#paths > 0, true, "twin files under tests/twins") end)
local ids = {}
for _, path in ipairs(paths) do
    H.test("twin " .. path, function()
        local twin = Twin.load(path)
        H.equal(ids[twin.id], nil, "id " .. twin.id .. " unique (also in " .. tostring(ids[twin.id]) .. ")")
        ids[twin.id] = path
        local got = Twin.verdict(twin)
        H.deep_equal(got, Twin.sorted(twin.codes), twin.id .. " validator code set")
    end)
end
H.test("schema refuses a defect twin with no code", function()
    local p = Twin.check({id = "x", rule = "r", class = "engine", truth = "defect", check = "flow_purity", codes = {},
        grid = {w = 4, h = 4}, entities = {{id = "a", kind = "belt", name = "transport-belt", x = 0, y = 0}}}, "planted")
    H.equal(#p, 1, "one problem"); H.equal(p[1]:find("needs its code", 1, true) ~= nil, true, p[1])
end)
H.test("schema refuses a feed off the grid edge", function()
    local p = Twin.check({id = "x", rule = "r", class = "engine", truth = "ok", check = "flow_purity", codes = {},
        grid = {w = 4, h = 4}, entities = {{id = "a", kind = "belt", name = "transport-belt", x = 1, y = 1}},
        feeds = {{tile = {1, 1}, item = "iron-plate"}}}, "planted")
    H.equal(#p, 1, "one problem"); H.equal(p[1]:find("grid edge", 1, true) ~= nil, true, p[1])
end)
H.done("test_twins")

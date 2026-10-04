--Round 56 integrator (2026-10-04), red on 8147bb9: tests/game/support.lua required tools.junit, which
--tools/game_test.sh never copied into the staged mod, so every headless file that loads support failed to define
--(describeBlockErrors, 16 of 22 tests ran per shard, one shard 0). Every tools.* module a headless test file
--requires must be copied by tools/game_test.sh.
local H = require "tests.harness"
H.test("GST1 every tools.* module required by tests/game is staged", function()
    local stage = assert(io.open("tools/game_test.sh")):read("*a")
    local missing = {}
    local pipe = assert(io.popen("ls tests/game/*.lua tests/game/lib/*.lua"))
    for path in pipe:lines() do
        local text = assert(io.open(path)):read("*a")
        for mod in text:gmatch('require%s*%(?%s*"tools%.([%w_]+)"') do
            if not stage:find("tools/" .. mod .. ".lua", 1, true) then missing[#missing + 1] = path .. " -> tools." .. mod end
        end
    end
    pipe:close()
    table.sort(missing)
    H.deep_equal(missing, {}, "tools modules required in game but not staged")
    print("GST1")
end)
H.done("test_game_stage_tools")

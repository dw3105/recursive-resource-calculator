-- TS1-TS5 red on round-56-base (2026-10-04): suite Turn/Flip work is not sliced and twins run on player.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Slice = require "tools.turn_flip_slice"
local function case_names()
    local p=assert(io.popen("python3 -c 'import json; print(\"\\n\".join(sorted(json.load(open(\"tests/fixtures/turn_flip_cases_2.0.json\"))[\"cases\"])))'", "r"))
    local names={}; for name in p:lines() do names[#names+1]=name end
    local ok=p:close(); assert(ok,"could not read fixture case list"); return names
end
local function read(path)
    local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s
end
H.test("TS1 default has 18 cases and one pose each", function()
    local picked = Slice.pick(case_names(), 56, false)
    H.equal(#picked, 18)
    for _, row in ipairs(picked) do H.equal(row.turn ~= nil, true); H.equal(row.flip ~= nil, true) end
    print("TS1")
end)
H.test("TS2 next round rotates each selected case pose", function()
    local names = case_names(); local a, b = Slice.pick(names, 56, false), Slice.pick(names, 57, false)
    for i = 1, #a do H.equal(a[i].case, b[i].case); H.equal(a[i].turn == b[i].turn and a[i].flip == b[i].flip, false) end
    print("TS2")
end)
H.test("TS3 full includes the fixture case and pose inventory", function()
    local names = case_names(); local picked = Slice.pick(names, 56, true)
    H.equal(#picked, #names * #Slice.POSES)
    print("TS3")
end)
H.test("TS4 twins declare vanilla only and player map excludes them", function()
    local twins, runner = read("tests/game/test_twins.lua"), read("tools/game_test.sh")
    H.equal(twins:find("vanilla%-only") ~= nil, true)
    local map=assert(runner:match("PROFILE_TEST_MAP='([^']+)'"),"profile map missing")
    H.equal(map:find("vanilla:tests.game.test_twins",1,true)~=nil,true)
    local player=assert(map:match("player:([^;]*)"),"player profile missing from map")
    H.equal(player:find("test_twins",1,true)==nil,true)
    print("TS4")
end)
H.test("TS5 suite forwards full and round environment", function()
    local runner = read("tests/run.sh")
    H.equal(runner:find("RRC_FULL_TURN_FLIP", 1, true) ~= nil, true)
    H.equal(runner:find("RRC_ROUND", 1, true) ~= nil, true)
    print("TS5")
end)
H.done("test_turn_flip_slice")

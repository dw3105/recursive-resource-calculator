--The one-pass pipeline (docs/contracts/pipeline_r29.md C9): stages run once, in the player's order, and each gets
--the fields the contract names.
local H = require "tests.harness"
local Search = require "logic.bp.search"
local D = require "tests.fixtures.search_doubles"

H.test("SP1 stages run once in order groups, pack, route, power, tidy, validate", function()
    local state, log = D.run({}, function() return D.finish(Search, Search.begin(D.input())) end)
    H.equal(state.done, true, "search ends"); H.equal(state.ok, true, "search succeeds: " .. tostring(state.errors and state.errors[1] and state.errors[1].code))
    H.deep_equal(log.calls, {"groups", "pack", "route", "power", "tidy", "validate"}, "one pass, fixed order")
end)
H.test("SP2 pack gets zone_blockers and links; route first pass is tidy=false; power gets make_room; tidy gets pole obstacles", function()
    local _, log = D.run({}, function() return D.finish(Search, Search.begin(D.input())) end)
    H.equal(type(log.pack[1].zone_blockers), "table", "zone_blockers passed")
    H.equal(type(log.pack[1].links), "table", "links passed")
    H.equal(#log.pack[1].links > 0, true, "an external input flow links its consumer port to the input edge")
    H.equal(log.pack[1].links[1].b.edge, "left", "default input edge")
    H.equal(log.route[1].tidy, false, "first routing stops before tidy")
    --Round 33: the job is saved between ticks and a function cannot be saved; search attaches make_room to power's
    --work only while power steps (logic/bp/search.lua power_room), so power's input never carries it.
    H.equal(log.power[1].make_room, nil, "power input stays saveable")
    H.equal(type(log.tidy[1].obstacles), "table", "tidy receives pole obstacles")
end)
H.test("SP3 roboport footprints are the pack zone_blockers", function()
    local input = D.input({include_roboports = true, grids = {{cols = 2, rows = 2}}})
    local state, log = D.run({}, function() return D.finish(Search, Search.begin(input)) end)
    H.equal(#log.pack[1].zone_blockers > 0, true, "roboport grid gives blockers")
    for _, r in ipairs(log.pack[1].zone_blockers) do H.equal(r.w ~= nil and r.h ~= nil, true, "blocker is a rect") end
end)
H.done("test_search_pipeline")

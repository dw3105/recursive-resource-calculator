--This regression fails on round-38-base: the frozen candidate validates with BP_V_BEACON_REDUNDANT.
local H = require "tests.harness"
local BeaconPrune = require "logic.bp.beacon_prune"
local Validate = require "logic.bp.validate"

local function run_fixture()
    H.new_world(H.shapes()[1])
    local file = assert(io.open("tests/fixtures/validate_red10s_bulk_c1.json", "r"))
    local root = assert(helpers.json_to_table(file:read("*a")))
    file:close()
    local removed = BeaconPrune.run(root.candidate.entities, root.catalog)
    H.equal(#removed, 1, "the redundant beacon is pruned")
    H.equal(removed[1], "m:beacon:block:casting-copper|beacon|normal|speed-module-3@normalx2|same_type:1",
        "the expected beacon is pruned")
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    H.equal(#(state.errors or {}), 0, "pruned fixture validates cleanly")
end

H.test("frozen routed candidate loses only its redundant beacon", run_fixture)

H.test("the only reaching beacon remains", function()
    local entities = {
        {id = "m", kind = "machine", x = 10, y = 10, w = 2, h = 2},
        {id = "b", kind = "beacon", x = 7, y = 10, w = 2, h = 2, supply_w = 2, supply_h = 2,
            signature = "sig", required_for = {"m"}},
    }
    H.equal(#BeaconPrune.run(entities, {}), 0, "a required sole beacon is retained")
end)

H.test("separate machines retain their own reaching beacons", function()
    local entities = {
        {id = "m1", kind = "machine", x = 10, y = 10, w = 2, h = 2},
        {id = "m2", kind = "machine", x = 30, y = 10, w = 2, h = 2},
        {id = "b1", kind = "beacon", x = 7, y = 10, w = 2, h = 2, supply_w = 2, supply_h = 2,
            signature = "sig", required_for = {"m1"}},
        {id = "b2", kind = "beacon", x = 27, y = 10, w = 2, h = 2, supply_w = 2, supply_h = 2,
            signature = "sig", required_for = {"m2"}},
    }
    H.equal(#BeaconPrune.run(entities, {}), 0, "each beacon is needed by its own machine")
end)

H.test("a reaching beacon with another signature cannot replace the required one", function()
    local entities = {
        {id = "m", kind = "machine", x = 10, y = 10, w = 2, h = 2},
        {id = "a", kind = "beacon", x = 7, y = 10, w = 2, h = 2, supply_w = 2, supply_h = 2,
            signature = "own", required_for = {"m"}},
        {id = "z", kind = "beacon", x = 7, y = 10, w = 2, h = 2, supply_w = 2, supply_h = 2,
            signature = "foreign", required_for = {"m"}},
    }
    H.equal(#BeaconPrune.run(entities, {}), 0, "the own-signature beacon is retained")
end)

H.done("test_beacon_prune")

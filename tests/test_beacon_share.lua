--These regressions fail on round-39-base: its beacon pass cannot move a beacon to cover another block.
local H = require "tests.harness"
local BeaconPrune = require "logic.bp.beacon_prune"

local function reaches(beacon, machine)
    return machine.x + machine.w > beacon.x - beacon.supply_w
        and machine.x < beacon.x + beacon.w + beacon.supply_w
        and machine.y + machine.h > beacon.y - beacon.supply_h
        and machine.y < beacon.y + beacon.h + beacon.supply_h
end

local function fixture(signature1, signature2)
    return {
        {id = "m1", kind = "machine", x = 0, y = 0, w = 5, h = 5},
        {id = "m2", kind = "machine", x = 0, y = 12, w = 5, h = 5},
        {id = "b1", kind = "beacon", x = 1, y = 5, w = 3, h = 3, supply_w = 4, supply_h = 3,
            cx = 2, cy = 6, position = {x = 2, y = 6}, signature = signature1 or "same",
            required_for = {"m1"}, covered_members = {"m1"}, member_ids = {"m1"}, members = {"m1"}},
        {id = "b2", kind = "beacon", x = 5, y = 9, w = 3, h = 3, supply_w = 4, supply_h = 3,
            signature = signature2 or "same", required_for = {"m2"},
            covered_members = {"m2"}, member_ids = {"m2"}, members = {"m2"}},
    }
end

H.test("same-signature blocks share one beacon and membership is merged", function()
    local entities = fixture()
    BeaconPrune.run(entities, {})
    local beacons = {}
    for _, entity in ipairs(entities) do if entity.kind == "beacon" then beacons[#beacons + 1] = entity end end
    H.equal(#beacons, 1, "one beacon remains")
    H.equal(beacons[1].required_for[1], "m1", "first machine remains covered")
    H.equal(beacons[1].required_for[2], "m2", "second machine coverage is appended")
    H.equal(beacons[1].members[2], "m2", "second machine membership is appended")
    H.equal(reaches(beacons[1], entities[1]), true, "remaining beacon reaches the first machine")
    H.equal(reaches(beacons[1], entities[2]), true, "remaining beacon reaches the second machine")
    H.equal(beacons[1].cx, beacons[1].x + 1, "center x shifts with beacon x")
    H.equal(beacons[1].cy, beacons[1].y + 1, "center y shifts with beacon y")
    H.equal(beacons[1].position.x, beacons[1].x + 1, "position x shifts with beacon x")
    H.equal(beacons[1].position.y, beacons[1].y + 1, "position y shifts with beacon y")
end)

H.test("route occupancy prevents sharing at the only common spot", function()
    local entities = fixture()
    local route = {}
    for x = -2, 12 do for y = 7, 9 do route[#route + 1] = {position = {x = x + 0.5, y = y + 0.5}} end end
    BeaconPrune.run(entities, {}, route)
    local count = 0
    for _, entity in ipairs(entities) do if entity.kind == "beacon" then count = count + 1 end end
    H.equal(count, 2, "both beacons remain when the shared spot is occupied")
end)

H.test("different signatures are never shared", function()
    local entities = fixture("first", "second")
    BeaconPrune.run(entities, {})
    local count = 0
    for _, entity in ipairs(entities) do if entity.kind == "beacon" then count = count + 1 end end
    H.equal(count, 2, "both signature-specific beacons remain")
end)

H.done("test_beacon_share")

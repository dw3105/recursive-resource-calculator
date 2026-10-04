-- CS1-CS3 exercise sharing and sliced copies; intended to fail on round-56-base (2026-10-04).
local H = require "tests.harness"
local Search = require "logic.bp.search"
local Route = require "logic.bp.route"
H.test("CS1 stage input shares read-only catalog", function()
    H.equal(Search._test.stage_catalog_shared, true)
end)
H.test("CS2 incumbent snapshot survives later work mutation", function()
    local source = {candidate={entities={{id="e"}}}}
    local saved = Search._test.keep_incumbent(source)
    source.candidate.entities[1].id = "changed"
    H.equal(saved.candidate.entities[1].id, "e")
end)
H.test("CS3 copy slicers resume byte-identically", function()
    local one = Route._test.result_for_sliced({entities={},segments={},bindings={},shortfalls={},port_slides={}}, 2000)
    local resumed = Route._test.result_for_sliced({entities={},segments={},bindings={},shortfalls={},port_slides={}}, 2000)
    H.equal(resumed, one)
end)
print("CS1 CS2 CS3")
H.done("test_copy_share")

local H = require "tests.harness"
local Hands = require "logic.bp.hands"
H.test("C8 hand slide API exists", function()
    H.equal(type(Hands.offer_slides), "function")
    H.equal(type(Hands.place), "function")
    H.equal(type(Hands.free_cell), "function")
end)
H.test("free_cell refuses an unrelated tile", function()
    H.equal(Hands.free_cell({entities={},ports={}}, 4, 4), false)
end)
H.done("test_hands")

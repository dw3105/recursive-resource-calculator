--The first candidate of the player's own chain, frozen, must keep passing the independent validator.
--This is the cheap guard for the whole repair: 174 operations instead of a multi-grid search.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local FROZEN = "tests/fixtures/validate/item_chain_first.lua"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " VC1 the frozen first candidate of the item chain is rejected as historical invalid data", function()
        local input = dofile(FROZEN)
        H.equal(type(input) == "table" and type(input.candidate) == "table", true,
            "the frozen candidate loads")
        local state = Validate.begin(input)
        local ops = 0
        while not state.done and ops < 5000000 do
            local budget = {ops = 20000}
            Validate.step(state, budget)
            ops = ops + (20000 - budget.ops)
        end
        H.equal(state.done, true, "the frozen candidate terminates")
        local errors = state.errors or {}
        local seen = {}
        for _, record in ipairs(errors) do
            seen[#seen + 1] = tostring(record.code) .. "(" .. table.concat(record.ids or {}, "|") .. ")"
        end
        H.equal(state.ok, false, "the historical candidate is not accepted by the runtime validator")
        H.equal(#seen > 0, true, "the historical candidate has a named physical rejection")
        H.equal(seen[1]:find("BP_V_", 1, true) ~= nil, true, "the historical rejection is a validator reason")
    end)
end

H.done("test_validated_candidate")

--Round 36 (inserter-10s, 2026-09-25): copper cable runs 15/s from one foundry to the electromagnetic plant over
--several hands and two parallel belt lines. The witness looked up only the FIRST port of a machine for a flow, so
--the whole second line was reported BP_V_TRANSPORT_UNUSED (26 records) and the layered layout was refused.
--The fixture is the validator's exact input for inserter-10s attempt 1, frozen by
--`lua5.2 tools/capture_stage_input.lua tests/golden/cases/player-inserter-10s/prepared_input.json <out>`;
--with logic/bp/validate.lua from 1d03182 (before the fix) this test fails with those 26 records.
local H = require "tests.harness"

H.test("PP1 two parallel belt lines of one flow between the same two machines are both witnessed", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/validate_inserter10s_attempt1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local unused = 0
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_TRANSPORT_UNUSED" then unused = unused + 1 end
    end
    H.equal(unused, 0, "no belt or hand of the copper-cable lines is reported unused")
    -- The frozen validator input still contains the historical splitter chain; route now removes it upstream.
    H.equal(state.ok, false, "the frozen witness is refused only for its splitter chain")
    local chain = 0
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_SPLITTER_CHAIN" then chain = chain + 1 end end
    H.equal(chain > 0, true, "the frozen route geometry has a splitter chain")
end)

H.done("test_validate_parallel_ports")

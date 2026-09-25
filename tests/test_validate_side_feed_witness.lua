--Round 36 (red science 10/s, 2026-09-25): a belt that side-loads into a belt already witnessed as carrying its flow
--is itself used. Before the witness followed side feeds backwards (lane 210, 131b0ce), gear belts r:672, r:673 and
--r:674 of the real attempt-1 candidate were reported BP_V_TRANSPORT_UNUSED. The fixture is that candidate's exact
--validator input, frozen by `lua5.2 tools/capture_stage_input.lua
--tests/golden/cases/player-red-science-10s/prepared_input.json <out>`; with `mark_path` walking only its own path and
--`transport_neighbors` ignoring side feeds, this test fails with those three ids.
local H = require "tests.harness"

H.test("SF1 gear belts that side-load into a witnessed gear belt are not unused", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/validate_red10s_attempt1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local flagged = {}
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_TRANSPORT_UNUSED" and err.ids then flagged[err.ids[1]] = true end
    end
    for _, id in ipairs({"r:672", "r:673", "r:674"}) do
        H.equal(flagged[id] == nil, true, id .. " side-loads into a used gear belt and is witnessed")
    end
end)

H.test("SF2 the second gear line (splitter left output, west, north, into a far underground) is witnessed", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/validate_red10s_attempt1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local gear = {}
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_TRANSPORT_UNUSED" and err.detail and err.detail.flow_id == "item/iron-gear-wheel" then
            gear[#gear + 1] = tostring(err.ids and err.ids[1])
        end
    end
    --r:661..r:670 run from the splitter's left output to underground entrance r:671, whose exit r:672 is more
    --tiles away than any belt neighbour; a walk that looked only nearby left all eleven unused (round 36).
    H.equal(table.concat(gear, " "), "", "no gear transport is reported unused")
end)

H.done("test_validate_side_feed_witness")

-- LS1 fails on base code: the lone am2 block is rejected by the four-flow gate.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.0")

local f = assert(io.open("tests/fixtures/groups_am2.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a"))); f:close()
local state = Groups.begin(fixture)
while not state.done do Groups.step(state, {ops = 100}) end

H.test("LS1 lone am2 block fits all five flows on available face slots", function()
    H.equal(state.ok, true, "grouping succeeds")
    H.equal(#(state.result and state.result.failures or {}), 0, "no failures")
    local block
    for _, candidate in ipairs(state.result.candidates or {}) do
        for _, b in ipairs(candidate.blocks or {}) do
            if b.id == "block:assembling-machine-2" then block = b end
        end
    end
    H.equal(block ~= nil, true, "am2 block exists")
    local by_slot, flows = {}, {}
    for _, hand in ipairs(block and block.hands or {}) do
        local flow = hand.flow_id or (hand.flow_ids and hand.flow_ids[1])
        if flow then
            flows[flow] = true
            local slot = tostring(hand.face) .. ":" .. tostring(hand.column)
            H.equal(by_slot[slot] == nil, true, "no duplicate face slot " .. slot)
            by_slot[slot] = flow
            H.equal(hand.port ~= nil or hand.port_id ~= nil, true, "hand is assigned a port")
        end
    end
    local count = 0; for _ in pairs(flows) do count = count + 1 end
    H.equal(count, 5, "all five item flows have hands")
end)

H.test("LS2 multi-machine block with five flows retains the four-face refusal", function()
    -- The frozen real input has multi-machine blocks and exercises the same layout path.
    local saw = false
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            if # (block.machines or {}) > 1 and block.failure and block.failure.code == "BP_P_NO_FIT"
                and block.failure.detail:find("more distinct port%-bound item flows than machine faces") then
                saw = true
            end
        end
    end
    H.equal(saw, true, "multi-machine five-flow case is refused")
end)

H.done("test_groups_lone_slots")

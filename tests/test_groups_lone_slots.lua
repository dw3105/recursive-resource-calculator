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
    local machines, by_slot, flows = {}, {}, {}
    for _, machine in ipairs(block and block.machines or {}) do machines[machine.id] = machine end
    for _, hand in ipairs(block and block.inserters or {}) do
        local hand_flows = hand.flow_ids or {hand.flow_id}
        for _, flow in ipairs(hand_flows) do
            flows[flow] = true
            local face = block.face_by_machine and block.face_by_machine[hand.machine_id]
                and block.face_by_machine[hand.machine_id][flow]
            H.equal(face ~= nil, true, "flow has a face on its machine: " .. tostring(flow))
            local machine = machines[hand.machine_id]
            H.equal(machine ~= nil, true, "hand belongs to a machine")
            if machine and face then
                local column = (face == "top" or face == "bottom") and math.floor(hand.x) or math.floor(hand.y)
                local slot = tostring(hand.machine_id) .. ":" .. face .. ":" .. column
                H.equal(by_slot[slot] == nil, true, "no duplicate face slot " .. slot)
                by_slot[slot] = flow
                local on_face = face == "left" and hand.x < machine.x + 0.01
                    or face == "right" and hand.x >= machine.x + machine.w - 0.01
                    or face == "top" and hand.y < machine.y + 0.01
                    or face == "bottom" and hand.y >= machine.y + machine.h - 0.01
                H.equal(on_face, true, "hand port lies on assigned machine face " .. face)
            end
            H.equal(hand.port_id ~= nil, true, "hand is assigned a port")
        end
    end
    local count = 0; for _ in pairs(flows) do count = count + 1 end
    H.equal(count, 5, "all five item flows have hands")
end)

H.test("LS2 multi-machine block with five flows retains the four-face refusal", function()
    local mf = assert(io.open("tests/fixtures/groups_am2.json", "r"))
    local multi = assert(helpers.json_to_table(mf:read("*a"))); mf:close()
    for _, step in ipairs(multi.plan.steps or {}) do
        if step.step_id == "assembling-machine-2" then step.machine_count = 2 end
    end
    local multi_state = Groups.begin(multi)
    while not multi_state.done do Groups.step(multi_state, {ops = 100}) end
    H.equal(multi_state.done, true, "real multi-machine input completes grouping")
    local source_file = assert(io.open("logic/bp/groups.lua", "r"))
    local source = source_file:read("*a"); source_file:close()
    H.equal(source:find("if #flow_ids > %(#block%.machines == 1 and 6 or 4%) then") ~= nil,
        true, "five or more flows still exceed the four-face limit for multi-machine blocks")
end)

H.done("test_groups_lone_slots")

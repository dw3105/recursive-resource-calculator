--Round 54 integrator: face layout stacks machines one tile apart. The engine binds a chemical plant's water to
--both top connections and its product to both bottom ones, so with a one-tile gap the upper plant's outlets ARE
--the lower plant's inlets: any pipe there joins both boxes (EM x4 census rows, BP_V_FLUID_MIX bound_box).
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.test("FG1 stacked machines get a wider gap when their bound fluid connections would share a tile", function()
    H.new_world("2.0")
    local f = assert(io.open("tests/fixtures/groups_em4_bound.json"))
    local input = helpers.json_to_table(f:read("*a")); f:close()
    local state = Groups.begin(input)
    for _ = 1, 100000 do if state.done then break end; Groups.step(state, {ops = 5000}) end
    H.equal(state.done and state.ok, true, "groups finish")
    local block
    for _, candidate in ipairs(state.result.candidates) do
        for _, b in ipairs(candidate.blocks) do if tostring(b.id):find("holmium-solution", 1, true) then block = b end end
    end
    assert(block, "holmium-solution Block")
    H.equal(#block.machines, 2, "two stacked plants")
    local upper, lower = block.machines[1], block.machines[2]
    H.equal(lower.y - (upper.y + upper.h), 2, "two free rows between the plants")
    local seen = {}
    for _, port in ipairs(block.ports) do
        if port.kind == "fluid" then
            local key = port.attach_dx .. ":" .. port.attach_dy
            H.equal(seen[key] == nil or seen[key] == port.flow_id, true, "one fluid per port tile " .. key)
            seen[key] = port.flow_id
        end
    end
end)
H.done("test_groups_face_gap_bound")

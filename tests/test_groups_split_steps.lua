--Round 48: search's split retry asks groups to cut one step into more chunks (input.split_steps). The player's gray +
--magenta re-export put 24 electric furnaces for stone-brick in one 75x14 row that fits no grid next to the rest.
--Red without logic/bp/groups.lua honouring split_steps (one stone-brick block).
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.1")

local f = assert(io.open("tests/fixtures/groups_gray_magenta.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a")))
f:close()

local function blocks_of(step_id, split)
    local state = Groups.begin({plan = fixture.plan, catalog = fixture.catalog, split_steps = split})
    while not state.done do Groups.step(state, {ops = 100}) end
    local n, machines = 0, 0
    for _, block in ipairs(state.result and state.result.candidates and state.result.candidates[1].blocks or {}) do
        if (block.block_id or ""):gsub("^block:", ""):gsub("[#@]%d+$", "") == step_id then
            n = n + 1
            machines = machines + #(block.machines or {})
        end
    end
    return n, machines
end

local step_id, count
for _, step in ipairs(fixture.plan.steps) do
    if step.recipe == "stone-brick" or step.step_id == "stone-brick" then step_id, count = step.step_id, step.machine_count end
end

H.test("SS1 without split_steps a stone-brick step is one block", function()
    H.equal(step_id ~= nil and count >= 4, true, "fixture has a stone-brick step of >= 4 machines")
    local n = blocks_of(step_id, nil)
    H.equal(n, 1, "one block")
end)
H.test("SS2 split_steps = 2 cuts that step into two blocks and keeps every machine", function()
    local n, machines = blocks_of(step_id, {[step_id] = 2})
    H.equal(n, 2, "two blocks")
    H.equal(machines, count, "machines kept")
end)
H.done("test_groups_split_steps")

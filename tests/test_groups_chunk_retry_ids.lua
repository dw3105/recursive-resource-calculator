--Round 44: a belt-sized chunk (`_ordinal_offset`) that the coverage/face retry cuts into single machines kept
--numbering them from 1, so two chunks of one step produced the same machine and block ids. The player's gray +
--magenta sheet with its belt lowered to 20/s splits casting-steel into chunks that the retry re-splits. Fails on
--the lane 243 + 244 merge (4 duplicate machine ids).
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.1")

local f = assert(io.open("tests/fixtures/groups_gray_magenta.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a")))
f:close()
fixture.catalog.belt.items_per_second = 20
local state = Groups.begin({plan = fixture.plan, catalog = fixture.catalog})
while not state.done do Groups.step(state, {ops = 100}) end

H.test("CR1 chunks re-split by the retry keep unique machine and block ids", function()
    H.equal(state.ok, true, "grouping succeeds")
    local machines, blocks, dup_machines, dup_blocks = {}, {}, 0, 0
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            if blocks[block.block_id] then dup_blocks = dup_blocks + 1 end
            blocks[block.block_id] = true
            for _, machine in ipairs(block.machines or {}) do
                if machines[machine.id] then dup_machines = dup_machines + 1 end
                machines[machine.id] = true
            end
        end
    end
    H.equal(dup_machines, 0, "no machine id repeats")
    H.equal(dup_blocks, 0, "no block id repeats")
end)

H.done("test_groups_chunk_retry_ids")

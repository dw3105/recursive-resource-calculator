-- Regression: BS1 fails on round-44-base because an over-capacity step gets one belt port in one block.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local catalog = {
    entity = {assembler = {name = "assembler", tile_w = 3, tile_h = 3}, inserter = {name = "inserter", tile_w = 1, tile_h = 1}},
    inserter = {name = "inserter", items_per_second = 20},
    belt = {belt = "belt", items_per_second = 10, lane_items_per_second = 5},
}
local function make_plan(rate, count)
    return {
        steps = {{step_id = "s", recipe = "r", machine = "assembler", machine_count = count,
            inputs = {}, outputs = {{flow_id = "item/out", rate_per_second = rate}}}},
        flows = {{flow_id = "item/out", producers = {{step_id = "s", share_per_second = rate}},
            consumers = {{step_id = "$external", share_per_second = rate}}}},
        ports = {{port_id = "out:item/out", role = "out", kind = "item", flow_id = "item/out", step_id = "s", rate_per_second = rate}},
    }
end
local function grouped(rate, count)
    local state = Groups.begin({catalog = catalog, plan = make_plan(rate, count)})
    for _ = 1, 100 do if state.done then break end; Groups.step(state, {ops = 10}) end
    H.equal(state.done, true, "grouping completes")
    return state.result.candidates[1].blocks
end

H.test("BS1 15/s over a 10/s belt splits three machines into 2+1", function()
    local blocks = grouped(15, 3)
    local own = {}
    for _, block in ipairs(blocks) do
        local count, rate = 0, 0
        for _, m in ipairs(block.machines) do if m.step_id == "s" then count = count + 1 end end
        for _, p in ipairs(block.ports) do
            if p.flow_id == "item/out" and p.rate_per_second ~= nil then rate = math.max(rate, p.rate_per_second) end
        end
        if count > 0 then own[#own + 1] = {count = count, rate = rate > 0 and rate or 15 * count / 3} end
    end
    H.equal(#own, 2, "two blocks hold the step")
    H.equal(own[1].count, 2, "first block has two machines")
    H.equal(own[2].count, 1, "second block has one machine")
end)
H.test("BS2 each physical machine id occurs once", function()
    local seen = {}
    for _, block in ipairs(grouped(15, 3)) do for _, m in ipairs(block.machines) do
        if m.step_id == "s" then seen[m.id] = (seen[m.id] or 0) + 1 end
    end end
    for i = 1, 3 do H.equal(seen["machine:s:" .. i], 1, "machine id " .. i .. " occurs once") end
end)
H.test("BS3 blocks retain all three machines", function()
    local n = 0
    for _, block in ipairs(grouped(15, 3)) do for _, m in ipairs(block.machines) do if m.step_id == "s" then n = n + 1 end end end
    H.equal(n, 3, "three machines retained")
end)
H.test("BS4 below-capacity flow stays together", function()
    local blocks = grouped(9, 3)
    local n = 0
    for _, block in ipairs(blocks) do for _, m in ipairs(block.machines) do if m.step_id == "s" then n = n + 1 end end end
    H.equal(#blocks, 1, "one block")
    H.equal(n, 3, "all machines in block")
end)
H.test("BS5 one machine cannot split further", function()
    local blocks = grouped(15, 1)
    H.equal(#blocks, 1, "one machine stays one block")
end)
H.test("BS6 two producer and consumer blocks route 15/s", function()
    local input = {grid = Grid.new(20, 7), catalog = {belt = {belt = "belt", items_per_second = 10, lane_items_per_second = 5}}, blocks = {}, flows = {
        {flow_id = "item/x", is_fluid = false, producers = {{step_id = "p", share_per_second = 15}}, consumers = {{step_id = "c", share_per_second = 15}}}}}
    for i = 1, 2 do
        input.blocks[#input.blocks + 1] = {block_id = "p" .. i, machines = {{step_id = "p"}}, x = 1, y = i * 3, w = 1, h = 1,
            ports = {{port_id = "po" .. i, role = "out", kind = "item", flow_id = "item/x", rate_per_second = 7.5, attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST}}}
        input.blocks[#input.blocks + 1] = {block_id = "c" .. i, machines = {{step_id = "c"}}, x = 15, y = i * 3, w = 1, h = 1,
            ports = {{port_id = "ci" .. i, role = "in", kind = "item", flow_id = "item/x", rate_per_second = 7.5, attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST}}}
    end
    local state = Route.begin(input)
    for _ = 1, 600 do if state.done then break end; Route.step(state, {ops = 100000}) end
    H.equal(state.done, true, "route completes")
    H.equal(state.ok, true, "four ports route 15/s over two belts")
end)
H.done("test_groups_belt_split")

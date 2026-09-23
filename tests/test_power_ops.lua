--Power candidate indexing cuts the placement sweep without changing its result.
local H = require "tests.harness"
local Power = require "logic.bp.power"

local function sheet_input()
    local consumers = {}
    --A compact 4 by 3 factory sheet: many consumers spread across a large
    --placement grid, with enough wire reach to join the selected poles.
    for row = 0, 2 do
        for column = 0, 3 do
            local n = #consumers + 1
            consumers[n] = {id = string.format("consumer-%02d", n),
            rect = {x = 6 + column * 24, y = 6 + row * 18, w = 2, h = 2}}
        end
    end
    return {grid_w = 150, grid_h = 90, consumers = consumers,
        pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
            supply_w = 5, supply_h = 5, wire_reach = 30},
        limits = {max_poles = 16}}
end

local function run(input, budget_size)
    local state, calls = Power.begin(input), 0
    while not state.done and calls < 2000000 do
        local budget = {ops = budget_size}
        Power.step(state, budget)
        calls = calls + 1
    end
    H.equal(state.done, true, "power search completes")
    H.equal(state.ok, true, "power search succeeds")
    return state
end

local function layout(result)
    local rows = {}
    for _, entity in ipairs(result.entities) do
        rows[#rows + 1] = table.concat({entity.name, entity.quality, entity.rect.x, entity.rect.y,
            entity.rect.w, entity.rect.h}, ":")
    end
    table.sort(rows)
    local wires = {}
    for _, wire in ipairs(result.wires) do
        wires[#wires + 1] = table.concat({wire.a_id, wire.a_connector, wire.b_id, wire.b_connector}, ":")
    end
    table.sort(wires)
    return table.concat(rows, "|"), table.concat(wires, "|")
end

--Re-frozen 2026-09-23 on legalcopilot-dev: 208630 ops with every supply-relevant position kept (base 413277).
--The lane's 8951 came from keeping one representative per coverage set, which dropped test_search to 28/54.
H.test("PO1 consumer-indexed sweep stays below 220000 ops", function()
    local state = run(sheet_input(), 2000)
    H.equal(state.result.pole_count <= 12, true, "consumer sheet is served by at most 12 poles")
    H.equal(#state.result.uncovered, 0, "all sheet consumers are covered")
    H.equal(state.result.components, 1, "sheet poles form one connected network")
    H.equal(state.ops_used < 220000, true, "indexed search uses " .. state.ops_used .. " ops; bound is 220000")
end)

H.test("PO2 one-op resumes and one-shot budgets produce identical poles and wires", function()
    local one = run(sheet_input(), 1)
    local all = run(sheet_input(), 1000000000)
    local one_poles, one_wires = layout(one.result)
    local all_poles, all_wires = layout(all.result)
    H.equal(one_poles, all_poles, "pole placements are budget independent")
    H.equal(one_wires, all_wires, "wire edges are budget independent")
end)

H.done("test_power_ops")

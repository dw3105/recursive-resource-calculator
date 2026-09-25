--Regression for the shared coverage miss: this test fails before the one-machine retry is implemented.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.1")

local f = assert(io.open("tests/fixtures/groups_ins10s_bulk.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a")))
f:close()
local state = Groups.begin({plan = fixture.plan, catalog = fixture.catalog})
while not state.done do Groups.step(state, {ops = 100}) end

local function signature(group)
    if group.signature then return group.signature end
    local beacon_name = group.name or group.beacon or group.type or "beacon"
    local pieces = {beacon_name, group.quality or "normal"}
    for _, module in ipairs(group.modules or {}) do
        pieces[#pieces + 1] = tostring(module.name) .. "@" .. tostring(module.quality or "normal") .. "x" .. tostring(module.count or 1)
    end
    local catalog_entry = fixture.catalog.entity and fixture.catalog.entity[beacon_name]
    local counter = catalog_entry and catalog_entry.beacon and catalog_entry.beacon.counter
    if counter then pieces[#pieces + 1] = tostring(counter) end
    return table.concat(pieces, "|")
end

H.test("frozen fast-hands groups input completes without failures", function()
    H.equal(state.ok, true, "grouping succeeds")
    H.equal(#(state.result and state.result.failures or {}), 0, "no group failures")
end)

H.test("every physical machine receives its configured beacon count by signature", function()
    local candidates = state.result and state.result.candidates or {}
    local seen = 0
    for _, candidate in ipairs(candidates) do
        for _, block in ipairs(candidate.blocks or {}) do
            for _, machine in ipairs(block.machines or {}) do
                seen = seen + 1
                local step
                for _, candidate_step in ipairs(fixture.plan.steps) do
                    if candidate_step.step_id == machine.step_id then step = candidate_step; break end
                end
                for _, requested in ipairs(step and step.beacon_groups or {}) do
                    local got = 0
                    for _, beacon_id in ipairs(block.beacon_coverage[machine.id] or {}) do
                        for _, beacon in ipairs(block.beacons or {}) do
                            if beacon.id == beacon_id and beacon.signature == signature(requested) then got = got + 1 end
                        end
                    end
                    H.equal(got >= requested.count_per_machine, true,
                        tostring(machine.step_id) .. " meets " .. signature(requested))
                end
            end
        end
    end
    local expected = 0
    for _, step in ipairs(fixture.plan.steps) do expected = expected + (step.machine_count or 1) end
    H.equal(seen, expected, "all physical machines are present")
end)

H.done("test_groups_coverage_split")

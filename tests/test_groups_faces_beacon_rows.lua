-- Regression: GF1-GF6 fail on round-44-base when beacon rows consume machine faces.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.1")
local f = assert(io.open("tests/fixtures/groups_gray_magenta.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a")))
f:close()
local state = Groups.begin({plan = fixture.plan, catalog = fixture.catalog})
while not state.done do Groups.step(state, {ops = 100}) end

local function signature(group)
    if group.signature then return group.signature end
    local name = group.name or group.beacon or group.type or "beacon"
    local parts = {name, group.quality or "normal"}
    for _, module in ipairs(group.modules or {}) do
        parts[#parts + 1] = tostring(module.name) .. "@" .. tostring(module.quality or "normal") .. "x" .. tostring(module.count or 1)
    end
    local entry = fixture.catalog.entity and fixture.catalog.entity[name]
    local counter = entry and entry.beacon and entry.beacon.counter
    if counter then parts[#parts + 1] = tostring(counter) end
    return table.concat(parts, "|")
end

local function has_step(block, name)
    for _, machine in ipairs(block.machines or {}) do if machine.step_id == name then return true end end
    return false
end

H.test("GF1 fixture groups without failures", function()
    H.equal(state.ok, true, "grouping succeeds")
    H.equal(#(state.result and state.result.failures or {}), 0, "no group failures")
end)
H.test("GF2 beacon rows do not cover hand faces", function()
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            for _, hand in ipairs(block.inserters or {}) do
                local machine
                for _, m in ipairs(block.machines or {}) do if m.id == hand.machine_id then machine = m; break end end
                if machine then for _, beacon in ipairs(block.beacons or {}) do
                    local spans = beacon.x < machine.x + machine.w and beacon.x + beacon.w > machine.x
                    H.equal(not (spans and beacon.y + beacon.h == machine.y and hand.y + hand.h == machine.y), true,
                        "hand stays off the covered top face")
                    H.equal(not (spans and beacon.y == machine.y + machine.h and hand.y == machine.y + machine.h), true,
                        "hand stays off the covered bottom face")
                end end
            end
        end
    end
end)
H.test("GF3 every physical machine receives configured beacons", function()
    local seen = 0
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do for _, machine in ipairs(block.machines or {}) do
            seen = seen + 1
            local step
            for _, s in ipairs(fixture.plan.steps) do if s.step_id == machine.step_id then step = s; break end end
            for _, requested in ipairs(step and step.beacon_groups or {}) do
                local got = 0
                for _, id in ipairs(block.beacon_coverage[machine.id] or {}) do
                    for _, beacon in ipairs(block.beacons or {}) do
                        if beacon.id == id and beacon.signature == signature(requested) then got = got + 1 end
                    end
                end
                H.equal(got >= requested.count_per_machine, true, machine.step_id .. " beacon count")
            end
        end end
    end
    local expected = 0
    for _, s in ipairs(fixture.plan.steps) do expected = expected + (s.machine_count or 1) end
    H.equal(seen, expected, "all physical machines represented")
end)
H.test("GF4 molten iron blocks are one machine each", function()
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do if has_step(block, "molten-iron") then
            H.equal(#block.machines, 1, "molten iron splits to one machine")
        end end
    end
end)
H.test("GF5 electric furnace has four hands with two on a long side", function()
    local found = false
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do if has_step(block, "electric-furnace") then
            found = true
            H.equal(#block.machines, 1, "one electric furnace machine")
            local machine, count, left, right = block.machines[1], 0, 0, 0
            for _, hand in ipairs(block.inserters or {}) do if hand.machine_id == machine.id and hand.port_id then
                count = count + 1
                if hand.x + hand.w == machine.x then left = left + 1 end
                if hand.x == machine.x + machine.w then right = right + 1 end
            end end
            H.equal(count, 4, "four port-bound hands")
            H.equal(left >= 2 or right >= 2, true, "two hands share a long side")
        end end
    end
    H.equal(found, true, "electric furnace block exists")
end)

H.test("GF6 strip output hand uses the free bottom face", function()
    local catalog = {entity = {
        assembler = {name = "assembler", tile_w = 3, tile_h = 3},
        inserter = {name = "inserter", tile_w = 1, tile_h = 1},
        beacon = {name = "beacon", tile_w = 3, tile_h = 3, beacon = {supply_w = 3, supply_h = 3}},
    }, beacon = {beacon = {supply_w = 3, supply_h = 3}}, inserter = {items_per_second = 15}}
    local plan = {steps = {{step_id = "strip", machine = "assembler", machine_count = 3,
        inputs = {{flow_id = "fluid/in", kind = "fluid", rate_per_second = 1}},
        outputs = {{flow_id = "item/out", rate_per_second = 1}},
        beacon_groups = {{signature = "b", name = "beacon", count_per_machine = 1, modules = {}}}}},
        flows = {{flow_id = "fluid/in", kind = "fluid"}, {flow_id = "item/out"}},
        ports = {{port_id = "out:item/out", role = "out", kind = "item", flow_id = "item/out", step_id = "strip", rate_per_second = 1}}}
    local s = Groups.begin({catalog = catalog, plan = plan})
    while not s.done do Groups.step(s, {ops = 100}) end
    H.equal(s.ok, true, "hand-built strip groups")
    local block = s.result and s.result.candidates and s.result.candidates[1] and s.result.candidates[1].blocks[1]
    H.equal(block ~= nil, true, "strip block exists")
    if block then
        H.equal(#block.machines, 3, "three machines stay in a strip")
        local below = false
        for _, hand in ipairs(block.inserters or {}) do
            if hand.role == "output" then
                for _, machine in ipairs(block.machines) do
                    if machine.id == hand.machine_id then
                        H.equal(hand.y == machine.y + machine.h, true, "output hand below its machine")
                        below = true
                    end
                end
            end
        end
        H.equal(below, true, "output hand exists")
    end
end)
print("GF1 GF2 GF3 GF4 GF5 GF6")
H.done("test_groups_faces_beacon_rows")

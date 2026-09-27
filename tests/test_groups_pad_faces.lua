-- PF1/PF3 regression: PF1 fails on round-45-base with BP_P_NO_FIT; PF3 pins unchanged foundry blocks.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local function replay(path)
    H.new_world("2.0")
    local f = assert(io.open(path, "r"))
    local fixture = assert(helpers.json_to_table(f:read("*a"))); f:close()
    local state = Groups.begin(fixture)
    while not state.done do Groups.step(state, {ops = 100}) end
    return state
end

local function canonical(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {"{"}
    for _, k in ipairs(keys) do out[#out + 1] = canonical(k) .. "=" .. canonical(value[k]) .. ";" end
    out[#out + 1] = "}"
    return table.concat(out)
end

local function hash(text)
    local h = 2166136261
    for i = 1, #text do h = (h * 16777619 + text:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

H.test("PF1 lone beaconed plant retries with free top face columns", function()
    local state = replay("tests/fixtures/groups_ins_stack1.json")
    H.equal(state.ok, true, "fixture generates groups")
    H.equal(#state.result.failures, 0, "no failures")
    local found
    for _, candidate in ipairs(state.result.candidates) do
        for _, block in ipairs(candidate.blocks or {}) do
            for _, machine in ipairs(block.machines or {}) do
                if machine.step_id == "item/electronic-circuit" or machine.step_id == "electronic-circuit" then found = block end
            end
        end
    end
    H.equal(found ~= nil, true, "electronic circuit block found")
    if found then
        H.equal(#found.inserters, 15, "15 hands allocated")
        for _, hand in ipairs(found.inserters) do
            for _, beacon in ipairs(found.beacons or {}) do
                local on_tile = hand.x >= beacon.x and hand.x < beacon.x + beacon.w and hand.y >= beacon.y and hand.y < beacon.y + beacon.h
                H.equal(on_tile, false, "hand avoids beacon tile")
            end
        end
        for _, port in ipairs(found.ports or {}) do
            if port.inserter_id then
                for _, beacon in ipairs(found.beacons or {}) do
                    local x, y = port.attach_dx, port.attach_dy
                    local on_tile = x and y and x >= beacon.x and x < beacon.x + beacon.w
                        and y >= beacon.y and y < beacon.y + beacon.h
                    H.equal(on_tile, false, "hand port avoids beacon tile")
                end
            end
        end
        for _, machine in ipairs(found.machines or {}) do
            H.equal(#(found.beacon_coverage[machine.id] or {} ) > 0, true,
                "machine retains beacon coverage: " .. tostring(machine.id))
        end
    end
end)

H.test("PF3 foundry blocks match base hash", function()
    local state = replay("tests/fixtures/groups_red1s_foundry.json")
    local blocks = {}
    for _, candidate in ipairs(state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do blocks[#blocks + 1] = block end
    end
    table.sort(blocks, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local serial = canonical(blocks)
    --51c1eead since lane 254 (every block carries an empty `belt_runs`); blueprint bytes of this sheet unchanged
    --(ec415235..., tests/fixtures/bytes_round43.txt), measured 2026-09-27 on legalcopilot-dev.
    H.equal(hash(serial), "51c1eead", "all blocks match round-45-w2")
end)

H.done("test_groups_pad_faces")

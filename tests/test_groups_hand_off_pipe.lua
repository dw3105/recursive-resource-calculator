-- HP1/HP2 regression: HP1 fails on round-45-w2 because a casting-copper-cable hand
-- occupies its molten-copper pipe tile; HP2 pins unaffected foundry blocks.
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

local function hash(value)
    local h = 2166136261
    for i = 1, #value do h = (h * 16777619 + value:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

H.test("HP1 machine hands leave every fluid pipe tile clear", function()
    local state = replay("tests/fixtures/groups_ins_stack1.json")
    H.equal(state.ok, true, "fixture generates groups")
    local casting_found = false
    for _, candidate in ipairs(state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            if block.id == "block:casting-copper-cable" then
                casting_found = true
                local hands = 0
                for _, hand in ipairs(block.inserters or {}) do
                    if hand.role == "output" then hands = hands + 1 end
                end
                H.equal(hands, 7, "casting copper cable retains seven output hands")
            end
            for _, hand in ipairs(block.inserters or {}) do
                for _, port in ipairs(block.ports or {}) do
                    if port.kind == "fluid" then
                        H.equal(hand.x == port.attach_dx and hand.y == port.attach_dy, false,
                            "hand avoids fluid pipe tile in " .. tostring(block.id))
                    end
                end
            end
        end
    end
    H.equal(casting_found, true, "casting copper cable block found")
end)

H.test("HP2 unaffected foundry block hash matches round-45-w2", function()
    local state = replay("tests/fixtures/groups_red1s_foundry.json")
    local blocks = {}
    for _, candidate in ipairs(state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do blocks[#blocks + 1] = block end
    end
    table.sort(blocks, function(a, b) return tostring(a.id) < tostring(b.id) end)
    H.equal(hash(canonical(blocks)), "51c1eead", "all blocks match round-45-w2")
end)

print("HP1 HP2")
H.done("test_groups_hand_off_pipe")

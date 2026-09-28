-- PH1 fails on round-45-w3: an item port can point along its face into another flow's hand tile.
-- PH2 pins the foundry fixture's sorted block|port|travel rows from round-45-w3.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

local function replay(path)
    H.new_world("2.0")
    local f = assert(io.open(path, "r"))
    local fixture = assert(helpers.json_to_table(f:read("*a"))); f:close()
    local state = Groups.begin(fixture)
    while not state.done do Groups.step(state, {ops = 100}) end
    return state
end

local function all_blocks(state)
    local blocks = {}
    for _, candidate in ipairs(state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do blocks[#blocks + 1] = block end
    end
    return blocks
end

local function flows(port)
    local result = {}
    if port.flow_id ~= nil then result[tostring(port.flow_id)] = true end
    for _, id in ipairs(port.flow_ids or {}) do result[tostring(id)] = true end
    return result
end

local function different_flow(a, b)
    local af, bf = flows(a), flows(b)
    for id in pairs(af) do if bf[id] then return false end end
    return true
end

local function hash(text)
    local h = 2166136261
    for i = 1, #text do h = (h * 16777619 + text:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

H.test("PH1 item hand headings clear other flow hand tiles", function()
    local blocks = all_blocks(replay("tests/fixtures/groups_ins_stack1.json"))
    local circuit
    for _, block in ipairs(blocks) do
        for _, port in ipairs(block.ports or {}) do
            if port.port_id == "out:item/electronic-circuit:hand:5:inserter:electronic-circuit:1:output:15" then
                circuit = port
            end
        end
    end
    H.equal(circuit ~= nil, true, "circuit hand 5 port found")
    if circuit then H.equal(circuit.travel_dir, 0, "circuit hand 5 points away from machine") end

    for _, block in ipairs(blocks) do
        local at = {}
        for _, port in ipairs(block.ports or {}) do
            if port.attach_dx ~= nil and port.attach_dy ~= nil then
                local key = port.attach_dx .. ":" .. port.attach_dy
                at[key] = at[key] or {}
                at[key][#at[key] + 1] = port
            end
        end
        for _, port in ipairs(block.ports or {}) do
            if port.kind ~= "fluid" and port.travel_dir ~= nil and port.attach_dx ~= nil and port.attach_dy ~= nil then
                local dx, dy = Grid.dir_vector(port.travel_dir)
                local sign = port.role == "out" and 1 or -1
                local key = (port.attach_dx + sign * dx) .. ":" .. (port.attach_dy + sign * dy)
                for _, other in ipairs(at[key] or {}) do
                    if different_flow(port, other) then
                        H.equal(false, true, "item port " .. tostring(port.port_id) .. " enters another flow port")
                    end
                end
            end
        end
    end
end)
print("PH1")

H.test("PH2 foundry headings match round-45-w3", function()
    local rows = {}
    for _, block in ipairs(all_blocks(replay("tests/fixtures/groups_red1s_foundry.json"))) do
        for _, port in ipairs(block.ports or {}) do
            rows[#rows + 1] = table.concat({tostring(block.id), tostring(port.port_id), tostring(port.travel_dir)}, "|")
        end
    end
    table.sort(rows)
    H.equal(hash(table.concat(rows, "\n")), "edf37ab0", "sorted block|port|travel hash")
end)
print("PH2")

H.done("test_groups_port_heading")

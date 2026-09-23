--The red-science sheet has eleven machines and twenty-six ordinary item hands.  The player's blueprint uses
--one input hand for copper plate and iron gear on each of its four science assemblers, so the paired shape is
--the twenty-two-hand characterization for contract 28.1/28.3.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"

local SCIENCE_BELT_TILE = {x = 210.5, y = 1076.5}

local function catalog()
    return {
        entity = {
            ["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine",
                tile_w = 3, tile_h = 3},
            ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine",
                tile_w = 3, tile_h = 3},
            ["electric-furnace"] = {name = "electric-furnace", etype = "furnace", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5},
    }
end

local function item(flow_id, rate, belt_tile)
    local result = {flow_id = flow_id, kind = "item", rate_per_second = rate}
    if belt_tile then result.belt_tile = belt_tile end
    return result
end

local function sheet_plan()
    return {
        steps = {
            {step_id = "science", machine = "assembling-machine-3", machine_count = 4,
                inputs = {item("item/iron-gear-wheel", 1, SCIENCE_BELT_TILE),
                    item("item/copper-plate", 1, SCIENCE_BELT_TILE)},
                outputs = {item("item/automation-science-pack", 1)}},
            {step_id = "copper", machine = "electric-furnace", machine_count = 2,
                inputs = {item("item/copper-ore", 1)}, outputs = {item("item/copper-plate", 1)}},
            {step_id = "iron", machine = "electric-furnace", machine_count = 4,
                inputs = {item("item/iron-ore", 2)}, outputs = {item("item/iron-plate", 2)}},
            {step_id = "gear", machine = "assembling-machine-2", machine_count = 1,
                inputs = {item("item/iron-plate", 2)}, outputs = {item("item/iron-gear-wheel", 1)}},
        },
        flows = {},
    }
end

local function finish(force)
    local state = Groups.begin({plan = sheet_plan(), catalog = catalog(), _force_multi_flow_hands = force})
    for _ = 1, 1000 do
        if state.done then break end
        Groups.step(state, {ops = 100})
    end
    H.equal(state.done, true, "the red-science shape finishes grouping")
    H.equal(state.result ~= nil and #state.result.candidates > 0, true,
        "the red-science shape has a grouping candidate")
    --Round 26 puts row candidates first (docs/contracts/row_block.md; tests/test_rows_integration.lua RI4).
    --This file characterizes the pre-row shapes, which still follow them: the first candidate without a row.
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        local has_row = false
        for _, block in ipairs(candidate.blocks or {}) do if block.row then has_row = true end end
        if not has_row then return candidate end
    end
    return nil
end

local function all_members(candidate, kind)
    local result = {}
    for _, block in ipairs(candidate and candidate.blocks or {}) do
        for _, member in ipairs(block.members or {}) do
            if member.kind == kind then result[#result + 1] = {block = block, member = member} end
        end
    end
    return result
end

local function flow_ids(hand)
    if type(hand.flow_ids) == "table" then return hand.flow_ids end
    return hand.flow_id and {hand.flow_id} or {}
end

local function has_flow(hand, wanted)
    for _, flow_id in ipairs(flow_ids(hand)) do if flow_id == wanted then return true end end
    return false
end

local function on_perimeter(block, x, y)
    return (x == -1 or x == block.w) and y >= 0 and y < block.h
        or (y == -1 or y == block.h) and x >= 0 and x < block.w
end

local function outward_cell(hand)
    local position = hand.role == "input" and hand.pickup_position or hand.drop_position
    return math.floor(position.x + 1e-9), math.floor(position.y + 1e-9)
end

local function counts(candidate)
    local machines, hands = 0, 0
    for _, block in ipairs(candidate.blocks or {}) do
        machines = machines + #(block.machines or {})
        for _, hand in ipairs(block.inserters or {}) do if hand.port_bound then hands = hands + 1 end end
    end
    return machines, hands
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " HE1 switch off preserves the measured eleven-machine, twenty-six-hand baseline", function()
        local candidate = finish(false)
        local machines, hands = counts(candidate)
        H.equal(machines, 11, "default grouping keeps all eleven machines")
        H.equal(hands, 26, "default grouping keeps one hand per item port")
        for _, entry in ipairs(all_members(candidate, "inserter")) do
            local x, y = outward_cell(entry.member)
            H.equal(on_perimeter(entry.block, x, y), true, "default hand remains on the block perimeter")
        end
    end)

    H.test(shape .. " HE2 paired mode gives every science machine one two-flow input hand", function()
        local candidate = finish(true)
        local machines, hands = counts(candidate)
        H.equal(machines, 11, "paired grouping keeps all eleven machines")
        H.equal(hands, 22, "paired grouping matches the player's twenty-two hands")

        local science = {}
        for _, entry in ipairs(all_members(candidate, "inserter")) do
            local hand, block = entry.member, entry.block
            local x, y = outward_cell(hand)
            H.equal(on_perimeter(block, x, y), true, "every paired-mode hand stays on the block perimeter")
            if hand.step_id == "science" and hand.role == "input" then
                science[hand.machine_id] = science[hand.machine_id] or {}
                science[hand.machine_id][#science[hand.machine_id] + 1] = hand
            end
        end
        H.equal((function() local n = 0 for _ in pairs(science) do n = n + 1 end return n end)(), 4,
            "all four science machines have an input hand")
        for machine_id, hands_for_machine in pairs(science) do
            H.equal(#hands_for_machine, 1, machine_id .. " has one science input hand")
            local hand = hands_for_machine[1]
            H.equal(has_flow(hand, "item/copper-plate"), true, "science hand carries copper plate")
            H.equal(has_flow(hand, "item/iron-gear-wheel"), true, "science hand carries iron gear wheel")
            H.near(hand.flow_shares["item/copper-plate"], 0.25, "copper keeps its per-machine share")
            H.near(hand.flow_shares["item/iron-gear-wheel"], 0.25, "gear keeps its per-machine share")
            H.near(hand.rate_per_second, 0.5, "shared hand moves the sum of its two shares")
        end
    end)

    H.test(shape .. " HE3 one paired hand has one anchored port advertising both flows", function()
        local candidate = finish(true)
        for _, block in ipairs(candidate.blocks or {}) do
            local ports_by_hand = {}
            for _, port in ipairs(block.ports or {}) do
                if port.inserter_id then
                    ports_by_hand[port.inserter_id] = (ports_by_hand[port.inserter_id] or 0) + 1
                    if type(port.flow_ids) == "table" then
                        H.equal(#port.flow_ids, 2, "the paired port advertises both item flows")
                        H.equal(port.flow_id, nil, "the paired port has no scalar flow identity")
                        H.near(port.flow_shares["item/copper-plate"], 0.25,
                            "the paired port preserves copper's share")
                        H.near(port.flow_shares["item/iron-gear-wheel"], 0.25,
                            "the paired port preserves gear's share")
                    end
                end
            end
            for _, hand in ipairs(block.inserters or {}) do
                if hand.port_bound then
                    H.equal(ports_by_hand[hand.id], 1, "every hand publishes exactly one block port")
                end
            end
        end
    end)
end

H.done("test_hand_economy")

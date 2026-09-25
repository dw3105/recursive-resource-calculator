-- Regression: the no-fit assertion fails on round-36-int4, which reports inserter-reach instead of inserter-face.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

H.test("one flow spreads its hands across free machine faces", function()
    local catalog = {
        entity = {
            assembler = {name = "assembler", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", items_per_second = 2.31},
    }
    local plan = {
        steps = {{step_id = "s", machine = "assembler", machine_count = 1,
            outputs = {{flow_id = "item/flow", rate_per_second = 15}}}},
        flows = {{flow_id = "item/flow", producers = {{step_id = "s", share_per_second = 15}},
            consumers = {{step_id = "$external", share_per_second = 15}}}},
        ports = {{port_id = "out:item/flow", role = "out", kind = "item", flow_id = "item/flow",
            step_id = "s", rate_per_second = 15}},
    }
    local state = Groups.begin({catalog = catalog, plan = plan})
    for _ = 1, 100 do
        if state.done then break end
        Groups.step(state, {ops = 10})
    end
    H.equal(state.done, true, "group search completes")
    H.equal(#state.result.candidates > 0, true, "overflow fits on other free faces")
    local block = state.result.candidates[1].blocks[1]
    local machine = block.machines[1]
    local faces, count = {}, 0
    for _, hand in ipairs(block.inserters) do
        count = count + 1
        local on_machine = hand.x < machine.x + machine.w and hand.x + hand.w > machine.x
            and hand.y < machine.y + machine.h and hand.y + hand.h > machine.y
        H.equal(on_machine, false, "hand footprint stays outside machine tiles")
        if hand.y + hand.h == machine.y then faces.top = true
        elseif hand.y == machine.y + machine.h then faces.bottom = true
        elseif hand.x + hand.w == machine.x then faces.left = true
        elseif hand.x == machine.x + machine.w then faces.right = true end
    end
    H.equal(count, 7, "15 per second at 2.31 per hand needs seven hands")
    local face_count = 0
    for _ in pairs(faces) do face_count = face_count + 1 end
    H.equal(face_count > 1, true, "hands use more than one face")
    for _, port in ipairs(block.ports) do
        if port.inserter_id then
            local x, y = port.attach_dx, port.attach_dy
            local outside = x < machine.x or x >= machine.x + machine.w
                or y < machine.y or y >= machine.y + machine.h
            H.equal(outside, true, "port attachment stays outside machine tiles")
        end
    end
end)

H.test("a flow larger than every available face fails by name", function()
    local catalog = {
        entity = {
            assembler = {name = "assembler", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", items_per_second = 2.31},
    }
    local rate = 13 * 2.31
    local plan = {
        steps = {{step_id = "s", machine = "assembler", machine_count = 1,
            outputs = {{flow_id = "item/flow", rate_per_second = rate}}}},
        flows = {{flow_id = "item/flow", producers = {{step_id = "s", share_per_second = rate}},
            consumers = {{step_id = "$external", share_per_second = rate}}}},
        ports = {{port_id = "out:item/flow", role = "out", kind = "item", flow_id = "item/flow",
            step_id = "s", rate_per_second = rate}},
    }
    local state = Groups.begin({catalog = catalog, plan = plan})
    for _ = 1, 100 do
        if state.done then break end
        Groups.step(state, {ops = 10})
    end
    H.equal(#state.result.candidates, 0, "thirteen hands exceed all twelve machine face slots")
    H.equal(state.result.failures[1].name, "inserter-face", "no-fit failure names the machine face")
end)
H.done("test_groups_hands_overflow")

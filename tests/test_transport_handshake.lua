--A grouped item transfer has one physical hand and one physical port.  The port is the
--belt tile immediately beyond that hand, not a separately chosen perimeter convention.
local H = require "tests.harness"

local Groups = require "logic.bp.groups"

local function catalog()
    return {
        entity = {
            ["assembling-machine-3"] = {name = "assembling-machine-3", etype = "assembling-machine",
                tile_w = 3, tile_h = 3},
            ["electric-furnace"] = {name = "electric-furnace", etype = "furnace", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}},
    }
end

local function external(flow_id)
    return {flow_id = flow_id, kind = "item", rate_per_second = 1}
end

--This is the small sheet shape that exposed the anchor split: four science assemblers and
--two copper furnaces, with three item obligations on each machine.
local function sheet_plan()
    return {
        steps = {
            {step_id = "science", machine = "assembling-machine-3", machine_count = 4,
                inputs = {external("item/iron-gear-wheel", "input"), external("item/iron-plate", "input")},
                outputs = {external("item/automation-science-pack", "output")}},
            {step_id = "copper", machine = "electric-furnace", machine_count = 2,
                inputs = {external("item/copper-ore", "input")},
                outputs = {external("item/copper-plate", "output"), external("item/stone", "output")}},
        },
        flows = {},
    }
end

local function finish()
    local state = Groups.begin({plan = sheet_plan(), catalog = catalog()})
    for _ = 1, 5000 do
        if state.done then break end
        Groups.step(state, {ops = 100})
    end
    H.equal(state.done, true, "grouping finishes for the sheet shape")
    return state
end

local function each_block(fn)
    local state = finish()
    local candidates = state.result and state.result.candidates or {}
    H.equal(#candidates > 0, true, "the sheet shape has grouping candidates")
    for _, candidate in ipairs(candidates) do
        for _, block in ipairs(candidate.blocks or {}) do fn(block) end
    end
end

local function cell(value)
    return math.floor(value + 1e-9)
end

local function outward_cell(inserter)
    local position = inserter.role == "input" and inserter.pickup_position or inserter.drop_position
    return cell(position.x), cell(position.y)
end

local function on_perimeter(block, x, y)
    return (x == -1 or x == block.w) and y >= 0 and y < block.h
        or (y == -1 or y == block.h) and x >= 0 and x < block.w
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " TH1 every external hand outward cell is on the block perimeter", function()
        each_block(function(block)
            for _, inserter in ipairs(block.inserters or {}) do
                local outward_x, outward_y = outward_cell(inserter)
                local external = (inserter.role == "input" and tostring(inserter.pickup_target):sub(1, 5) == "port:")
                    or (inserter.role == "output" and tostring(inserter.drop_target):sub(1, 5) == "port:")
                if external then
                    H.equal(on_perimeter(block, outward_x, outward_y), true,
                        "external hand outward cell is on the block perimeter")
                end
            end
        end)
    end)

    H.test(shape .. " TH2 every external hand has exactly one port carrying its id", function()
        each_block(function(block)
            local ports_by_inserter = {}
            for _, port in ipairs(block.ports or {}) do
                if port.inserter_id ~= nil then
                    ports_by_inserter[port.inserter_id] = (ports_by_inserter[port.inserter_id] or 0) + 1
                end
            end
            for _, inserter in ipairs(block.inserters or {}) do
                local external = (inserter.role == "input" and tostring(inserter.pickup_target):sub(1, 5) == "port:")
                    or (inserter.role == "output" and tostring(inserter.drop_target):sub(1, 5) == "port:")
                if external then H.equal(ports_by_inserter[inserter.id], 1, "external hand has one anchored port") end
            end
        end)
    end)

    H.test(shape .. " TH3 every block port id is distinct", function()
        each_block(function(block)
            local seen_ports = {}
            for _, port in ipairs(block.ports or {}) do
                H.equal(seen_ports[port.port_id], nil, "port ids are distinct")
                seen_ports[port.port_id] = true
            end
        end)
    end)
end

H.done("test_transport_handshake")

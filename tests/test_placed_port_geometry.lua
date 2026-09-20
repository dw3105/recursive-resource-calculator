--The placed frame: a rotated block's port, its approach tile, and what the independent checker may demand.
--Every case here failed on the player's own chain before it was fixed, and each one rejected a layout the game
--would have accepted.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local function finish(input)
    local state = Validate.begin(input)
    for _ = 1, 20000 do
        if state.done then break end
        Validate.step(state, {ops = 100})
    end
    H.equal(state.done, true, "placed port fixture terminates")
    return state
end

local function reported(state, code, id)
    for _, record in ipairs((state.result and state.result.errors) or state.errors or {}) do
        if record.code == code then
            if id == nil then return true end
            for _, value in ipairs(record.ids or {}) do if value == id then return true end end
        end
    end
    return false
end

local function codes(state)
    local result = {}
    for _, record in ipairs((state.result and state.result.errors) or state.errors or {}) do
        result[#result + 1] = tostring(record.code) .. "/"
            .. tostring(type(record.detail) == "table" and record.detail.reason or record.detail)
    end
    table.sort(result)
    return result
end

local function catalog()
    return {schema_version = 1, entity = {
        ["assembler"] = {etype = "assembling-machine", name = "assembler", needs_power = true,
            tile_w = 3, tile_h = 3},
        ["transport-belt"] = {etype = "transport-belt", name = "transport-belt", needs_power = false,
            tile_w = 1, tile_h = 1},
        ["medium-electric-pole"] = {etype = "electric-pole", name = "medium-electric-pole", needs_power = false,
            tile_w = 1, tile_h = 1},
    }, pole = {supply_w = 3.5, supply_h = 3.5, wire_reach = 9, tile_w = 1, tile_h = 1,
        name = "medium-electric-pole", quality = "normal"}, quality = "normal"}
end

--A 3x1 block placed east: its port sits on the placed east edge and its approach follows the rotated travel
--direction, never the direction written in the block's own frame.
local function rotated_block_candidate()
    local port = {port_id = "out:item/gear", role = "out", flow_id = "item/gear", kind = "item",
        attach_dx = 0, attach_dy = -1, normal_dir = 8, travel_dir = 0, rate_per_second = 1,
        _block_w = 1, _block_h = 3}
    return {
        grid_w = 12, grid_h = 12, grid = {w = 12, h = 12},
        blocks = {{block_id = "block:gear", id = "block:gear", x = 2, y = 2, w = 3, h = 1, dir = 4,
            ports = {port}}},
        placements = {{block_id = "block:gear", x = 2, y = 2, dir = 4}},
        external_ports = {{port_id = "in:item/gear", id = "in:item/gear", role = "out", flow_id = "item/gear",
            perimeter = true, x = 11, y = 5, travel_dir = 4, rate_per_second = 1}},
        entities = {
            --A belt of another flow on the tile the unrotated approach would have used.
            {id = "r:1", name = "transport-belt", x = 5, y = 1, w = 1, h = 1, flow_id = "item/plate", dir = 4},
        },
        segments = {}, bindings = {{source_port_id = "out:item/gear", sink_port_id = "in:item/gear",
            flow_id = "item/gear", rate_per_second = 1}},
        flows = {}, plan = {steps = {}, flows = {}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PG1 a rotated block's approach tile follows the placed direction", function()
        local state = finish({candidate = rotated_block_candidate(), plan = {steps = {}, flows = {}},
            catalog = catalog()})
        H.equal(reported(state, "BP_V_PORT_EDGE_WRONG"), false,
            "a belt beside the unrotated approach is no wrong port edge; saw "
                .. table.concat(codes(state), " "))
    end)

    H.test(shape .. " PG2 a binding names its port by port_id", function()
        local candidate = rotated_block_candidate()
        --The port carries a step id as well. Indexing ports by anything but port_id loses the binding.
        candidate.blocks[1].ports[1].step_id = "gear"
        candidate.blocks[1].ports[1].member_id = "m:machine:gear:1"

        local state = finish({candidate = candidate, plan = {steps = {}, flows = {}}, catalog = catalog()})
        H.equal(reported(state, "BP_V_PORT_EDGE_WRONG"), false,
            "the binding resolves both of its ports; saw " .. table.concat(codes(state), " "))
    end)

    H.test(shape .. " PG3 an edge input is reachable when a binding uses it as a source", function()
        local candidate = rotated_block_candidate()
        candidate.external_ports[#candidate.external_ports + 1] = {port_id = "in:item/plate",
            id = "in:item/plate", role = "in", flow_id = "item/plate", perimeter = true, x = 0, y = 5,
            travel_dir = 4, rate_per_second = 4}
        candidate.external_ports[#candidate.external_ports + 1] = {port_id = "in:item/plate:block",
            id = "in:item/plate:block", role = "in", flow_id = "item/plate", block_id = "block:gear",
            x = 3, y = 6, travel_dir = 4, rate_per_second = 4}
        candidate.bindings[#candidate.bindings + 1] = {source_port_id = "in:item/plate",
            sink_port_id = "in:item/plate:block", flow_id = "item/plate", rate_per_second = 4}
        local state = finish({candidate = candidate, plan = {steps = {}, flows = {}}, catalog = catalog()})
        H.equal(reported(state, "BP_V_PORT_UNREACHABLE", "in:item/plate"), false,
            "an edge input supplies the layout and is never asked for an upstream producer; saw "
                .. table.concat(codes(state), " "))
    end)

    H.test(shape .. " PG4 a machine beside a pole is powered when its box overlaps the supply area", function()
        local candidate = {
            grid_w = 20, grid_h = 20, grid = {w = 20, h = 20},
            blocks = {}, placements = {}, external_ports = {}, segments = {}, bindings = {}, flows = {},
            plan = {steps = {}, flows = {}},
            entities = {
                --Machine centre is 4.5 tiles from the pole centre, outside a 3.5 supply half-width; its box
                --reaches to 3 tiles away, so the game powers it.
                {id = "m:1", name = "assembler", x = 5, y = 0, w = 3, h = 3, step_id = "gear"},
                {id = "p:1", name = "medium-electric-pole", x = 1, y = 1, w = 1, h = 1},
            },
        }
        local state = finish({candidate = candidate, plan = {steps = {}, flows = {}}, catalog = catalog()})
        H.equal(reported(state, "BP_V_POWER_UNCOVERED", "m:1"), false,
            "an overlapping machine is covered; saw " .. table.concat(codes(state), " "))
    end)
end

H.done("test_placed_port_geometry")

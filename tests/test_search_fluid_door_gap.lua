--These checks fail on the base code because it assigns adjacent perimeter slots to distinct fluid flows.
local H = require "tests.harness"
local Search = require "logic.bp.search"

local function input_for(kind_a, kind_b)
    local function port(id, kind)
        return {port_id = "in:" .. id, role = "in", kind = kind, flow_id = kind .. "/" .. id, rate_per_second = 0}
    end
    return {
        plan = {steps = {{step_id = "one", machine = "machine/a", machine_count = 1, power_w = 1,
            modules = {}, beacon_groups = {}, inputs = {}, outputs = {}}}, flows = {},
            ports = {port("a", kind_a), port("b", kind_b)}},
        catalog = {entity = { ["machine/a"] = {name = "machine/a", tile_w = 1, tile_h = 1,
            energy_usage_w = 1, collision_box = {{-0.4, -0.4}, {0.4, 0.4}}, collision_mask = {"item-layer"}}}},
        pole = {name = "pole/a", tile_w = 1, tile_h = 1, supply_w = 10, supply_h = 10, wire_reach = 20},
        include_roboports = false, grids = {{w = 8, h = 8}}, settings = {input_edge = "left", output_edge = "top"},
    }
end

local function generated(kind_a, kind_b)
    local state = Search.begin(input_for(kind_a, kind_b))
    for _ = 1, 300 do
        if state.work.perimeter_ports and #state.work.perimeter_ports == 2 then return state.work.perimeter_ports end
        if state.done then break end
        Search.step(state, {ops = 1000})
    end
    return state.work.perimeter_ports or {}
end

local function gap(ports)
    local a, b = ports[1], ports[2]
    return a and b and math.abs(a.y - b.y)
end

H.test("DG1 different fluid flows entering one edge leave a slot between doors", function()
    local ports = generated("fluid", "fluid")
    H.equal(#ports, 2, "both fluid doors are assigned")
    H.equal(gap(ports) >= 2, true, "fluid doors have at least one free slot between them")
end)

H.test("DG2 item flows may still take neighboring slots", function()
    local ports = generated("item", "item")
    H.equal(#ports, 2, "both item doors are assigned")
    H.equal(gap(ports), 1, "item doors may be neighbors")
end)

H.test("DG3 a fluid door and an item door may be neighbors", function()
    local ports = generated("fluid", "item")
    H.equal(#ports, 2, "both doors are assigned")
    H.equal(gap(ports), 1, "mixed doors may be neighbors")
end)

H.done("test_search_fluid_door_gap")

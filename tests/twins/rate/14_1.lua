--Round 48 physical twin: one transport-belt row from a source on the west edge to consumer s on the east edge. The source makes 3 items/s but s is planned to consume 6/s: the sink sees 3 < 0.95 x 6.
--Pair: 14_1 (breach) / 14_2 (clean).
local entities = {}
for x = 0, 9 do
    entities[#entities + 1] = {id = "b" .. x, kind = "belt", name = "transport-belt", x = x, y = 0, dir = "east", flows = {"iron-plate"}}
end
local validator = {
    flows = {{flow_id = "item/iron-plate", producers = {{step_id = "src", share_per_second = 3}}, consumers = {{step_id = "s", share_per_second = 6}}}},
    segments = {{segment_id = "belt", kind = "belt", flow_id = "item/iron-plate", capacity_per_second = 15,
        allocations = {{flow_id = "item/iron-plate", sink = "step:s", rate_per_second = 6}}}},
    catalog = {entity = {["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {id = "T-280-V141", rule = "BP_V_FLOW_IMBALANCE", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 10, h = 1}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect",
    codes = {"BP_V_FLOW_IMBALANCE"},
    feeds = {{tile = {0, 0}, item = "iron-plate", rate = 3}}, sinks = {{tile = {9, 0}, items = {"iron-plate"}, rate = 6}},
    audit = {}}

--Round 48 physical twin: one transport-belt row from the west edge to a sink on the east edge, planned 20 items/s.
--A transport-belt carries 15 items/s (7.5 per lane): the feed saturates and the sink sees at most 15/s < 0.95 x 20.
--Pair: 11_1 (breach) / 11_2 (clean).
local entities = {}
for x = 0, 9 do
    entities[#entities + 1] = {id = "b" .. x, kind = "belt", name = "transport-belt", x = x, y = 0, dir = "east", flows = {"iron-plate"}}
end
local validator = {
    segments = {{segment_id = "s", kind = "belt", capacity_per_second = 15, allocations = {{flow_id = "item/iron-plate", rate_per_second = 20}}}},
    flows = {{flow_id = "item/iron-plate"}},
    catalog = {entity = {["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false}},
        belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {id = "T-280-V111", rule = "BP_V_TRANSFER_CAPACITY", class = "engine", from = "tests/test_validate.lua twin candidate",
    grid = {w = 10, h = 1}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect",
    codes = {"BP_V_TRANSFER_CAPACITY"},
    feeds = {{tile = {0, 0}, item = "iron-plate", rate = 20}}, sinks = {{tile = {9, 0}, items = {"iron-plate"}, rate = 20}},
    audit = {}}

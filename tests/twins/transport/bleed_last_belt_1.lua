--Seed twin (round 48 S0): last belt of flow A points into flow B. Player, green v2, 2026-09-24 ("belt bleeding").
--Flow A runs down x=5 from the top edge and ends at (5,2); flow B runs east along y=3 from the left edge.
local belts = {}
local function belt(id, x, y, dir, item) belts[#belts + 1] = {id = id, kind = "belt", name = "transport-belt", x = x, y = y, dir = dir, flows = {item}} end
belt("a0", 5, 0, "south", "iron-plate")
belt("a1", 5, 1, "south", "iron-plate")
belt("a2", 5, 2, "south", "iron-plate")
for x = 0, 8 do belt("b" .. x, x, 3, "east", "copper-plate") end
return {
    id = "T-BLEED-1", rule = "BP_V_BELT_BLEED", class = "engine", from = "tests/test_validate_bleed.lua VB1",
    grid = {w = 20, h = 20},
    entities = belts,
    feeds = {{tile = {5, 0}, item = "iron-plate"}, {tile = {0, 3}, item = "copper-plate"}},
    sinks = {{tile = {8, 3}, items = {"copper-plate"}}},
    check = "flow_purity",
    truth = "defect",
    codes = {"BP_V_BELT_BLEED"},
    --no audit keys: lane_sim bleed counts only at machine pickups (tools/lane_sim.py:13), blueprint_audit
    --sideload only at underground inlets; a twin with no machine is outside both auditors.
    audit = {},
}

--Round 48 integration: blueprint_audit redundant_beacons needs --beacon-config. One assembler, two beacons in
--reach; configured count 1 -> 1 redundant. Pair: audit_redundant_1 (breach) / audit_redundant_2 (clean).
local entities = {
    {id = "m", kind = "machine", name = "assembling-machine-2", x = 5, y = 5, w = 3, h = 3, recipe = "iron-gear-wheel", step_id = "s"},
    {id = "b1", kind = "beacon", name = "beacon", x = 5, y = 1, w = 3, h = 3, signature = "sb", required_for = {"m"}},
    {id = "b2", kind = "beacon", name = "beacon", x = 5, y = 9, w = 3, h = 3, signature = "sb", required_for = {"m"}},
    {id = "p", kind = "pole", name = "substation", x = 1, y = 6, w = 2, h = 2},
}
local validator = {
    plan = {steps = {{step_id = "s", machine = "assembling-machine-2", machine_count = 1,
        beacon_groups = {{signature = "sb", name = "beacon", count_per_machine = 1}}}}},
    catalog = {entity = {
        ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = true},
        beacon = {name = "beacon", etype = "beacon", tile_w = 3, tile_h = 3, needs_power = true, beacon = {supply_w = 3, supply_h = 3, distribution_effectivity = 1.5}},
        substation = {name = "substation", etype = "electric-pole", tile_w = 2, tile_h = 2, supply_w = 9, supply_h = 9, wire_reach = 18},
    }, belt = {items_per_second = 15, lane_items_per_second = 7.5}},
}
return {
    id = "T-AUDIT-RB-1", rule = "audit:blueprint_audit:redundant_beacons", class = "waste",
    from = "round 48 integration (tools/blueprint_audit.py audit_beacons)",
    grid = {w = 20, h = 20}, entities = entities, validator = validator, stage = "validate", check = "beacon_effect",
    truth = "waste", codes = {"BP_V_BEACON_REDUNDANT"},
    audit = {blueprint_audit = {redundant_beacons = 1}},
    audit_beacon_config = {["iron-gear-wheel"] = 1},
}

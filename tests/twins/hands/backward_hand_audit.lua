--Round 48 physical twin: an assembling-machine-2 (1..3, 0..2) is unloaded by the inserter at (4,0) onto the belt at
--(5,0), which runs WEST, back toward the hand. The engine gives the hand both targets (truth ok); blueprint_audit
--flags the hand as backward (RRC-03).
return {
    id = "T-280-AUDIT-BACKWARD", rule = "audit:blueprint_audit:backward_hands", class = "engine",
    from = "tests/test_blueprint_physical_contract.lua transport hand", stage = "validate",
    grid = {w = 12, h = 12},
    entities = {
        {id = "machine", kind = "machine", name = "assembling-machine-2", x = 1, y = 0, w = 3, h = 3},
        {id = "hand", kind = "inserter", name = "inserter", x = 4, y = 0, dir = "east", flow_id = "item/iron-plate", pickup_position = {x = 3.5, y = 0.5}, drop_position = {x = 5.5, y = 0.5}},
        {id = "head", kind = "belt", name = "transport-belt", x = 5, y = 0, dir = "west"},
        {id = "tail", kind = "belt", name = "transport-belt", x = 6, y = 0, dir = "west"},
        {id = "pole", kind = "pole", name = "medium-electric-pole", x = 4, y = 1},
    },
    validator = {catalog = {inserter = {items_per_second = 0.83, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, entity = {
        inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1, needs_power = true, items_per_second = 0.83},
        ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", tile_w = 3, tile_h = 3, needs_power = true, crafting_speed = 0.75},
        ["transport-belt"] = {name = "transport-belt", etype = "transport-belt", tile_w = 1, tile_h = 1, needs_power = false},
        ["medium-electric-pole"] = {name = "medium-electric-pole", etype = "electric-pole", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
    }}},
    check = "pickup_drop", truth = "ok", codes = {},
    --AUDITOR-DOUBT: redundant_beacons is pinned at zero because the audit runner passes no beacon config.
    audit = {blueprint_audit = {invalid_inserters = 0, backward_hands = 1, redundant_beacons = 0}},
}

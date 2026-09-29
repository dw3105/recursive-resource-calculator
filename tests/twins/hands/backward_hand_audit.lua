return {
    id = "T-280-AUDIT-BACKWARD", rule = "audit:blueprint_audit:backward_hands", class = "engine",
    from = "tests/test_blueprint_physical_contract.lua transport hand", stage = "validate",
    grid = {w = 12, h = 12},
    entities = {
        {id = "machine", kind = "machine", name = "assembling-machine-2", x = 3, y = 0, needs_power = false},
        {id = "hand", kind = "inserter", name = "inserter", x = 4, y = 0, dir = "east", needs_power = false, flow_id = "item/iron-plate", pickup_position = {x = 3.5, y = 0.5}, drop_position = {x = 5.5, y = 0.5}},
        {id = "head", kind = "belt", name = "transport-belt", x = 5, y = 0, dir = "west"},
        {id = "tail", kind = "belt", name = "transport-belt", x = 6, y = 0, dir = "west"},
    },
    validator = {catalog = {inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}, entity = {inserter = {name = "inserter", etype = "inserter", needs_power = false, items_per_second = 5}, ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", needs_power = false, crafting_speed = 1}}}},
    check = "pickup_drop", truth = "ok", codes = {},
    --AUDITOR-DOUBT: redundant_beacons is pinned at zero because the audit runner passes no beacon config.
    audit = {blueprint_audit = {invalid_inserters = 0, backward_hands = 1, redundant_beacons = 0}},
}

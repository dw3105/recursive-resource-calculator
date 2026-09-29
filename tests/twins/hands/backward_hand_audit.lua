--AUDITOR-DOUBT: redundant_beacons is pinned at zero because the audit runner does not pass a beacon config.
return {
    id = "T-280-AUDIT-BACKWARD", rule = "audit:blueprint_audit:backward_hands", class = "waste",
    from = "tests/test_blueprint_physical_contract.lua transport hand", stage = "validate",
    grid = {w = 12, h = 12},
    entities = {
        {id = "machine", kind = "machine", name = "assembling-machine-2", x = 3, y = 5, needs_power = false},
        {id = "hand", kind = "inserter", name = "inserter", x = 4, y = 5, dir = "east", needs_power = false},
        {id = "head", kind = "belt", name = "transport-belt", x = 5, y = 5, dir = "west", flows = {"iron-plate"}},
        {id = "tail", kind = "belt", name = "transport-belt", x = 6, y = 5, dir = "west", flows = {"iron-plate"}},
    },
    validator = {catalog = {entity = { ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", needs_power = false}}}},
    check = "pickup_drop", truth = "waste", codes = {"BP_V_TRANSPORT_UNUSED"},
    audit = {blueprint_audit = {backward_hands = 1, redundant_beacons = 0}},
}

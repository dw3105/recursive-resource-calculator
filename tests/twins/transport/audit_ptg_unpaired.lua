return {
 id = "audit_ptg_unpaired", rule = "audit:blueprint_audit:unpairable_pipe_to_ground", class = "engine",
 from = "tests/test_validate_ptg_sides.lua VS1 unpaired underground pipe audit control",
 grid = {w = 20, h = 20},
 entities = {{id = "ptg", kind = "pipe", name = "pipe-to-ground", x = 3, y = 4, dir = "west", flow_id = "fluid/water"}},
 --Engine (headless 2.0.77, round 48): a lone pipe-to-ground is unpaired; the validator used to return nothing
 --for an endpoint that declares no partner (validate.lua check_underground, fixed round 48).
 validator = {catalog = {entity = {["pipe-to-ground"] = {name = "pipe-to-ground", etype = "pipe-to-ground", tile_w = 1, tile_h = 1}}}},
 check = "underground_pair", truth = "defect", codes = {"BP_V_UNDERGROUND_UNPAIRED"}, audit = {blueprint_audit = {unpairable_pipe_to_ground = 1}},
}

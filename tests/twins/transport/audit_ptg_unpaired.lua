return {
 id = "audit_ptg_unpaired", rule = "audit:blueprint_audit:unpairable_pipe_to_ground", class = "engine",
 from = "tests/test_validate_ptg_sides.lua VS1 unpaired underground pipe audit control",
 grid = {w = 20, h = 20},
 entities = {{id = "ptg", kind = "pipe", name = "pipe-to-ground", x = 3, y = 4, dir = "west", flow_id = "fluid/water"}},
 check = "underground_pair", truth = "ok", codes = {}, audit = {blueprint_audit = {unpairable_pipe_to_ground = 1}},
}

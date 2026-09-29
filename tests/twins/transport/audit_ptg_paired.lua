return {
 id = "audit_ptg_paired", rule = "audit:blueprint_audit:unpairable_pipe_to_ground", class = "engine",
 from = "tests/test_validate_ptg_sides.lua VS2 paired underground pipe audit control",
 grid = {w = 20, h = 20},
 entities = {
  {id = "in", kind = "pipe", name = "pipe-to-ground", x = 3, y = 4, dir = "west", type = "input", ug_role = "input", ug_pair_id = "out", flow_id = "fluid/water"},
  {id = "out", kind = "pipe", name = "pipe-to-ground", x = 8, y = 4, dir = "east", type = "output", ug_role = "output", ug_pair_id = "in", flow_id = "fluid/water"},
 },
 validator = {catalog = {pipe = {underground_max_distance = 10}, entity = {["pipe-to-ground"] = {name = "pipe-to-ground", etype = "pipe-to-ground", tile_w = 1, tile_h = 1, needs_power = false}}}},
 check = "underground_pair", truth = "ok", codes = {}, audit = {blueprint_audit = {unpairable_pipe_to_ground = 0}},
}

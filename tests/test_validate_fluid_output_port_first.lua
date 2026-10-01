--Round 54 integrator: a cryogenic plant has three output boxes on one face. Turned sideways (x4 Block, Turn 4, edge
--inset 6), the hot fluoroketone pipe leaves the declared port tile, runs past the middle box and on. The witness
--started at the middle box and called the two pipes on the port tile waste (BP_V_TRANSPORT_UNUSED, 6 pipes).
local H = require "tests.harness"
H.test("FO1 fluid output witness starts at the declared port tile", function()
    H.new_world("2.1")
    local f = assert(io.open("tests/fixtures/validate_cryo4_turn4.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local codes = {}
    for _, err in ipairs(state.errors or {}) do codes[#codes + 1] = tostring(err.code) end
    H.equal(table.concat(codes, " "), "", "no validate error")
    H.equal(state.ok, true)
end)
H.done("test_validate_fluid_output_port_first")

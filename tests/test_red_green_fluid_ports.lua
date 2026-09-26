--Round 41: the player's red + green science 10/s blueprint (round 40 bytes) built but 5 of 8 casting foundries got
--no fluid: a pipe-to-ground stood ON the foundry's fluid port tile with its open side facing away.
--RGF1 fails on round-41-base: the validator walks a pipe-to-ground on all four sides, so it accepts that layout.
--RGF2 fails on round-41-base: the router still lays a pipe-to-ground on a port tile facing away.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

H.test("RGF1 the round-40 red-green layout is refused: five foundries get no fluid", function()
    H.new_world(H.shapes()[1])
    local file = assert(io.open("tests/fixtures/validate_red_green_r40_c1.json", "r"))
    local root = assert(helpers.json_to_table(file:read("*a")))
    file:close()
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local disconnected = 0
    for _, e in ipairs(state.errors or {}) do
        if e.code == "BP_V_FLUID_DISCONNECTED" then disconnected = disconnected + 1 end
    end
    H.equal(disconnected, 5, "five casting foundries are reported without fluid")
end)

H.test("RGF2 no pipe-to-ground on a fluid port tile opens away from its machine", function()
    H.new_world(H.shapes()[1])
    local out = os.tmpname()
    os.execute("lua5.2 tools/capture_stage_input.lua tests/golden/cases/player-red-green-science-10s/prepared_input.json "
        .. out .. " validate 1 >/dev/null 2>&1")
    local file = io.open(out, "r")
    local captured = file and helpers.json_to_table(file:read("*a"))
    if file then file:close() end
    os.remove(out)
    H.equal(captured ~= nil, true, "the first candidate reaches the validator")
    local candidate = captured.candidate or captured
    local port_dir = {}
    for _, port in ipairs(candidate.ports or {}) do
        if port.kind == "fluid" and port.x ~= nil and port.dir ~= nil then
            port_dir[tostring(port.x) .. ":" .. tostring(port.y)] = port.dir
        end
    end
    local wrong = 0
    for _, e in ipairs(candidate.entities or {}) do
        if tostring(e.name) == "pipe-to-ground" and e.position then
            local key = tostring(math.floor(e.position.x)) .. ":" .. tostring(math.floor(e.position.y))
            if port_dir[key] ~= nil and (e.dir or e.direction) ~= port_dir[key] then wrong = wrong + 1 end
        end
    end
    H.equal(wrong, 0, "every pipe-to-ground on a fluid port tile opens into its machine")
end)

H.done("test_red_green_fluid_ports")

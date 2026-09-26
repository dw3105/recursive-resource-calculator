--Round 40: the player's red + green science 10/s sheet (tests/golden/cases/player-red-green-science-10s,
--export 1.1.89) must build. Red on round-40-base: every candidate is refused (the layered one only on
--BP_V_FLUID_MIX and BP_V_UNDERGROUND_SIDELOAD_BLOCKED).
local H = require "tests.harness"

H.test("RGD1 red + green science 10/s delivers a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-green-science-10s/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_red_green_10s_delivers")

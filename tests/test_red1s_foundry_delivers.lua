--Regression for the player's red science 1/s sheet; this test fails on the base code.
local H = require "tests.harness"

H.test("R1 red science foundry delivers a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s-foundry/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_red1s_foundry_delivers")

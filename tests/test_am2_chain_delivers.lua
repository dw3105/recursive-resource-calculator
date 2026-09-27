-- Regression for the player's am2 chain; the original case fails generation on base code.
local H = require "tests.harness"
H.test("AM1 am2 chain delivers a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-am2-chain/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)
H.done("test_am2_chain_delivers")

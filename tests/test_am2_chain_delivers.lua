-- Regression for the player's am2 chain; the original case fails generation on base code.
local H = require "tests.harness"
H.test("AM1 am2 chain delivers a blueprint", function()
    local out = os.tmpname()
    local err = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-am2-chain/prepared_input.json --output " .. out .. " >/dev/null 2>" .. err)
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    local ef = io.open(err); local error_text = ef and ef:read("*a") or ""; if ef then ef:close() end
    os.remove(out); os.remove(err)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true; output: " .. text:sub(1, 700) .. error_text)
end)
H.done("test_am2_chain_delivers")

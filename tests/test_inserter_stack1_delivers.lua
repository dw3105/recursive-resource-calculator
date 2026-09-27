--Regression for player-inserter-10s-stack1; this delivery fails on round-45-base.
local H = require "tests.harness"

H.test("player inserter stack1 generates a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-inserter-10s-stack1/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_inserter_stack1_delivers")

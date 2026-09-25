--Round 36: the player's red science 10/s sheet (tests/golden/cases/player-red-science-10s, export 1.1.81) must
--build. End to end, because its last two rules only work together: after an attempt starves an edge flow, every
--edge flow with several sinks gets one terminal per sink, and a terminal may stand on the reserved approach tile of
--a port of its own flow. With either rule removed every attempt fails (calcite into the second foundry).
local H = require "tests.harness"

H.test("R10 red science 10/s delivers a blueprint", function()
    local out = os.tmpname()
    local ok = os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-10s/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_red10s_delivers")

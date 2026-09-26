--Round 38: the player's red science 10/s sheet with bulk hands (tests/golden/cases/player-red-science-10s-bulk,
--export 1.1.85) must build. Red on round-38-base: every candidate is refused (the layered one only on
--BP_V_BEACON_REDUNDANT, a beacon that another block's beacon already covers for).
local H = require "tests.harness"

H.test("R10B red science 10/s with bulk hands delivers a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-10s-bulk/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_red10s_bulk_delivers")

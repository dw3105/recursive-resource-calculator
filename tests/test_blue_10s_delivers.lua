--Round 41: the player's blue science 10/s sheet (tests/golden/cases/player-blue-science-10s, export 1.1.91) hung
--in "placing blocks" in game. Red on round-41-base: pack refuses the oil refinery on every grid (all its fluids
--get one fluid box), so the first candidate never reaches the validator.
--Fast check (tools/first_stage.lua): stops at the first validator verdict, gives up after 15 refused packs.
local H = require "tests.harness"

H.test("BL1 the first blue science candidate validates", function()
    local handle = io.popen("lua5.2 tools/first_stage.lua player-blue-science-10s validate 15 2>&1 >/dev/null")
    local text = handle:read("*a")
    handle:close()
    H.equal(text:find("FIRST%-VALIDATE ok=true") ~= nil, true, "first candidate validates: " .. text)
end)

H.done("test_blue_10s_delivers")

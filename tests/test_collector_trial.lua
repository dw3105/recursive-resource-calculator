--Round 37 (2026-09-25): one collector belt per machine output flow is the player's shape (red science 10/s: 275
--entities against 298), but on the inserter 10/s sheet the collector layout finishes at 401 entities against 373
--without it (375 once the junk tidy turns chained splitters into straight belts). Search routes a validated collector candidate once more without collectors and keeps the better
--finished one (Validate.compare). Without that trial in logic/bp/search.lua this test fails with 401.
local H = require "tests.harness"

local function generate(case)
    local out = os.tmpname()
    local saved = arg
    arg = {[0] = "tests/golden/generate.lua", "--input", "tests/golden/cases/" .. case .. "/prepared_input.json", "--output", out}
    local ok, err = pcall(dofile, "tests/golden/generate.lua")
    arg = saved
    assert(ok, err)
    local f = assert(io.open(out)); local text = f:read("*a"); f:close(); os.remove(out)
    return helpers.json_to_table(text)
end

H.test("CT1 inserter 10/s keeps the smaller layout without collectors", function()
    H.new_world(H.shapes()[1])
    local result = generate("player-inserter-10s")
    H.equal(result.ok, true, "sheet builds")
    local n = #((result.result or {}).entities or {})
    H.equal(n <= 375, true, "entities " .. n .. " <= 375")
end)

H.done("test_collector_trial")

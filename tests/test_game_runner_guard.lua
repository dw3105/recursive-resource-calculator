--Player, 2026-09-26: lanes are FORBIDDEN from running headless tests; headless runs only at merge and release. The
--runners refuse every headless run when LANE_RUN_ID is set (lane_run sets it), before touching Factorio.
local H = require "tests.harness"

local function exit_code(command)
    local ok, how, code = os.execute(command .. " >/dev/null 2>&1")
    if type(ok) == "number" then return ok end
    return code
end

H.test("GR1 a lane cannot run the headless full suite", function()
    H.equal(exit_code("LANE_RUN_ID=x sh tools/game_test.sh 2.0 --full"), 2, "--full refused")
end)

H.test("GR2 a lane cannot run one headless game test", function()
    H.equal(exit_code("LANE_RUN_ID=x sh tools/game_test.sh 2.1 'tests/game/test_probe.lua::probe > rrc loads'"), 2, "one test refused")
end)

H.test("GR3 a lane cannot load-check a zip headless", function()
    H.equal(exit_code("LANE_RUN_ID=x sh tools/game_load_check.sh /nonexistent.zip 2.0"), 2, "load check refused")
end)

H.done("test_game_runner_guard")

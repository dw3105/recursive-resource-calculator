--Round 51 integration: the drawn pack (RRC_PACK=sugiyama: Flow graph drawing, Block Turn, machine Turn/Flip) delivers
--the three fast player sheets end to end, judged from delivered bytes (lane_sim clean, names ok). Each sheet runs in
--seconds (tools/slow_budget.json fast_cases). Red on round-51-base only if the skeleton path breaks delivery.
local H = require "tests.harness"

local CASES = {"player-red-science-1s", "player-red-science-1s-foundry", "player-green-science-1s"}

local function run(cmd)
    local p = io.popen(cmd .. " 2>&1")
    local text = p:read("*a")
    p:close()
    return text
end

for i, case in ipairs(CASES) do
    H.test("DE" .. i .. " drawn pack delivers " .. case, function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p " .. dir)
        local input = "tests/golden/cases/" .. case .. "/prepared_input.json"
        os.execute("RRC_PACK=sugiyama lua5.2 tests/golden/generate.lua --input " .. input .. " --output " .. dir .. "/r.json >/dev/null 2>&1")
        local f = io.open(dir .. "/r.json"); local text = f and f:read("*a") or ""; if f then f:close() end
        H.equal(text:find('"ok":%s*true') ~= nil, true, case .. " generate returns ok=true under RRC_PACK=sugiyama")
        run("python3 tools/blueprint_string.py " .. dir .. "/r.json -o " .. dir .. "/bp.txt")
        local lanes = run("python3 tools/lane_sim.py " .. dir .. "/bp.txt --input " .. input .. " | tail -1")
        H.equal(lanes:match("LANE%-SIM mixed=0 starved=0 bleed=0") ~= nil, true, case .. " lane_sim clean: " .. lanes)
        local names = run("python3 tools/entity_names.py " .. dir .. "/bp.txt " .. input .. " | tail -1")
        H.equal(names:match("NAMES%-OK") ~= nil, true, case .. " names: " .. names)
        os.execute("rm -rf " .. dir)
    end)
end

H.done("test_drawn_e2e")

--Round 39: the player rebuilt our 1.1.87 red science 10/s bulk blueprint (266 entities) by hand at 192. Four
--mistakes, each its own row. Numbers are the combined result of lanes 226-228, measured on the probe tree
--(docs/tasks/r39_probe_reference.diff) on 2026-09-26. Every row is RED on round-39-base (266/157/10/15/37).
local H = require "tests.harness"

local summary
local function measure()
    if summary then return summary end
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-10s-bulk/prepared_input.json --output "
        .. out .. " >/dev/null 2>&1")
    local py = [[
import json, sys, collections
r = json.load(open(sys.argv[1]))
es = r.get("result", {}).get("entities", []) if r.get("ok") else []
c = collections.Counter(e["name"].split("-", 1)[1] if e["name"].startswith("turbo-") else e["name"] for e in es)
south = sum(1 for e in es if e["name"].endswith("transport-belt") and e["position"]["x"] == 30.5
    and 8 < e["position"]["y"] < 37 and e.get("direction", 0) != 0)
print("ok=%d entities=%d belts=%d ug=%d beacons=%d pipes=%d south=%d" % (1 if r.get("ok") else 0, len(es),
    c["transport-belt"], c["underground-belt"], c["beacon"], c["pipe"], south))
]]
    local p = io.popen("python3 -c '" .. py .. "' " .. out)
    local line = p and p:read("*l") or ""
    if p then p:close() end
    os.remove(out)
    summary = {}
    for k, v in line:gmatch("(%w+)=(%d+)") do summary[k] = tonumber(v) end
    return summary
end

local function at_most(key, cap, why)
    local s = measure()
    H.equal(s.ok, 1, "generate returns ok=true")
    H.equal((s[key] or math.huge) <= cap, true, why .. ": " .. key .. "=" .. tostring(s[key]) .. " cap " .. cap)
end

H.test("SH1 science output belt x=30 runs north, no U-turn (lane 226)", function()
    at_most("south", 0, "output run flows toward the top exit")
    at_most("belts", 104, "belts")
end)
H.test("SH2 ore hands seated on the edge face, no undergrounds under foundries (lane 227)", function()
    at_most("ug", 4, "undergrounds")
end)
H.test("SH3 one beacon shared by both molten foundries (lane 228)", function()
    at_most("beacons", 14, "beacons")
end)
H.test("SH4 fluid output box nearest its partner (lane 228)", function()
    at_most("pipes", 31, "pipes")
end)
H.test("SH5 whole sheet", function()
    at_most("entities", 200, "entities")
end)

H.done("test_red10s_bulk_shape")

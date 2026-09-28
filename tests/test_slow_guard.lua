-- SG1 is red on base: golden generation starts without a guard and does not refuse in under two seconds.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local function write(path, text)
    local f = assert(io.open(path, "w")); f:write(text); f:close()
end
local function run(command, slot, reason)
    local env = "RRC_SLOW_LEDGER=/tmp/rrc-sg-ledger.tsv RRC_WAVE_FILE=/tmp/rrc-sg-wave "
    if slot then env = env .. "RRC_SLOW='" .. slot .. ":" .. reason .. "' " else env = env .. "RRC_SLOW= " end
    local p = io.popen(env .. command .. " 2>&1", "r")
    local out = p:read("*a"); local ok, why, code = p:close()
    return out, (ok and 0 or code or 1)
end
local function refused(out, code)
    H.equal(code, 7, "refusal exit code"); H.equal(out:find("SLOW%-REFUSED") ~= nil, true, "refusal line")
end
local golden = "tests/golden/cases/player-red-science-1s/prepared_input.json"
write("/tmp/rrc-sg-wave", "sg-wave\n")
H.test("SG1 unapproved golden generation refuses immediately", function()
    io.write("SG1\n")
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local out, code = run("lua5.2 tests/golden/generate.lua --input " .. golden .. " --output /tmp/x", nil)
    refused(out, code)
end)
H.test("SG2 short reason refuses", function()
    io.write("SG2\n")
    local out, code = run("lua5.2 tests/golden/generate.lua --input " .. golden, "profile", "short")
    refused(out, code)
end)
H.test("SG3 unknown slot refuses", function()
    io.write("SG3\n")
    local out, code = run("lua5.2 tests/golden/generate.lua --input " .. golden, "turbo", "long enough reason for tests")
    refused(out, code)
end)
H.test("SG4 valid authorization records one ledger line", function()
    io.write("SG4\n")
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local command = "lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden_profile\", \"tests/fixtures/route_red10s_call2.json\")'"
    local out, code = run(command, "profile", "authorized profile work for SG4")
    H.equal(code, 0, out)
    local f = assert(io.open("/tmp/rrc-sg-ledger.tsv")); local lines = 0; for _ in f:lines() do lines=lines+1 end; f:close()
    H.equal(lines, 1, "one audit record")
end)
H.test("SG5 per wave budget refuses second profile", function()
    io.write("SG5\n")
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local command = "lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden_profile\")'"
    local _, first = run(command, "profile", "first allowed profile call in same wave")
    local out, second = run(command, "profile", "second profile call in same wave")
    H.equal(first, 0, "first authorization"); refused(out, second)
end)
H.test("SG6 test slot rejects golden case and allows small fixture", function()
    io.write("SG6\n")
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local command = "lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden generate\", \"%s\")'"
    local out, code = run(string.format(command, golden), "test", "ok")
    refused(out, code)
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local _, allowed = run(string.format(command, "tests/fixtures/route_red10s_call2.json"), "test", "okay")
    H.equal(allowed, 0, "small fixture is allowed")
end)
H.test("SG7 every listed tool refuses before doing work", function()
    io.write("SG7\n")
    local commands = {
        "lua5.2 tests/golden/generate.lua --input " .. golden,
        "lua5.2 tools/golden_profile.lua small /tmp/x",
        "lua5.2 tools/ckpt.lua save x a b", "lua5.2 tools/ckpt.lua list x", "lua5.2 tools/ckpt.lua uninterrupted x",
        "lua5.2 tools/first_stage.lua x pack", "sh tools/bytes_hash.sh x", "sh tools/gate_sheet.sh x 1",
        "sh tools/measure_sheet.sh x", "sh tools/speed_probe.sh", "sh tests/run.sh", "sh tools/game_test.sh 2.0 --full"
    }
    for _, command in ipairs(commands) do
        os.remove("/tmp/rrc-sg-ledger.tsv")
        local out, code = run(command, nil)
        H.equal(code, 7, command .. " exit code"); H.equal(out:find("SLOW%-REFUSED") ~= nil, true, command .. " refusal")
    end
end)
H.test("SG8 checkpoint resume is exempt", function()
    io.write("SG8\n")
    local out, code = run("lua5.2 tools/ckpt.lua resume /tmp/no-such-checkpoint", nil)
    H.equal(out:find("SLOW%-REFUSED") == nil, true, "resume did not invoke guard")
    H.equal(code ~= 7, true, "resume proceeded to checkpoint handling")
end)
--SG9 (integrator, 2026-09-28): a budget counts distinct runs. bytes_hash.sh runs generate.lua and a 13-sheet gate
--runs bytes_hash.sh 13 times under ONE RRC_SLOW value: every nested or repeated check of that value passes.
H.test("SG9 one RRC_SLOW value is one run for children and loop steps", function()
    io.write("SG9\n")
    os.remove("/tmp/rrc-sg-ledger.tsv")
    local command = "lua5.2 -e 'package.path=\"./?.lua;\"..package.path; require(\"tools.lib.slow_guard\").check(\"golden_profile\")'"
    local _, first = run(command, "profile", "one profile run with nested checks")
    local _, again = run(command, "profile", "one profile run with nested checks")
    local out, other = run(command, "profile", "a different second profile run")
    H.equal(first, 0, "first check"); H.equal(again, 0, "same run checked again"); refused(out, other)
end)
H.done("test_slow_guard")

--Red on round-56-base: per-case selection, unit collection, and JUnit addresses are absent there. 2026-10-04.
local H = require "tests.harness"
local J = require "tools.junit"

local function command_output(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a")
    local ok, why, code = pipe:close()
    return output, ok, why, code
end

local function has(text, fragment)
    return text:find(fragment, 1, true) ~= nil
end

H.test("SU1 RRC_CASE selects only the exact named fixture case", function()
    local output, ok = command_output("RRC_CASE=a lua5.2 tests/fixtures/r56/315/tiny.lua")
    H.equal(ok, true, "selected fixture exits successfully: " .. output)
    H.equal(has(output, "FIXTURE-a"), true, "selected case ran")
    H.equal(has(output, "FIXTURE-b"), false, "unselected case did not run")
    local dispatched, dispatched_ok = command_output("RRC_SUITE_ROOT=tests/fixtures/r56/315 RRC_JUNIT_DIR=/tmp/rrc-315-junit sh tools/suite_units.sh run lua/tiny::a")
    H.equal(dispatched_ok, true, "runner dispatched one address: " .. dispatched)
    H.equal(has(dispatched, "FIXTURE-a"), true, "runner executed requested unit")
    H.equal(has(dispatched, "FIXTURE-b"), false, "runner omitted other unit")
    print("SU1")
end)

H.test("SU2 collect ids agree with JUnit addresses for the tiny fixture suite", function()
    local ids, ok = command_output("RRC_SUITE_ROOT=tests/fixtures/r56/315 sh tools/suite_units.sh collect")
    H.equal(ok, true, "collect command exits successfully: " .. ids)
    H.equal(ids, "lua/tiny::a\nlua/tiny::b\n", "collected addresses")
    local xml, xml_ok = command_output("RRC_JUNIT_DIR=/tmp/rrc-315-junit lua5.2 tests/fixtures/r56/315/tiny.lua")
    H.equal(xml_ok, true, "fixture wrote JUnit: " .. xml)
    local junit_file = io.open("/tmp/rrc-315-junit/junit-tiny.xml", "r")
    H.equal(junit_file ~= nil, true, "JUnit file exists")
    local junit = junit_file:read("*a")
    junit_file:close()
    H.equal(has(junit, 'classname="lua/tiny" name="a"'), true, "JUnit a address")
    H.equal(has(junit, 'classname="lua/tiny" name="b"'), true, "JUnit b address")
    print("SU2")
end)

H.test("SU3 JUnit classnames never contain a separator", function()
    local output, ok = command_output("RRC_JUNIT_DIR=/tmp/rrc-315-junit lua5.2 tests/fixtures/r56/315/tiny.lua")
    H.equal(ok, true, "JUnit fixture succeeds: " .. output)
    local file = assert(io.open("/tmp/rrc-315-junit/junit-tiny.xml", "r"))
    local xml = file:read("*a"); file:close()
    for classname in xml:gmatch('classname="([^"]+)"') do
        H.equal(classname:find("::", 1, true), nil, "classname is only the prefix")
    end
    print("SU3")
end)

H.test("SU4 census and sheet unit addresses use their required prefixes", function()
    H.equal(J.classname("test_turn_flip_census", "case-x"), "census/case-x", "census prefix")
    H.equal(J.classname("test_sheets", "case-y"), "sheets/case-y", "sheet prefix")
    H.equal(J.classname("test_turn_flip_sims", "case-z"), "turnflip/case-z", "turnflip prefix")
    print("SU4")
end)

H.test("SU5 unknown RRC_CASE fails and names the missing case", function()
    local output, ok = command_output("RRC_CASE=does-not-exist lua5.2 tests/fixtures/r56/315/tiny.lua")
    H.equal(ok, nil, "unknown case exits non-zero")
    H.equal(has(output, "does-not-exist"), true, "error names unknown case")
    print("SU5")
end)

H.done("test_split_units")

--The companion's cheap proof is a state-machine proof, not a throughput claim.
--The first red run deliberately uses the small fallback below while scenario.lua
--does not exist.  That keeps the red proof in assertions instead of a loader
--error; the same cases exercise the real controller after it is added.
package.path = "tests/golden/engine/mod/?.lua;" .. package.path
local scenario_ok, Scenario = pcall(require, "scenario")
if not scenario_ok then
    Scenario = {}
    function Scenario.new()
        return {
            submit = function() return false, {state = "missing-controller"} end,
            tick = function() end,
            cancel = function() return {state = "missing-controller"} end,
        }
    end
end

local passed, failed = 0, 0
local function fail(message)
    failed = failed + 1
    io.write("FAIL " .. message .. " [assert]\n")
end

local function equal(actual, expected, message)
    if actual ~= expected then fail(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
end

local function truth(value, message) equal(value, true, message) end

local function near(actual, expected, message)
    if math.abs(actual - expected) > 1e-9 then
        fail(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function test(name, body)
    local before = failed
    local ok, message = pcall(body)
    if not ok then fail(name .. ": " .. tostring(message)) end
    if failed == before then
        passed = passed + 1
        io.write("PASS " .. name .. "\n")
    end
end

local function fake_world(sequence, build, options)
    options = options or {}
    local calls = {}
    local written
    local tick = 0
    local status_index = 0
    local candidate = {
        build_id = function()
            calls[#calls + 1] = "build_id"
            return build or {candidate_sha = "sha-good", packaged = true, factorio_branch = "2.0"}
        end,
        start_generation = function(context)
            calls[#calls + 1] = "start_generation"
            calls.context = context
            return options.job_id or "job-1"
        end,
        generation_status = function()
            calls[#calls + 1] = "generation_status"
            status_index = status_index + 1
            return sequence[status_index] or sequence[#sequence] or {state = "pending"}
        end,
        cancel_generation = function()
            calls[#calls + 1] = "cancel_generation"
            return {state = "cancelled"}
        end,
        export = function()
            calls[#calls + 1] = "export"
            return options.export or "encoded-export"
        end,
        canonical = function()
            calls[#calls + 1] = "canonical"
            return {canonical_sha256 = "canonical-sha", canonical_version = 1}
        end,
    }
    local adapter = {
        tick = function() return tick end,
        setup_environment = function(case)
            calls[#calls + 1] = "setup_environment"
            return {surface = case.engine_scenario.surface or "nauvis", force = "player"}
        end,
        generation_context = function(case)
            calls[#calls + 1] = "generation_context"
            return {sheet_id = case.sheet_id or case.case_id, prepared_input = case.prepared_input}
        end,
        build_blueprint = function(blueprint)
            calls[#calls + 1] = "build_blueprint"
            if options.build_failure then return nil, "build failed" end
            return {blueprint_string = blueprint, entities = {"factory"}}
        end,
        prepare_supply = function()
            calls[#calls + 1] = "prepare_supply"
            return {}
        end,
        provide_power = function()
            calls[#calls + 1] = "provide_power"
            return true
        end,
        prepare_drain = function()
            calls[#calls + 1] = "prepare_drain"
            return {}
        end,
        supply = function()
            calls[#calls + 1] = "supply"
            return {accepted = {["item/ore"] = 1 / 3}}
        end,
        drain = function()
            calls[#calls + 1] = "drain"
            return {drained = {["item/plate"] = 1 / 3}}
        end,
        cleanup = function()
            calls[#calls + 1] = "cleanup"
        end,
        metadata = function()
            return {engine_version = "2.0.77", active_mods = {base = "2.0.77"}, force_research = {}}
        end,
        write_observation = function(observation)
            written = observation
            calls[#calls + 1] = "write_observation"
        end,
        announce = function() end,
    }
    return candidate, adapter, calls, function(value) tick = value end, function() return written end
end

local function case(overrides)
    local result = {
        case_id = "scenario-case",
        expected_candidate_sha = "sha-good",
        sheet_id = "sheet-1",
        setup = {selection = {}, settings = {}, options = {}},
        engine_scenario = {
            warm_up_ticks = 2,
            sampling_window_ticks = 3,
            timeout_seconds = 10,
            supply = {{full_name = "item/ore", rate_per_second = 1}},
            drain = {{full_name = "item/plate", rate_per_second = 1}},
            expected_rates = {['item/plate'] = 20},
        },
    }
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

test("SM1 pending generation reaches build, perimeter, warm-up, sample and write", function()
    local candidate, adapter, calls, set_tick, written = fake_world({
        {state = "pending"}, {state = "success", blueprint_string = "blueprint"},
    })
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    local accepted = controller:submit(case())
    truth(accepted, "submission accepted")
    equal(controller:status().state, "environment", "initial state waits for a tick")
    set_tick(1); controller:tick(1); equal(controller:status().state, "generation", "environment transition")
    set_tick(2); controller:tick(2); equal(controller:status().state, "generation", "pending generation transition")
    set_tick(3); controller:tick(3); equal(controller:status().state, "build", "terminal generation transition")
    set_tick(4); controller:tick(4); equal(controller:status().state, "supply_setup", "build transition")
    set_tick(5); controller:tick(5); equal(controller:status().state, "power", "supply transition")
    set_tick(6); controller:tick(6); equal(controller:status().state, "drain_setup", "power transition")
    for current = 7, 12 do set_tick(current); controller:tick(current) end
    equal(written().outcome_kind, "production", "production observation")
    near(written().production.rates["item/plate"], 20, "rate arithmetic in production")
    equal(calls[2], "setup_environment", "environment follows identity")
    truth(table.concat(calls, ","):find("build_blueprint", 1, true) ~= nil, "blueprint built")
    truth(table.concat(calls, ","):find("provide_power", 1, true) ~= nil, "power supplied")
    truth(table.concat(calls, ","):find("supply", 1, true) ~= nil, "input supplied")
    truth(table.concat(calls, ","):find("drain", 1, true) ~= nil, "output drained")
end)

test("SM2 a development build is refused before setup or generation", function()
    local candidate, adapter, calls, set_tick, written = fake_world({}, {candidate_sha = "dev", packaged = false})
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case())
    set_tick(1); controller:tick(1)
    equal(written().outcome_kind, "rejection", "development rejection")
    equal(written().rejection.stage, "identity", "identity rejection stage")
    equal(calls[1], "build_id", "identity is read first")
    equal(calls[2], "write_observation", "rejection is written")
    equal(#calls, 2, "no factory work after refusal")
end)

test("SM3 a candidate SHA mismatch is refused before setup or generation", function()
    local candidate, adapter, calls, _, written = fake_world({}, {candidate_sha = "sha-other", packaged = true})
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case())
    equal(written().rejection.reason_codes[1], "RRC_CANDIDATE_IDENTITY_MISMATCH", "identity mismatch code")
    equal(#calls, 2, "no factory work after mismatch")
end)

test("SM4 a failed build is rejected and cleaned up", function()
    local candidate, adapter, calls, set_tick, written = fake_world({
        {state = "success", blueprint_string = "blueprint"},
    }, nil, {build_failure = true})
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case())
    for current = 1, 6 do set_tick(current); controller:tick(current) end
    equal(written().rejection.stage, "build", "build rejection stage")
    truth(table.concat(calls, ","):find("cleanup", 1, true) ~= nil, "failed build cleanup")
end)

test("SM5 generation timeout cancels the candidate", function()
    local candidate, adapter, calls, set_tick, written = fake_world({{state = "pending"}}, nil)
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    local timed = case({engine_scenario = {warm_up_ticks = 0, sampling_window_ticks = 1, timeout_seconds = 1}})
    controller:submit(timed)
    for current = 1, 65 do set_tick(current); controller:tick(current) end
    equal(written().rejection.stage, "generation-timeout", "timeout stage")
    truth(table.concat(calls, ","):find("cancel_generation", 1, true) ~= nil, "timeout cancellation")
end)

test("SM6 explicit cancellation writes a rejection and cleans up", function()
    local candidate, adapter, calls, set_tick, written = fake_world({{state = "pending"}})
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case())
    set_tick(1); controller:tick(1)
    local result = controller:cancel()
    equal(result.state, "cancelled", "cancelled status")
    equal(written().rejection.stage, "cancelled", "cancelled observation stage")
    truth(table.concat(calls, ","):find("cancel_generation", 1, true) ~= nil, "candidate cancellation")
end)

test("SM7 warm-up and sample are half-open tick boundaries", function()
    local candidate, adapter, _, set_tick, written = fake_world({
        {state = "success", blueprint_string = "blueprint"},
    })
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case())
    for current = 1, 12 do set_tick(current); controller:tick(current) end
    local production = written().production
    equal(production.warm_up.ticks, 2, "warm-up tick count")
    equal(production.window.ticks, 3, "sample tick count")
    equal(production.window.start_tick + 2, production.window.end_tick, "sample end boundary")
end)

test("SM8 rate arithmetic uses engine ticks, not wall time", function()
    equal(Scenario.rate_per_second(5, 300), 1, "five items in 300 ticks is one per second")
    equal(Scenario.rate_per_second(0, 60), 0, "zero count rate")
    equal(Scenario.rate_per_second(5, 0), 0, "zero-window guard")
end)

test("SM9 export is a terminal outcome with no production block", function()
    local candidate, adapter, calls, set_tick, written = fake_world({}, nil, {export = "encoded-export"})
    local controller = Scenario.new({candidate = candidate, adapter = adapter})
    controller:submit(case({expected_outcome = "export"}))
    set_tick(1); controller:tick(1)
    set_tick(2); controller:tick(2)
    equal(written().outcome_kind, "export", "export outcome")
    equal(written().production, nil, "export has no production block")
    truth(table.concat(calls, ","):find("export", 1, true) ~= nil, "candidate export called")
    equal(table.concat(calls, ","):find("start_generation", 1, true), nil, "export does not generate")
end)

io.write(string.format("%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)

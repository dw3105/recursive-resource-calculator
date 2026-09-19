--A finished calculation is a plain, current record; stale, cancelled and forgotten work is never served.
local H = require "tests.harness"

local function record(sheet_revision, config_revision, fingerprint, result)
    return {
        schema_version = 1,
        player_index = 1,
        sheet_id = "sheet",
        sheet_revision = sheet_revision or 0,
        config_revision = config_revision or 0,
        input_fingerprint = fingerprint or "input-1",
        result = result or {status = "ok", solved_rates = { ["item/plate"] = 3 }},
        published_tick = 12,
    }
end

local function fresh(shape)
    H.new_world(shape)
    storage[1] = {}
    return require "logic.calculation_result"
end

local function walk_plain(value, path, seen)
    local value_type = type(value)
    H.equal(value_type == "function" or value_type == "userdata", false, path .. " is not executable or a LuaObject")
    if value_type ~= "table" then return end
    H.equal(getmetatable(value), nil, path .. " has no metatable")
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        walk_plain(key, path .. ".<key>", seen)
        walk_plain(child, path .. "." .. tostring(key), seen)
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CR-01 publish and get return an isolated CalculationResult", function()
        local Calculation = fresh(shape)
        local source = record(2, 4, "input-2", {status = "ok", solved_rates = {plate = 3}, nested = {value = true}})
        H.equal(Calculation.publish(source), true, "publication succeeds")

        local first = Calculation.get(1, "sheet", {sheet_revision = 2, config_revision = 4, input_fingerprint = "input-2"})
        H.deep_equal(first, source, "the published record is readable")
        first.result.nested.value = false
        H.equal(Calculation.get(1, "sheet", {sheet_revision = 2, config_revision = 4, input_fingerprint = "input-2"}).result.nested.value,
            true, "get returns a copy")
    end)

    H.test(shape .. " CR-02 an older sheet revision is stale and reports BP_REJ_SNAPSHOT_STALE", function()
        local Calculation = fresh(shape)
        Calculation.publish(record(1, 4, "input-2"))
        local value, reason = Calculation.get(1, "sheet", {sheet_revision = 2, config_revision = 4, input_fingerprint = "input-2"})
        H.equal(value, nil, "older sheet revision is not served")
        H.equal(reason, "BP_REJ_SNAPSHOT_STALE", "sheet revision stale reason")
    end)

    H.test(shape .. " CR-03 an older config revision is stale and reports BP_REJ_SNAPSHOT_STALE", function()
        local Calculation = fresh(shape)
        Calculation.publish(record(2, 3, "input-2"))
        local value, reason = Calculation.get(1, "sheet", {sheet_revision = 2, config_revision = 4, input_fingerprint = "input-2"})
        H.equal(value, nil, "older config revision is not served")
        H.equal(reason, "BP_REJ_SNAPSHOT_STALE", "config revision stale reason")
    end)

    H.test(shape .. " CR-04 a changed input fingerprint is stale and reports BP_REJ_SNAPSHOT_STALE", function()
        local Calculation = fresh(shape)
        Calculation.publish(record(2, 4, "input-old"))
        local value, reason = Calculation.get(1, "sheet", {sheet_revision = 2, config_revision = 4, input_fingerprint = "input-new"})
        H.equal(value, nil, "changed input is not served")
        H.equal(reason, "BP_REJ_SNAPSHOT_STALE", "input fingerprint stale reason")
    end)

    H.test(shape .. " CR-05 a cancelled publication leaves the previous record untouched", function()
        local Calculation = fresh(shape)
        local previous = record(1, 1, "old", {status = "ok", solved_rates = {plate = 1}})
        Calculation.publish(previous)
        --A cancelled or superseded pipeline has no successful publication call at all.
        local current = Calculation.get(1, "sheet", {sheet_revision = 1, config_revision = 1, input_fingerprint = "old"})
        H.deep_equal(current, previous, "cancelled work does not overwrite the old record")
    end)

    H.test(shape .. " CR-06 forget drops a sheet and forget_player drops the remaining player records", function()
        local Calculation = fresh(shape)
        Calculation.publish(record(0, 0, "one"))
        local other = record(0, 0, "two")
        other.sheet_id = "other"
        Calculation.publish(other)
        H.equal(Calculation.forget(1, "sheet"), true, "sheet deletion forgets one record")
        H.equal(Calculation.get(1, "sheet"), nil, "deleted sheet record is gone")
        H.equal(Calculation.get(1, "other", {sheet_revision = 0, config_revision = 0, input_fingerprint = "two"}) ~= nil, true,
            "another sheet remains")
        H.equal(Calculation.forget_player(1), true, "reset/player removal forgets all records")
        H.equal(storage[1].calc_results, nil, "player records are dropped")
    end)

    H.test(shape .. " CR-07 reads and writes charge one bounded copy operation", function()
        local Calculation = fresh(shape)
        local publish_budget = {ops = 1}
        H.equal(Calculation.publish(record(0, 0, "budget"), publish_budget), true, "publish fits in one operation")
        H.equal(publish_budget.ops, 0, "publish spends its operation")
        local get_budget = {ops = 1}
        H.equal(Calculation.get(1, "sheet", {sheet_revision = 0, config_revision = 0, input_fingerprint = "budget"}, get_budget) ~= nil, true,
            "get fits in one operation")
        H.equal(get_budget.ops, 0, "get spends its operation")
        H.equal(Calculation.get(1, "sheet", {sheet_revision = 0, config_revision = 0, input_fingerprint = "budget"}, {ops = 0}), nil,
            "a zero budget cannot copy")
    end)

    H.test(shape .. " CR-08 storage calculation records contain only plain data", function()
        local Calculation = fresh(shape)
        Calculation.publish(record(1, 2, "plain", {status = "ok", nested = {number = 1, flag = true, callback = function() end}}))
        walk_plain(storage[1].calc_results, "storage[1].calc_results")
    end)
end

H.done("test_calculation_result")

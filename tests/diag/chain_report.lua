--One integrated run of one chain, reported as structured records.
--Every number below comes from the same single run, so termination, validator outcome and output presence can
--never be read from three separate expensive runs that disagree.
--
--  lua5.2 tests/diag/chain_report.lua item_chain [search_budget] [ticks]
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"

local which = (...) or arg and arg[1] or "item_chain"
local budget = tonumber(arg and arg[2])
local tick_limit = tonumber(arg and arg[3]) or 1200

local function clock() return os.clock() end

local function fingerprint(candidate)
    local ids = {}
    for _, entity in ipairs(candidate and candidate.entities or {}) do ids[#ids + 1] = tostring(entity.id or entity.name) end
    table.sort(ids)
    return tostring(#ids) .. ":" .. table.concat(ids, ",")
end

local record = {stages = {}, validate = {calls = 0, ok = 0, bad = 0, codes = {}, samples = {}},
    route = {calls = 0, ok = 0, failed = 0, codes = {}}, power = {calls = 0, consumers = nil},
    serialize = 0, incumbent_tick = nil, max_tick_ms = 0, ops = {}}

local function bump(table_of_counts, key)
    key = tostring(key)
    table_of_counts[key] = (table_of_counts[key] or 0) + 1
end

local function instrument()
    local Route = require "logic.bp.route"
    local Power = require "logic.bp.power"
    local Validate = require "logic.bp.validate"
    local Serialize = require "logic.bp.serialize"
    local Search = require "logic.bp.search"

    local route_begin, route_step = Route.begin, Route.step
    Route.begin = function(input) record.route.calls = record.route.calls + 1; return route_begin(input) end
    Route.step = function(state, budget_table)
        local out = route_step(state, budget_table)
        if out and out.done and not out.__diag then
            out.__diag = true
            if out.ok == false then
                record.route.failed = record.route.failed + 1
                bump(record.route.codes, out.errors and out.errors[1] and out.errors[1].code)
            else record.route.ok = record.route.ok + 1 end
        end
        return out
    end

    local power_begin = Power.begin
    Power.begin = function(input)
        record.power.calls = record.power.calls + 1
        record.power.consumers = record.power.consumers or #(input.consumers or {})
        record.power.occupied = record.power.occupied or #(input.occupied or {})
        return power_begin(input)
    end

    local validate_begin, validate_step = Validate.begin, Validate.step
    Validate.begin = function(input)
        record.validate.calls = record.validate.calls + 1
        local state = validate_begin(input)
        state.__diag_candidate = fingerprint(input and input.candidate)
        return state
    end
    Validate.step = function(state, budget_table)
        local out = validate_step(state, budget_table)
        if out and out.done and not out.__diag then
            out.__diag = true
            local result = out.result or {}
            local errors = result.errors or out.errors or {}
            if #errors == 0 and out.ok ~= false then
                record.validate.ok = record.validate.ok + 1
                record.accepted = state.__diag_candidate
            else
                record.validate.bad = record.validate.bad + 1
                for _, error_record in ipairs(errors) do
                    local code = type(error_record) == "table" and error_record.code or error_record
                    bump(record.validate.codes, code)
                    if #record.validate.samples < 12 and type(error_record) == "table" then
                        record.validate.samples[#record.validate.samples + 1] = {code = tostring(code),
                            ids = table.concat(error_record.ids or {}, "|"),
                            detail = type(error_record.detail) == "table"
                                and tostring(error_record.detail.reason) or tostring(error_record.detail)}
                    end
                end
            end
        end
        return out
    end

    local serialize_begin = Serialize.begin
    Serialize.begin = function(candidate)
        record.serialize = record.serialize + 1
        record.serialized = fingerprint(candidate)
        return serialize_begin(candidate)
    end

    local search_begin, search_step = Search.begin, Search.step
    Search.begin = function(input)
        record.effective_budget = input.search_budget
        local state = search_begin(input)
        return state
    end
    Search.step = function(state, budget_table)
        local out = search_step(state, budget_table)
        local inner = out and out.work and out or state
        record.max_ops = inner and inner.max_ops or record.max_ops
        record.ops_used = inner and inner.ops_used or record.ops_used
        if record.incumbent_tick == nil and inner and inner.incumbent ~= nil then record.incumbent_tick = record.tick end
        return out
    end
end

--The harness clears package.loaded when it builds a world, so instrumentation installed before that build is
--thrown away. Build first, then instrument the modules the run will actually use.
local started = clock()
local chain = Chains[which]("2.0")
local built = clock()
instrument()

local Generation = require "logic.bp.generation"
local settings = require("logic.bp.settings").of_sheet(1, chain.sheet_id)
local start = {player_index = 1, sheet_id = chain.sheet_id, settings = settings, deliver = true}
if budget then start.options = {search_budget = budget} end
local job_id = Generation.start(start)
local result = Generation.status(1, job_id)
record.tick = 0
while result.state == "pending" and record.tick < tick_limit do
    local before = clock()
    H.run_ticks(chain.world, 1)
    local spent = (clock() - before) * 1000
    if spent > record.max_tick_ms then record.max_tick_ms = spent end
    record.tick = record.tick + 1
    result = Generation.status(1, job_id)
end
local finished = clock()

local function counts(map)
    local names = {}
    for key in pairs(map) do names[#names + 1] = key end
    table.sort(names)
    local parts = {}
    for _, key in ipairs(names) do parts[#parts + 1] = key .. "=" .. map[key] end
    return table.concat(parts, " ")
end

print("CHAIN " .. which)
print("  terminal      state=" .. tostring(result.state) .. " stage=" .. tostring(result.stage or result.phase)
    .. " codes=" .. table.concat(result.reason_codes or {}, ","))
print("  limits        effective_search_budget=" .. tostring(record.effective_budget)
    .. " max_ops=" .. tostring(record.max_ops) .. " ops_used=" .. tostring(record.ops_used))
print("  route         begun=" .. record.route.calls .. " ok=" .. record.route.ok
    .. " failed=" .. record.route.failed .. " " .. counts(record.route.codes))
print("  power         begun=" .. record.power.calls .. " consumers=" .. tostring(record.power.consumers)
    .. " occupied=" .. tostring(record.power.occupied))
print("  validate      begun=" .. record.validate.calls .. " accepted=" .. record.validate.ok
    .. " rejected=" .. record.validate.bad .. " " .. counts(record.validate.codes))
for _, sample in ipairs(record.validate.samples) do
    print("    reject      " .. sample.code .. " ids=" .. sample.ids .. " detail=" .. tostring(sample.detail))
end
print("  publish       serialize_begun=" .. record.serialize .. " serialized=" .. tostring(record.serialized ~= nil)
    .. " accepted_is_serialized=" .. tostring(record.accepted ~= nil and record.accepted == record.serialized))
print("  timing        build_s=" .. string.format("%.2f", built - started)
    .. " run_s=" .. string.format("%.2f", finished - built)
    .. " ticks=" .. record.tick .. " max_tick_ms=" .. string.format("%.1f", record.max_tick_ms)
    .. " first_incumbent_tick=" .. tostring(record.incumbent_tick))

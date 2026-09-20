--The delivery assertion: a chain must reach a successful, independently validated, non-empty blueprint.
--Nothing here stubs a stage. Validate and Serialize are wrapped only to observe which candidate passed the
--independent check and which candidate was published, so a success cannot come from an unchecked layout.
local H = require "tests.harness"

local M = {}

local function fingerprint(candidate)
    local ids = {}
    for _, entity in ipairs(candidate and candidate.entities or {}) do
        ids[#ids + 1] = tostring(entity.id or entity.name)
    end
    table.sort(ids)
    return tostring(#ids) .. ":" .. table.concat(ids, ",")
end

--Observers stay installed for one run and are removed again, so one case never changes another's modules.
local function observe()
    local Validate = require "logic.bp.validate"
    local Serialize = require "logic.bp.serialize"
    local record = {validated_ok = {}, serialized = nil, validate_calls = 0, validate_ok = 0, validate_bad = 0,
        codes = {}}
    local validate_begin, validate_step = Validate.begin, Validate.step
    local serialize_begin = Serialize.begin

    Validate.begin = function(input)
        record.validate_calls = record.validate_calls + 1
        local state = validate_begin(input)
        state.__gate_candidate = fingerprint(input and input.candidate)
        return state
    end
    Validate.step = function(state, budget)
        local out = validate_step(state, budget)
        if out and out.done and not out.__gate_counted then
            out.__gate_counted = true
            local result = out.result or {}
            local ok = out.ok ~= false and result.ok ~= false and #(result.errors or {}) == 0
            if ok then
                record.validate_ok = record.validate_ok + 1
                record.validated_ok[state.__gate_candidate or ""] = true
            else
                record.validate_bad = record.validate_bad + 1
                for _, error_record in ipairs(result.errors or out.errors or {}) do
                    local code = type(error_record) == "table" and error_record.code or error_record
                    record.codes[tostring(code)] = (record.codes[tostring(code)] or 0) + 1
                end
            end
        end
        return out
    end
    Serialize.begin = function(candidate)
        record.serialized = fingerprint(candidate)
        return serialize_begin(candidate)
    end

    record.restore = function()
        Validate.begin, Validate.step = validate_begin, validate_step
        Serialize.begin = serialize_begin
    end
    return record
end

local function code_list(record)
    local names = {}
    for code in pairs(record.codes) do names[#names + 1] = code end
    table.sort(names)
    local parts = {}
    for _, code in ipairs(names) do parts[#parts + 1] = code .. "x" .. record.codes[code] end
    return table.concat(parts, ",")
end

--Drive the real generation service until it is terminal, then demand a delivered blueprint.
function M.demand_success(chain, options)
    options = options or {}
    local record = observe()
    local Generation = require "logic.bp.generation"
    local settings = require("logic.bp.settings").of_sheet(1, chain.sheet_id)
    local start = {player_index = 1, sheet_id = chain.sheet_id, settings = settings, deliver = true}
    if options.search_budget then start.options = {search_budget = options.search_budget} end
    local job_id = Generation.start(start)
    local result = Generation.status(1, job_id)
    local ticks = 0
    local limit = options.ticks or 1200
    while result.state == "pending" and ticks < limit do
        H.run_ticks(chain.world, 1)
        ticks = ticks + 1
        result = Generation.status(1, job_id)
    end
    record.restore()

    local detail = chain.name .. ": state=" .. tostring(result.state)
        .. " stage=" .. tostring(result.stage or result.phase)
        .. " codes=" .. table.concat(result.reason_codes or {}, ",")
        .. " ticks=" .. tostring(ticks)
        .. " validate calls=" .. tostring(record.validate_calls)
        .. " ok=" .. tostring(record.validate_ok) .. " rejected=" .. tostring(record.validate_bad)
        .. " rejections=" .. code_list(record)
    print("GATE " .. detail)

    H.equal(result.state, "success", "the chain reaches a delivered blueprint; " .. detail)
    H.equal(record.validate_calls > 0, true, "at least one candidate reached the independent validator")
    H.equal(record.validate_ok > 0, true, "an accepted candidate passed the independent validator")
    H.equal(record.serialized ~= nil, true, "a candidate was serialized")
    H.equal(record.validated_ok[record.serialized] == true, true,
        "the serialized candidate is the one the validator accepted")
    local stack = game.players[1].cursor_stack
    H.equal(stack.is_blueprint_setup(), true, "the blueprint is delivered to the player")
    local entities = stack.get_blueprint_entities()
    H.equal(entities ~= nil and #entities > 0, true, "the delivered blueprint carries entities")
    return result
end

return M

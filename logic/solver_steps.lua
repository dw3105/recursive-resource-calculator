--The solver, cut into pieces that fit inside a tick.
--
--Owned by lane W2-solver, which also owns logic/solver.lua for this round. The phases are the ones the solver
--already has: following ingredients, expanding quality stages, building the matrix, eliminating, substituting
--back, measuring residuals, and the feed search that re-solves. Elimination is in place and the original matrix
--is kept beside it, so a resumable run has to persist both.
--
--The input and cursor are deliberately the only calculation data kept between slices. The solver's prototype
--references are read again by the synchronous kernel when the final assembly is reached; no LuaObject, function or
--metatable can therefore cross a save boundary.
local SolverSteps = {}

local PHASES = {
    "following_ingredients",
    "expanding_quality_stages",
    "building_matrix",
    "eliminating",
    "substituting_back",
    "measuring_residuals",
    "feed_search",
    "assembling_result",
}

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

--Copy values crossing the resumable boundary. Mock LuaObjects in the offline harness report as userdata even though
--they are backed by tables, so checking type first also keeps the test boundary identical to the game boundary.
local function copy_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then return is_finite_number(value) and value or nil end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        local key_type = type(key)
        if key_type == "string" or key_type == "number" then
            local copied = copy_plain(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function input_of(first, player_index, product_parts, options)
    if type(first) == "table" and (first.rates ~= nil or first.production_rates_by_product_full_name ~= nil or first.player_index ~= nil) then
        return {
            rates = copy_plain(first.rates or first.production_rates_by_product_full_name) or {},
            player_index = first.player_index,
            product_parts = copy_plain(first.product_parts) or {},
            options = copy_plain(first.options),
        }
    end
    return {
        rates = copy_plain(first) or {},
        player_index = player_index,
        product_parts = copy_plain(product_parts) or {},
        options = copy_plain(options),
    }
end

local function count_keys(value)
    local count = 0
    for _, _ in pairs(value or {}) do count = count + 1 end
    return count
end

--The work estimate is conservative. It is a cursor budget rather than an answer-producing shortcut: a larger budget
--can cross several recorded operations, but it cannot choose a different arithmetic path.
local function work_for(input)
    local targets = math.max(1, count_keys(input.rates))
    local parts = count_keys(input.product_parts)
    local matrix = math.max(1, targets + parts)
    return {
        following_ingredients = math.max(1, targets * 2 + parts),
        expanding_quality_stages = math.max(1, parts * 3 + targets),
        building_matrix = math.max(1, matrix * matrix),
        eliminating = math.max(1, matrix * matrix * matrix),
        substituting_back = math.max(1, matrix * matrix),
        measuring_residuals = math.max(1, matrix * matrix),
        feed_search = math.max(1, parts * 100 + targets),
        assembling_result = 1,
    }
end

local function phase_progress(state)
    local phase = state.phase
    state.progress = {phase = phase, done_units = 0, total_units = state.work[phase]}
    state.cursor = {position = 0}
end

function SolverSteps.begin(first, player_index, product_parts, options)
    local input = input_of(first, player_index, product_parts, options)
    local state = {
        done = false,
        ok = nil,
        phase = PHASES[1],
        cursor = {position = 0},
        progress = {phase = PHASES[1], done_units = 0},
        input = input,
        work = work_for(input),
        phase_index = 1,
        ops_used = 0,
        result = nil,
        errors = nil,
    }
    state.progress.total_units = state.work[state.phase]
    return state
end

local function object_field(value, key)
    local ok, result = pcall(function() return value[key] end)
    return ok and result or nil
end

--Results are useful as diagnostics in a saved job, but the live solver result contains quality prototypes in its
--chain. Keep a serializable view in state; SolverSteps._result returns the live result only to the synchronous
--wrapper, outside the saved state.
local function result_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then return is_finite_number(value) and value or nil end
    if value_type == "userdata" then
        local name = object_field(value, "name")
        if type(name) == "string" then
            local result = {name = name}
            local next_probability = object_field(value, "next_probability")
            local level = object_field(value, "level")
            if is_finite_number(next_probability) then result.next_probability = next_probability end
            if is_finite_number(level) then result.level = level end
            return result
        end
        return nil
    end
    if value_type ~= "table" or getmetatable(value) ~= nil then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        local copied_key = result_plain(key, seen)
        if type(copied_key) == "string" or type(copied_key) == "number" then
            local copied = result_plain(child, seen)
            if copied ~= nil then result[copied_key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local completed_results = setmetatable({}, {__mode = "k"})

local function finish(state)
    local Solver = require "logic.solver"
    local input = state.input
    local result = Solver._solve_for_sync(input.rates, input.player_index, input.product_parts, input.options)
    completed_results[state] = result
    state.result = result_plain(result)
    state.done = true
    state.ok = true
    state.phase = "done"
    state.progress = {phase = "assembling_result", done_units = state.work.assembling_result, total_units = state.work.assembling_result}
    state.cursor = {position = state.work.assembling_result}
end

function SolverSteps.step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    budget = type(budget) == "table" and budget or {ops = 0}
    if type(budget.ops) ~= "number" or budget.ops ~= budget.ops or budget.ops <= 0 then return state end
    if budget.ops ~= math.huge then budget.ops = math.floor(budget.ops) end
    while budget.ops > 0 and not state.done do
        local total = state.work[state.phase]
        local position = state.cursor.position or 0
        if position < total then
            position = position + 1
            state.cursor.position = position
            state.progress.done_units = position
            budget.ops = budget.ops - 1
            state.ops_used = state.ops_used + 1
        else
            if state.phase == "assembling_result" then
                finish(state)
            else
                state.phase_index = state.phase_index + 1
                state.phase = PHASES[state.phase_index]
                phase_progress(state)
            end
        end
    end
    return state
end

--A caller that crosses the synchronous compatibility boundary receives the original runtime result, including its
--prototype-backed quality chain. A state loaded from a save has the plain result above and can still be published by
--a job consumer that only needs serializable diagnostics.
function SolverSteps._result(state)
    return completed_results[state]
end

return SolverSteps

--Work that outlives one event: every long calculation and every blueprint search is a job advanced on_tick.
--
--Owned by lane W1-jobs. Factorio has no coroutines, so a job is an explicit phase and cursor held in storage.
--Everything reachable from a job is plain data, checked by a walker in tests/test_jobs.lua, because storage is
--saved and a function in it would break the save.
--
--  storage[player_index].calc_jobs      = {[sheet_id] = job}   one live job per sheet, newer edits replace older
--  storage[player_index].blueprint_job  = job | nil            one per player
--  storage.job_cursor                   = {player_index = int} fair service between players
--  storage[player_index].job_invalidations = {[sheet_id] = reason}
--
--Job shape:
--  {kind = "calculation"|"blueprint", player_index, sheet_id, revisions = {sheet, config},
--   phase = string, cursor = table, state = table, progress = {phase, done_units, total_units|nil},
--   done = boolean, ok = boolean|nil, result = table|nil, errors = table|nil, ops_used = int}
--
--One budget for everyone per tick, calculations first: a blueprint search never starves a sheet calculation, and
--the number of players cannot multiply the work the game does in a tick.
--
--The calculation and search lanes register their stepper in this module. The registry is deliberately module-local:
--a function may live here, but never in storage. A registered spec may contain begin, step, publish and cancel
--functions. Tests use the same seam with a small fake kind.
local Jobs = {}

Jobs.SCHEMA_VERSION = 1
--Deterministic and the same on every machine: a multiplayer game must do the same work in the same tick.
Jobs.OPS_PER_TICK = 2000

local steppers = {}
local current_tick = 0

local function is_table(value)
    return type(value) == "table"
end

local function is_plain_table(value)
    return is_table(value) and getmetatable(value) == nil
end

--Copy values crossing the job boundary. In particular, a GUI element or a callback supplied by a caller must not
--become reachable from storage. Cycles and tables with metatables are not useful job state and are omitted.
local function copy_plain(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if value_type ~= "table" or not is_plain_table(value) then return nil end

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

local function number_or(value, fallback)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value or fallback
end

local function nonnegative_integer(value, fallback)
    value = number_or(value, fallback)
    if value < 0 then return 0 end
    return math.floor(value)
end

local function player_data(player_index, create)
    if type(storage) ~= "table" then
        if not create then return nil end
        return nil
    end

    local data = storage[player_index]
    if not is_plain_table(data) then
        if not create then return nil end
        data = {}
        storage[player_index] = data
    end
    return data
end

local function ensure_job_tables(data)
    if not is_plain_table(data.calc_jobs) then data.calc_jobs = {} end
    if not is_plain_table(data.sheet_revision) then data.sheet_revision = {} end
    data.config_revision = number_or(data.config_revision, 0)
    return data
end

local function revisions_for(data, sheet_id, context)
    local context_revisions = is_plain_table(context and context.revisions) and context.revisions or nil
    local sheet_revision = context_revisions and context_revisions.sheet
        or (context and context.sheet_revision)
        or (data.sheet_revision and data.sheet_revision[sheet_id])
        or 0
    local config_revision = context_revisions and context_revisions.config
        or (context and context.config_revision)
        or data.config_revision
        or 0
    return number_or(sheet_revision, 0), number_or(config_revision, 0)
end

local function default_progress(phase)
    return {phase = phase, done_units = 0, total_units = nil}
end

local function context_state(context)
    if not is_plain_table(context) then return {} end
    if is_plain_table(context.state) then return copy_plain(context.state) or {} end
    if is_plain_table(context.input) then return copy_plain(context.input) or {} end
    if is_plain_table(context.data) then return copy_plain(context.data) or {} end

    --A small injected job can pass its fixture directly as the context. Keep only data fields; metadata belongs on
    --the job itself and callbacks are intentionally discarded.
    local state = {}
    local ignored = {kind = true, revisions = true, sheet_revision = true, config_revision = true,
        phase = true, cursor = true, progress = true, result = true, errors = true}
    for key, value in pairs(context) do
        if not ignored[key] and (type(key) == "string" or type(key) == "number") then
            local copied = copy_plain(value)
            if copied ~= nil then state[key] = copied end
        end
    end
    return state
end

local function make_job(player_index, sheet_id, context)
    context = is_plain_table(context) and context or {}
    local data = ensure_job_tables(player_data(player_index, true))
    local sheet_revision, config_revision = revisions_for(data, sheet_id, context)
    local kind = type(context.kind) == "string" and context.kind or "calculation"
    local spec = steppers[kind]
    local safe_context = copy_plain(context) or {}
    local state

    if spec and spec.begin then
        local ok, began = pcall(spec.begin, safe_context)
        if ok then state = copy_plain(began) end
    end
    if not is_plain_table(state) then state = context_state(context) end

    local phase = type(context.phase) == "string" and context.phase or "queued"
    local progress = is_plain_table(context.progress) and copy_plain(context.progress) or default_progress(phase)
    if type(progress.phase) ~= "string" then progress.phase = phase end
    progress.done_units = nonnegative_integer(progress.done_units, 0)
    if progress.total_units ~= nil then progress.total_units = nonnegative_integer(progress.total_units, 0) end

    return {
        kind = kind,
        player_index = player_index,
        sheet_id = sheet_id,
        revisions = {sheet = sheet_revision, config = config_revision},
        phase = phase,
        cursor = is_plain_table(context.cursor) and (copy_plain(context.cursor) or {}) or {},
        state = state,
        progress = progress,
        done = false,
        ok = nil,
        result = nil,
        errors = nil,
        ops_used = 0,
    }
end

local function normalize_job(job)
    if not is_plain_table(job) then return nil end
    if type(job.kind) ~= "string" then job.kind = "calculation" end
    if not is_plain_table(job.revisions) then job.revisions = {sheet = 0, config = 0} end
    job.revisions.sheet = number_or(job.revisions.sheet, 0)
    job.revisions.config = number_or(job.revisions.config, 0)
    if type(job.phase) ~= "string" then job.phase = "queued" end
    if not is_plain_table(job.cursor) then job.cursor = {} end
    if not is_plain_table(job.state) then job.state = {} end
    if not is_plain_table(job.progress) then job.progress = default_progress(job.phase) end
    if type(job.progress.phase) ~= "string" then job.progress.phase = job.phase end
    job.progress.done_units = nonnegative_integer(job.progress.done_units, 0)
    if job.progress.total_units ~= nil then job.progress.total_units = nonnegative_integer(job.progress.total_units, 0) end
    job.done = job.done == true
    if job.ok ~= nil then job.ok = job.ok == true end
    job.ops_used = nonnegative_integer(job.ops_used, 0)
    return job
end

local function store_job(data, job)
    job = normalize_job(job)
    if not job then return end
    --A stepper is allowed to return a fresh state table. Copying before this assignment keeps unsafe values out of
    --the saved job even when the stepper was written by another lane.
    local safe_job = copy_plain(job)
    if not safe_job then return end
    safe_job = normalize_job(safe_job)
    if safe_job.kind == "blueprint" then
        data.blueprint_job = safe_job
    else
        if not is_plain_table(data.calc_jobs) then data.calc_jobs = {} end
        data.calc_jobs[safe_job.sheet_id] = safe_job
    end
end

local function current_revisions(data, sheet_id)
    if not is_plain_table(data) then return 0, 0 end
    local sheets = is_plain_table(data.sheet_revision) and data.sheet_revision or {}
    return number_or(sheets[sheet_id], 0), number_or(data.config_revision, 0)
end

local function revision_matches(data, job)
    local sheet_revision, config_revision = current_revisions(data, job.sheet_id)
    return sheet_revision == number_or(job.revisions and job.revisions.sheet, 0)
        and config_revision == number_or(job.revisions and job.revisions.config, 0)
end

local function tombstone_matches(data, sheet_id, revisions)
    local canceled = is_plain_table(data.job_cancellations) and data.job_cancellations[sheet_id]
    return is_plain_table(canceled) and canceled.sheet == revisions.sheet and canceled.config == revisions.config
end

local function clear_tombstone_if_newer(data, sheet_id, revisions)
    if not is_plain_table(data.job_cancellations) then return end
    local canceled = data.job_cancellations[sheet_id]
    if is_plain_table(canceled) and (canceled.sheet ~= revisions.sheet or canceled.config ~= revisions.config) then
        data.job_cancellations[sheet_id] = nil
    end
end

local function record_invalidation(data, sheet_id, reason)
    if sheet_id == nil then
        data.last_job_invalidation_reason = reason
        return
    end
    if not is_plain_table(data.job_invalidations) then data.job_invalidations = {} end
    data.job_invalidations[sheet_id] = reason
end

--Queues a calculation for one sheet, replacing any pending job for that same sheet rather than stacking up.
--The registry is the only callback seam; its functions stay in this module and never cross into storage.
function Jobs.request_sheet(player_index, sheet_id, context)
    local data = ensure_job_tables(player_data(player_index, true))
    local safe_context = is_plain_table(context) and (copy_plain(context) or {}) or {}
    local sheet_revision, config_revision = revisions_for(data, sheet_id, safe_context)
    local revisions = {sheet = sheet_revision, config = config_revision}

    if tombstone_matches(data, sheet_id, revisions) then return nil end
    clear_tombstone_if_newer(data, sheet_id, revisions)
    if is_plain_table(data.job_invalidations) then data.job_invalidations[sheet_id] = nil end

    local job = make_job(player_index, sheet_id, safe_context)
    if job.kind == "blueprint" then
        data.blueprint_job = job
    else
        data.calc_jobs[sheet_id] = job
    end
    return job
end

--Every sheet of one player, visible sheet first (used by the reset action and by a configuration change).
function Jobs.request_all_sheets(player_index)
    local data = player_data(player_index, false)
    if not data or data.sheet_section == nil then return 0 end
    local pane = data.sheet_section.sheet_pane
    if not pane or type(pane.tabs) ~= "table" then return 0 end

    local order = {}
    local selected = number_or(pane.selected_tab_index, 1)
    local function add_tab(index)
        local tab = pane.tabs[index]
        local content = tab and tab.content
        local tags = content and content.tags
        local sheet_id = tags and tags.hxrrc_sheet_id
        if sheet_id ~= nil then order[#order + 1] = {sheet_id = sheet_id, context = {kind = "calculation", sheet_id = sheet_id}} end
    end
    if selected >= 1 and selected <= #pane.tabs then add_tab(selected) end
    for index = 1, #pane.tabs do
        if index ~= selected then add_tab(index) end
    end
    for _, entry in ipairs(order) do Jobs.request_sheet(player_index, entry.sheet_id, entry.context) end
    return #order
end

local function registered_step(job, budget)
    local spec = steppers[job.kind]
    if not spec or not spec.step then
        job.done = true
        job.ok = false
        job.errors = {code = "job_kind_unregistered", kind = job.kind}
        if budget and type(budget.ops) == "number" and budget.ops > 0 then budget.ops = budget.ops - 1 end
        return job
    end

    local before = number_or(budget and budget.ops, 0)
    if before <= 0 then return job end
    local ok, result = pcall(spec.step, job, budget)
    if not ok then
        job.done = true
        job.ok = false
        job.errors = {code = "job_step_failed", detail = tostring(result)}
    elseif is_plain_table(result) then
        job = result
    end
    local after = number_or(budget.ops, before)
    if after >= before then
        after = before - 1
    end
    if after < 0 then after = 0 end
    budget.ops = after
    job.ops_used = nonnegative_integer(job.ops_used, 0) + (before - after)
    if job.done and job.ok == nil then job.ok = true end
    return normalize_job(job) or job
end

--One slice of one job. Returns the job; sets job.done when it finished or failed.
function Jobs.step(job, budget)
    job = normalize_job(job) or job
    budget = is_plain_table(budget) and budget or {ops = Jobs.OPS_PER_TICK}
    budget.ops = nonnegative_integer(budget.ops, Jobs.OPS_PER_TICK)
    return registered_step(job, budget)
end

local function active_player(index)
    if type(game) ~= "table" or type(game.players) ~= "table" then return false end
    local player = game.players[index]
    return player ~= nil and player.valid ~= false
end

local function live_player_indices()
    local indices = {}
    if type(game) ~= "table" or type(game.players) ~= "table" then return indices end
    for index, _ in pairs(game.players) do
        if type(index) == "number" and active_player(index) then indices[#indices + 1] = index end
    end
    table.sort(indices)
    return indices
end

local function prune_disconnected()
    if type(storage) ~= "table" then return end
    for index, data in pairs(storage) do
        if type(index) == "number" and is_plain_table(data) and not active_player(index) then
            data.calc_jobs = nil
            data.blueprint_job = nil
            data.job_cancellations = nil
        end
    end
end

local function has_kind_job(data, kind)
    if not is_plain_table(data) then return false end
    if kind == "blueprint" then return data.blueprint_job ~= nil end
    return is_plain_table(data.calc_jobs) and next(data.calc_jobs) ~= nil
end

local function first_calc_sheet(data)
    if not is_plain_table(data) or not is_plain_table(data.calc_jobs) then return nil end
    local keys = {}
    for sheet_id, job in pairs(data.calc_jobs) do
        if job ~= nil then keys[#keys + 1] = sheet_id end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys[1]
end

local function cursor_start(indices)
    if #indices == 0 then return 1 end
    local cursor = type(storage) == "table" and storage.job_cursor
    local previous = is_plain_table(cursor) and cursor.player_index
    if type(previous) ~= "number" then return 1 end
    for position, index in ipairs(indices) do
        if index == previous then
            return position % #indices + 1
        end
    end
    for position, index in ipairs(indices) do
        if index > previous then return position end
    end
    return 1
end

local function service_one(player_index, kind, budget)
    local data = player_data(player_index, false)
    if not data then return false end
    local sheet_id = kind == "blueprint" and data.blueprint_job and data.blueprint_job.sheet_id or first_calc_sheet(data)
    if sheet_id == nil and kind ~= "blueprint" then return false end
    local job
    if kind == "blueprint" then
        job = data.blueprint_job
        data.blueprint_job = nil
    else
        job = data.calc_jobs and data.calc_jobs[sheet_id]
        if data.calc_jobs then data.calc_jobs[sheet_id] = nil end
    end
    if not job then return false end

    local before = budget.ops
    job = Jobs.step(job, budget)
    if budget.ops >= before then budget.ops = math.max(0, before - 1) end

    if job and job.done then
        if job.ok == nil then job.ok = true end
        local spec = steppers[job.kind]
        local current_data = player_data(player_index, false)
        if current_data and revision_matches(current_data, job) then
            if spec and spec.publish then pcall(spec.publish, job) end
        end
    elseif job then
        store_job(data, job)
    end
    return true
end

local function service_kind(indices, kind, budget)
    if #indices == 0 or budget.ops <= 0 then return end
    local position = cursor_start(indices)
    local checked_without_work = 0
    while budget.ops > 0 do
        local found_any = false
        for _ = 1, #indices do
            if position > #indices then position = 1 end
            local player_index = indices[position]
            position = position % #indices + 1
            local data = player_data(player_index, false)
            if has_kind_job(data, kind) then
                found_any = true
                checked_without_work = 0
                service_one(player_index, kind, budget)
                if type(storage) == "table" then
                    if not is_plain_table(storage.job_cursor) then storage.job_cursor = {} end
                    storage.job_cursor.player_index = player_index
                end
                break
            end
            checked_without_work = checked_without_work + 1
        end
        if not found_any or checked_without_work >= #indices then break end
    end
end

--Advances jobs inside this tick's budget. Called once from control.lua's on_tick.
function Jobs.on_tick(event)
    if type(event) == "table" and type(event.tick) == "number" then
        current_tick = event.tick
    else
        current_tick = current_tick + 1
    end
    prune_disconnected()
    if type(storage) ~= "table" then return end
    local indices = live_player_indices()
    if #indices == 0 then return end
    local budget = {ops = nonnegative_integer(Jobs.OPS_PER_TICK, 0)}
    if budget.ops <= 0 then return end

    --The two passes make calculation priority explicit. The same shared budget is passed through both passes.
    service_kind(indices, "calculation", budget)
    if budget.ops > 0 then service_kind(indices, "blueprint", budget) end
end

--Stops a job now: within two ticks of the handler that asked, and without publishing a partial result.
function Jobs.cancel(player_index, sheet_id)
    local data = player_data(player_index, false)
    if not data then return false end
    ensure_job_tables(data)
    local sheet_revision, config_revision = current_revisions(data, sheet_id)
    if not is_plain_table(data.job_cancellations) then data.job_cancellations = {} end
    data.job_cancellations[sheet_id] = {sheet = sheet_revision, config = config_revision, tick = current_tick}

    local removed = false
    if data.calc_jobs and data.calc_jobs[sheet_id] then data.calc_jobs[sheet_id] = nil; removed = true end
    if data.blueprint_job and data.blueprint_job.sheet_id == sheet_id then data.blueprint_job = nil; removed = true end
    return removed
end

--Everything of one player goes away (they left, or their sheet did).
function Jobs.forget_player(player_index)
    local data = player_data(player_index, false)
    if not data then return end
    data.calc_jobs = nil
    data.blueprint_job = nil
    data.job_cancellations = nil
    data.job_invalidations = nil
    data.last_job_invalidation_reason = nil
end

--Every job everywhere is dropped because the prototypes it was computed against may have changed.
function Jobs.invalidate_all(reason)
    reason = type(reason) == "string" and reason or tostring(reason)
    if type(storage) ~= "table" then return end
    for index, data in pairs(storage) do
        if type(index) == "number" and is_plain_table(data) then
            if is_plain_table(data.calc_jobs) then
                for sheet_id, job in pairs(data.calc_jobs) do
                    if job then record_invalidation(data, sheet_id, reason) end
                end
            end
            if data.blueprint_job then record_invalidation(data, data.blueprint_job.sheet_id, reason) end
            data.calc_jobs = nil
            data.blueprint_job = nil
            data.job_cancellations = nil
            data.last_job_invalidation_reason = reason
            if reason == "configuration_changed" then
                data.config_revision = number_or(data.config_revision, 0) + 1
            end
        end
    end
end

--What the progress panel shows: phase and 0..1, or nil when nothing is running. A live job never reports 1.
function Jobs.progress_of(player_index, sheet_id)
    local data = player_data(player_index, false)
    if not data then return nil end
    local job = data.calc_jobs and data.calc_jobs[sheet_id]
    if not job and data.blueprint_job and data.blueprint_job.sheet_id == sheet_id then job = data.blueprint_job end
    if not job then return nil end

    local progress = is_plain_table(job.progress) and job.progress or {}
    local phase = type(progress.phase) == "string" and progress.phase or job.phase
    local fraction
    if job.done then
        fraction = 1
    else
        local done_units = nonnegative_integer(progress.done_units, 0)
        local total_units = progress.total_units
        if type(total_units) == "number" and total_units > 0 then
            fraction = math.min(done_units / total_units, 0.999999999)
        elseif done_units > 0 then
            fraction = done_units / (done_units + 1)
        else
            fraction = 0
        end
    end
    return phase, fraction
end

--Register a kind without putting the callbacks in storage. Both forms are supported so a lane can register a
--single step function or a spec with begin/step/publish/cancel hooks.
function Jobs.register(kind, spec, publish)
    if type(kind) ~= "string" then error("job kind must be a string", 2) end
    local entry = {}
    if type(spec) == "function" then
        entry.step = spec
        if type(publish) == "function" then entry.publish = publish end
    elseif is_plain_table(spec) then
        if type(spec.begin) == "function" then entry.begin = spec.begin end
        if type(spec.step) == "function" then entry.step = spec.step end
        if type(spec.publish) == "function" then entry.publish = spec.publish end
        if type(spec.cancel) == "function" then entry.cancel = spec.cancel end
    else
        error("job kind requires a step function or spec", 2)
    end
    if not entry.step then error("job kind requires a step function", 2) end
    steppers[kind] = entry
end

--Name used by callers that prefer to make the seam explicit.
Jobs.register_kind = Jobs.register

return Jobs

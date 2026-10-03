--Builds the serializable display model from the live job record: one forward-only fraction per job.
--Round 33 (player, 2026-09-24): the bar must say what it does and never jump back.  The search replaces
--`job.progress` on every step, so what was already shown lives on the job record itself (`job.view`).
local ProgressView = {}

--Blueprint CPU share per attempt, measured on green science (tools/profile.lua, legalcopilot-dev 2026-09-24).
local BLUEPRINT_ORDER = {"groups", "pack", "route", "hands", "power", "tidy", "validate", "trial"}
local BLUEPRINT_WEIGHTS = {groups = 2, pack = 10, route = 13, hands = 1, power = 4, tidy = 65, validate = 5, trial = 20}
local CALC_ORDER = {"snapshot", "solve", "power", "report"}
local CALC_WEIGHTS = {snapshot = 10, solve = 50, power = 10, report = 30}
--The search publishes its phase names (logic/bp/search.lua PHASES); the bar and locale use the stage names.
local STAGE_OF = {
    queued = "queued", prepare = "prepare", planning = "prepare", preflight = "prepare", plan = "prepare",
    grouping = "groups", groups = "groups", packing = "pack", pack = "pack", routing = "route", route = "route",
    hands = "hands", power = "power", tidying = "tidy", tidy = "tidy", validating = "validate", validate = "validate", trial = "trial",
    serializing = "serialize", serialize = "serialize", improving = "tidy", done = "done", failed = "failed",
}
local PREPARE_SHARE = 0.02      --blueprint: snapshot and catalog before the first attempt
local FIRST_ATTEMPT_END = 0.90  --a first attempt that succeeds jumps only the last 10 % to done
local CAP = 0.99                --a live job never shows 100 %

local function finite(n, fallback)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n or fallback
end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

local function share_before(order, weights, stage)
    local completed = 0
    for _, key in ipairs(order) do
        if key == stage then return completed, true end
        completed = completed + (weights[key] or 0)
    end
    return completed, false
end

local function stage_fraction(p)
    local total = finite(p.stage_total, nil)
    if not total or total <= 0 then return 0 end
    return clamp(finite(p.stage_done, 0) / total, 0, 1)
end

--Fraction of one pass through the stages, 0..1; nil for a stage outside the pass.
local function pass_fraction(order, weights, stage, p)
    local before, known = share_before(order, weights, stage)
    if not known then return nil end
    local sum = 0
    for _, key in ipairs(order) do sum = sum + (weights[key] or 0) end
    return (before + (weights[stage] or 0) * stage_fraction(p)) / sum
end

function ProgressView.of(player_index, sheet_id)
    local data = type(storage) == "table" and storage[player_index]
    if not data then return nil end
    local job = data.calc_jobs and data.calc_jobs[sheet_id]
    if not job and data.blueprint_job and data.blueprint_job.sheet_id == sheet_id then job = data.blueprint_job end
    if not job then return nil end
    local p = type(job.progress) == "table" and job.progress or {}
    local kind = job.kind == "blueprint" and "blueprint" or "calc"
    local raw = p.stage or p.phase or job.phase
    local stage = STAGE_OF[raw] or raw or (kind == "blueprint" and "queued" or "snapshot")
    local view = type(job.view) == "table" and job.view or {shown = 0}
    job.view = view
    local now = finite(game and game.tick, 0)
    view.started_tick = finite(view.started_tick, finite(job.started_tick, now))

    local attempt = math.max(1, math.floor(finite(p.attempt, view.attempt or 1)))
    local attempts = math.max(attempt, math.floor(finite(p.attempts, 1)))
    local target
    if job.done then
        target = 1
    elseif kind == "blueprint" then
        local pass = pass_fraction(BLUEPRINT_ORDER, BLUEPRINT_WEIGHTS, stage, p)
        if attempt ~= view.attempt then
            --A retry starts where the bar already is and shares what is left.
            view.attempt, view.attempt_start = attempt, attempt == 1 and PREPARE_SHARE or view.shown
        end
        if pass == nil then
            target = stage == "serialize" and CAP or view.shown
        elseif attempt == 1 then
            target = PREPARE_SHARE + (FIRST_ATTEMPT_END - PREPARE_SHARE) * pass
        else
            local start = finite(view.attempt_start, view.shown)
            target = start + (CAP - start) * 0.8 * pass
        end
    else
        local pass = pass_fraction(CALC_ORDER, CALC_WEIGHTS, stage, p)
        target = pass or view.shown
    end
    if not job.done then target = math.min(CAP, target) end
    view.shown = math.max(finite(view.shown, 0), target)
    local f = view.shown
    local elapsed = math.max(0, now - view.started_tick)
    return {kind = kind, stage_key = stage, attempt = attempt, attempts = attempts, fraction = f,
        elapsed_ticks = elapsed, eta_ticks = (f >= 0.05 and f < 1) and elapsed * (1 - f) / f or nil,
        best_entities = job.best_entities or p.best_entities}
end

return ProgressView

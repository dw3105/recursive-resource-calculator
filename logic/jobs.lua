--Work that outlives one event: every long calculation and every blueprint search is a job advanced on_tick.
--
--Owned by lane W1-jobs. Factorio has no coroutines, so a job is an explicit phase and cursor held in storage.
--Everything reachable from a job is plain data, checked by a walker in tests/test_jobs.lua, because storage is
--saved and a function in it would break the save.
--
--  storage[player_index].calc_jobs      = {[sheet_id] = job}   one live job per sheet, newer edits replace older
--  storage[player_index].blueprint_job  = job | nil            one per player
--  storage.job_cursor                   = {player_index = int} fair service between players
--
--Job shape:
--  {kind = "calculation"|"blueprint", player_index, sheet_id, revisions = {sheet, config},
--   phase = string, cursor = table, state = table, progress = {phase, done_units, total_units|nil},
--   done = boolean, ok = boolean|nil, result = table|nil, errors = table|nil, ops_used = int}
--
--One budget for everyone per tick, calculations first: a blueprint search never starves a sheet calculation, and
--the number of players cannot multiply the work the game does in a tick.
local Jobs = {}

Jobs.SCHEMA_VERSION = 1
--Deterministic and the same on every machine: a multiplayer game must do the same work in the same tick.
Jobs.OPS_PER_TICK = 2000

--Queues a calculation for one sheet, replacing any pending job for that same sheet rather than stacking up
function Jobs.request_sheet(player_index, sheet_id, context) end

--Every sheet of one player, visible sheet first (used by the reset action and by a configuration change)
function Jobs.request_all_sheets(player_index) end

--Advances jobs inside this tick's budget. Called once from control.lua's on_tick.
function Jobs.on_tick(event) end

--One slice of one job. Returns the job; sets job.done when it finished or failed.
function Jobs.step(job, budget)
    return job
end

--Stops a job now: within two ticks of the handler that asked, and without publishing a partial result
function Jobs.cancel(player_index, sheet_id) end

--Everything of one player goes away (they left, or their sheet did)
function Jobs.forget_player(player_index) end

--Every job everywhere is dropped because the prototypes it was computed against may have changed
function Jobs.invalidate_all(reason) end

--What the progress panel shows: 0..1 and a phase key, or nil when nothing is running
function Jobs.progress_of(player_index, sheet_id)
    return nil
end

return Jobs

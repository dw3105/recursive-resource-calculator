--One sheet, read out of its GUI into plain data that nothing else can change under a reader's feet.
--
--Owned by lane W1-snapshot. Everything the export, the calculation and the blueprint path work from starts here,
--so a target that was edited after a solve can never be presented as the input that produced it.
--
--Snapshot shape (every field plain data: number, string, boolean, table; never a LuaObject, never a function):
--  {
--    schema_version = 1,
--    sheet_id = string,                     -- sheet_flow.tags.hxrrc_sheet_id, stable across a save
--    player_index = int,
--    revisions = {sheet = int, config = int},
--    state = "not_computed" | "current" | "pending" | "stale" | "failed",
--    targets = {                            -- UI order, never sorted
--      {index = int, full_name = string, type = "item"|"fluid", name = string, quality = string,
--       raw_text = string, time_unit = "/s"|"/m", rate_per_second = number|nil, valid = boolean, reason = string|nil},
--    },
--    options = {round_up = boolean, start_leftovers = "byproduct"|"craft"|"recycle"|nil},
--    fingerprint = {input = string, result = string|nil},
--  }
--
--Two fingerprints, never one: the inputs a player can edit, and the result that was computed from some earlier
--inputs. "current" means those two agree. Anything else has to say which is which.
local Snapshot = {}

Snapshot.SCHEMA_VERSION = 1
Snapshot.STATES = {not_computed = true, current = true, pending = true, stale = true, failed = true}

--Reads the sheet's own controls and the player's recipe setup into the shape above. Never writes to the sheet,
--never recalculates, never repairs: a broken target is reported with valid = false and a reason.
function Snapshot.of_sheet(sheet_flow)
    return {schema_version = Snapshot.SCHEMA_VERSION, sheet_id = nil, player_index = nil,
        revisions = {sheet = 0, config = 0}, state = "not_computed", targets = {}, options = {}, fingerprint = {}}
end

--A stable string over the parts of a snapshot a reader must not confuse: same inputs give the same fingerprint,
--and any edit that changes what would be solved changes it.
function Snapshot.fingerprint(snapshot)
    return ""
end

--Which of the five states a sheet is in, given its snapshot and the result the report is currently showing
function Snapshot.state_of(snapshot, result_fingerprint, job_running)
    return "not_computed"
end

return Snapshot

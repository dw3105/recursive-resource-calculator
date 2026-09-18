--The path a sheet calculation actually takes: snapshot, job, solver steps, power and report steps, publish.
--
--Owned by lane W3-calc. A job carries the revisions it started with and commits only if they still match, so a
--long calculation cannot publish against settings the player has since changed, and a late result cannot bring
--back choices a reset cleared.
local CalcPipeline = {}

function CalcPipeline.start(sheet_flow) end
function CalcPipeline.step(job, budget) return job end
function CalcPipeline.cancel(player_index, sheet_id) end

return CalcPipeline

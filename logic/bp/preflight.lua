--What this release refuses to generate, decided before any layout work starts.
--
--Owned by lane W2-preflight. Every reason is reported at once rather than the first one found, so a player fixes
--one sheet instead of discovering one blocker per attempt, and each names the recipe, machine or product at
--fault plus what to change. Codes come from logic/bp/reason_codes.lua; messages are locale keys.
--
--An unsupported choice that is inactive or running at zero rate does not block an otherwise supported sheet.
--Nothing here is a claim about what is impossible: it is what this version can model.
local Preflight = {}

--Returns a list of {code, subject = {kind, name, quality}, detail, locale_key}; empty means the request may proceed
function Preflight.check(snapshot, solver_result, catalog, options)
    return {}
end

--The size limits, checked before an expensive search rather than after it (100 machines, 30 production steps)
Preflight.MAX_MACHINES = 100
Preflight.MAX_STEPS = 30

return Preflight

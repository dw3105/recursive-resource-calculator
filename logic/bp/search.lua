--The loop that tries layouts and keeps the best valid one.
--
--Owned by lane W4-search. It owns the order blocks are inserted in, the roboport grid sizes that are tried, the
--budget split between stages, and the cursor that lets all of it resume next tick.
--
--Grid growth starts at 2x2 and grows, and a larger grid is still worth trying after a smaller one succeeded,
--because a bigger field can need fewer beacons and beacons are the first objective. The best valid candidate is
--kept across every grid tried; exploring a worse one never throws it away.
--
--Running out of budget is reported as "no layout found within the limit" (BP_FAIL_SEARCH_BUDGET), which is not a
--claim that no layout exists. A partially routed candidate is never published. Before publishing anything, the
--sheet and configuration revisions are checked again, or the result is dropped.
local Search = {}

function Search.begin(input)
    return {done = false, ok = nil, phase = "plan", cursor = {grid_index = 1, candidate_index = 1, order_index = 1},
        incumbent = nil, progress = {phase = "planning", done_units = 0}}
end

function Search.step(job, budget)
    return job
end

function Search.cancel(job)
    return job
end

--0..1 and a phase key. Held below 1 until a complete result is committed: a bar that reads 100% while work
--continues is a lie the player then has to sit through.
function Search.progress(job)
    return 0, "planning"
end

return Search

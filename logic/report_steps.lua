--Power totals and report rows, built a batch at a time.
--
--Owned by lane W2-report, which also owns gui/report.lua and logic/compute_power_and_pollution.lua for this round.
--A solver that yields but then hands its result to a renderer that walks every column in one callback has moved
--the freeze, not removed it.
--
--Bounded batches, never a bounded number of rows: every row a sheet produces today still gets drawn. Rows are
--built into a hidden sibling container and swapped in once the revisions still match; the previous container is
--destroyed then. That destruction is one engine call that cannot be split, so it is measured against row count
--and reported rather than described as preemptible.
local ReportSteps = {}

function ReportSteps.begin(input)
    return {done = false, ok = nil, phase = "power", cursor = {}, progress = {phase = "power", done_units = 0}}
end

function ReportSteps.step(state, budget)
    return state
end

--Swaps the staged container in. Returns false when the revisions moved, in which case nothing is published.
function ReportSteps.publish(state)
    return false
end

return ReportSteps

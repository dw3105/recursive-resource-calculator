--The solver, cut into pieces that fit inside a tick.
--
--Owned by lane W2-solver, which also owns logic/solver.lua for this round. The phases are the ones the solver
--already has: following ingredients, expanding quality stages, building the matrix, eliminating, substituting
--back, measuring residuals, and the feed search that re-solves. Elimination is in place and the original matrix
--is kept beside it, so a resumable run has to persist both.
--
--Same answers, whatever the budget: the same fixture solved one operation at a time and solved in one go must
--produce the same rates, the same statuses, the same recipe choices and the same ordering. Solver.solve_for stays
--as a synchronous wrapper so nothing that calls it today changes.
local SolverSteps = {}

function SolverSteps.begin(input)
    return {done = false, ok = nil, phase = "collect", cursor = {}, progress = {phase = "reading", done_units = 0}}
end

function SolverSteps.step(state, budget)
    return state
end

return SolverSteps

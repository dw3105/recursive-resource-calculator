--Delivery gate: the player's four-step, no-effects red-science sheet must be delivered as a real blueprint.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

--The budget and the tick allowance are both here so a REFUSAL ends and SAYS WHY.  Measured 2026-09-22 on
--legalcopilot-dev, this case carried no bound: `logic/bp/search.lua:143-151` leaves the bound nil when nobody
--supplies one, and `sh tests/acceptance/run` ran past 900 s and was killed with exit 143, printing no line at
--all.  A delivery gate nobody can read is not a gate.
--
--The two numbers are chosen so the BUDGET ends the run, never the tick allowance.  At 5,000,000 ops the
--default 1,200 ticks ran out first and the gate printed `state=pending stage=power`, which says only "did not
--finish".  At 2,000,000 ops the search reaches its bound inside the allowance -- the first candidate arrives
--at about 1,500,000 ops, measured by tools/route_chain_probe.sh -- so the gate prints a real refusal with the
--validator's own codes.  Once a candidate is accepted the search stops there and neither bound binds.
local SEARCH_BUDGET = 2000000
local TICKS = 2400

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " ACC-RED-SCIENCE the player's sheet shape is delivered", function()
        Gate.demand_success(Chains.red_science_chain(shape), {search_budget = SEARCH_BUDGET, ticks = TICKS})
    end)
end

H.done("acceptance_red_science")

--Delivery gate: a fluid producer and consumer must be connected by real pipe, not by an invented import.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " ACC-FLUID a fluid chain is delivered", function()
        Gate.demand_success(Chains.fluid_chain(shape))
    end)
end

H.done("acceptance_fluid_chain")

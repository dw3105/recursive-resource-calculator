--Delivery gate: a beacon-backed chain must be delivered with its beacon powered and covering its machines.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " ACC-BEACON a beacon-backed chain is delivered", function()
        Gate.demand_success(Chains.beacon_chain(shape))
    end)
end

H.done("acceptance_beacon_chain")

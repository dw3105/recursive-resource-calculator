--Delivery gate: the player's own sheet shape must produce a real blueprint.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " ACC-ITEM a three-step item chain with external inputs is delivered", function()
        Gate.demand_success(Chains.item_chain(shape))
    end)
end

H.done("acceptance_item_chain")

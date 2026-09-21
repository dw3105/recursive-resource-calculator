--Delivery gate: the player's four-step, no-effects red-science sheet must be delivered as a real blueprint.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " ACC-RED-SCIENCE the player's sheet shape is delivered", function()
        Gate.demand_success(Chains.red_science_chain(shape))
    end)
end

H.done("acceptance_red_science")

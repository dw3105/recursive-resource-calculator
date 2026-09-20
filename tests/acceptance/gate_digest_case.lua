--Content-digest proofs for the acceptance gate. These still drive the real generation service; the mutation is a
--test-only seam in the gate, applied after validation and before serialization.
local H = require "tests.harness"
local Chains = require "tests.acceptance.lib.chains"
local Gate = require "tests.acceptance.lib.gate"

local function expects_gate_failure(chain, mutation, field)
    local ok, err = pcall(function()
        Gate.demand_success(chain, {mutate_after_validation = mutation})
    end)
    H.equal(ok, false, mutation .. " mutation is rejected by the acceptance gate")
    H.equal(tostring(err):find(field, 1, true) ~= nil, true,
        mutation .. " failure names the first differing field")
end

H.test("2.0 GD1 a position changed after validation blocks the acceptance case", function()
    expects_gate_failure(Chains.item_chain("2.0"), "position", "position")
end)

H.test("2.0 GD2 an unchanged candidate still passes", function()
    Gate.demand_success(Chains.item_chain("2.0"))
end)

H.test("2.0 GD3 a changed module loadout is caught", function()
    expects_gate_failure(Chains.item_chain("2.0"), "module", "module loadout")
end)

H.test("2.0 GD4 a changed wire endpoint is caught", function()
    expects_gate_failure(Chains.item_chain("2.0"), "wire", "wire endpoints")
end)

H.done("acceptance_gate_digest")

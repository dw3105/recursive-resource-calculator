-- L1: every block belonging to a shared step participates in flow links.
local H = require "tests.harness"
local D = require "tests.fixtures.search_doubles"
local Search = require "logic.bp.search"
local Groups = require "logic.bp.groups"

H.test("L1 split step blocks each link to producer and consumer", function()
    local original = Groups.step
    local state, log = D.run({}, function()
        Groups.step = function(stage, budget)
            if budget.ops > 0 then
                budget.ops = budget.ops - 1
                stage.result = {candidates = {{id = "candidate", blocks = {
                    {id = "producer", w = 1, h = 1, ports = {{port_id = "p", step_id = "p", flow_id = "f-in", role = "out"}}},
                    {id = "shared-a", w = 1, h = 1, ports = {
                        {port_id = "a-in", step_id = "shared", flow_id = "f-in", role = "in"},
                        {port_id = "a-out", step_id = "shared", flow_id = "f-out", role = "out"},
                        {port_id = "a-ext", step_id = "shared", flow_id = "f-ext", role = "in"},
                        {port_id = "a-ext-out", step_id = "shared", flow_id = "f-ext-out", role = "out"},
                    }},
                    {id = "shared-b", w = 1, h = 1, ports = {
                        {port_id = "b-in", step_id = "shared", flow_id = "f-in", role = "in"},
                        {port_id = "b-out", step_id = "shared", flow_id = "f-out", role = "out"},
                        {port_id = "b-ext", step_id = "shared", flow_id = "f-ext", role = "in"},
                        {port_id = "b-ext-out", step_id = "shared", flow_id = "f-ext-out", role = "out"},
                    }},
                    {id = "consumer", w = 1, h = 1, ports = {{port_id = "c", step_id = "c", flow_id = "f-out", role = "in"}}},
                }}}}
                stage.done, stage.ok = true, true
            end
            return stage
        end
        local input = D.input({plan_result = {steps = {}, flows = {
            {flow_id = "f-in", producers = {{step_id = "p"}}, consumers = {{step_id = "shared"}}},
            {flow_id = "f-out", producers = {{step_id = "shared"}}, consumers = {{step_id = "c"}}},
            {flow_id = "f-ext", producers = {{step_id = "$external"}}, consumers = {{step_id = "shared"}}},
            {flow_id = "f-ext-out", producers = {{step_id = "shared"}}, consumers = {{step_id = "$external"}}},
        }, ports = {}}})
        local search = Search.begin(input)
        -- Exercise the MaxRects retry path too: link construction must not depend on the active packer.
        search.work.layered_off = true
        return D.finish(Search, search)
    end)
    Groups.step = original
    local from_producer, to_consumer, external_in, external_out = {}, {}, {}, {}
    for _, link in ipairs(log.pack[1].links) do
        if link.a.block_id == "producer" then from_producer[link.b.block_id] = true end
        if link.b.block_id == "consumer" then to_consumer[link.a.block_id] = true end
        if link.b.edge == "left" then external_in[link.a.block_id] = true end
        if link.b.edge == "top" then external_out[link.a.block_id] = true end
    end
    H.equal(from_producer["shared-a"], true, "producer links to first split block")
    H.equal(from_producer["shared-b"], true, "producer links to second split block")
    H.equal(to_consumer["shared-a"], true, "first split block links to consumer")
    H.equal(to_consumer["shared-b"], true, "second split block links to consumer")
    H.equal(external_in["shared-a"], true, "external input reaches first split block")
    H.equal(external_in["shared-b"], true, "external input reaches second split block")
    H.equal(external_out["shared-a"], true, "first split block links to external output")
    H.equal(external_out["shared-b"], true, "second split block links to external output")
end)
H.done("test_candidate_links")

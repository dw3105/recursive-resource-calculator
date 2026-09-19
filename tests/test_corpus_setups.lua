--Each positive corpus case must prove its production graph before the
--generation service is allowed to ask for a layout.  These are harness
--captures: they exercise preparation and may observe a bounded search failure,
--but they are never engine evidence or an accepted golden expectation.
local H = require "tests.harness"
local Setup = require "tests.golden.setup.init"
local CaptureCase = require "tests.golden.capture_case"

local CASE_NAMES = {
    "base-only-crafting-smelting",
    "shared-intermediate-multi-target",
    "fluid-byproduct-chain",
    "assembler-chain-example",
    "repeatability",
}

local function calculated_environment(description, shape)
    local world = Setup.new_world(description, shape)
    require "control"
    local Sheet = require "gui.sheet"
    local pane, sheet, sheet_id = Setup.make_sheet(world, description, 1)

    --This is deliberately the assertion point.  No Generation.start or
    --blueprint search has run yet, so a missing fluid/byproduct cannot be
    --hidden by a later layout input.
    Sheet.calculate(Sheet.compute_button_of(sheet))
    local limit = 600
    while storage[1] and storage[1].calc_jobs and storage[1].calc_jobs[sheet_id] do
        H.run_ticks(world, 1)
        limit = limit - 1
        H.equal(limit > 0, true, description.setup_id .. " calculation finishes")
    end
    local Calculation = require "logic.calculation_result"
    local record = Calculation.get(1, sheet_id)
    H.equal(record ~= nil, true, description.setup_id .. " publishes a calculation")
    local graph = Setup.assert_calculated_graph(description, record.result)

    return {
        world = world,
        Sheet = Sheet,
        Generation = require "logic.bp.generation",
        ExportPayload = require "logic.export_payload",
        Registry = require "logic.registry",
        shape = shape,
        player_index = 1,
        pane = pane,
        sheet = sheet,
        sheet_id = sheet_id,
        graph = graph,
    }
end

local function capture(description, shape)
    local environment = calculated_environment(description, shape)
    environment.Registry.generation = environment.Generation
    local result = CaptureCase.capture(environment, description)
    H.equal(result.capture.source_kind, description.source_kind,
        description.setup_id .. " capture source kind")
    H.equal(result.capture.provenance.candidate_sha, description.source_sha,
        description.setup_id .. " capture source SHA")
    H.equal(result.capture.provenance.factorio_branch, shape,
        description.setup_id .. " capture branch provenance")
    H.equal(result.options.engine_scenario.supply ~= nil, true,
        description.setup_id .. " capture keeps engine supply")
    H.equal(result.options.engine_scenario.drain ~= nil, true,
        description.setup_id .. " capture keeps engine drain")
    H.equal(description.supported_outcome, "production",
        description.setup_id .. " remains a positive supported outcome")
    return result, environment.graph
end

for _, shape in ipairs(H.shapes()) do
    for _, name in ipairs(CASE_NAMES) do
        local description = require("tests.golden.setup." .. name)
        H.test(shape .. " " .. name .. " setup and pre-layout graph are truthful", function()
            Setup.validate(description)
            local result = capture(description, shape)
            H.equal(type(result.capture.snapshot), "table", name .. " keeps prepared input snapshot")
            H.equal(type(result.capture.solver_result), "table", name .. " keeps prepared solver result")
            H.equal(type(result.capture.provenance.revisions), "table", name .. " keeps capture revisions")
        end)
    end

    local repeatability = require "tests.golden.setup.repeatability"
    H.test("repeatability captures have the same calculated graph on " .. shape, function()
        local first, first_graph = capture(repeatability, shape)
        local second, second_graph = capture(repeatability, shape)
        H.deep_equal(second_graph, first_graph, "repeatability graph is stable")
        H.deep_equal(second.capture.solver_result, first.capture.solver_result,
            "repeatability prepared calculation is stable")
        H.equal(first.capture.provenance.candidate_sha, second.capture.provenance.candidate_sha,
            "repeatability source SHA is stable")
    end)
end

H.done("test_corpus_setups")

--One harness setup reaches the real calculation, preparation and a failed
--search, then becomes a labelled draft through the existing golden tool.
local H = require "tests.harness"
local Setup = require "tests.golden.setup.init"
local CaptureCase = require "tests.golden.capture_case"

local setup = require "tests.golden.setup.tiny-chain"
local shape = "2.0"
local world = Setup.new_world(setup, shape)
require "control"
local Sheet = require "gui.sheet"
local Generation = require "logic.bp.generation"
local ExportPayload = require "logic.export_payload"
local Registry = require "logic.registry"
Registry.generation = Generation
local pane, sheet, sheet_id = Setup.make_sheet(world, setup, 1)
local environment = {
    world = world, Sheet = Sheet, Generation = Generation, ExportPayload = ExportPayload, Registry = Registry,
    shape = shape, player_index = 1, pane = pane, sheet = sheet, sheet_id = sheet_id,
}

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if file then file:close() return true end
    return false
end

local function command_ok(code_a, code_b, code_c)
    if type(code_a) == "number" then return code_a == 0 end
    return code_a == true and (code_c == nil or code_c == 0)
end

H.test("CC1 setup calculation preparation capture and failed search make a harness draft", function()
    H.equal(setup.prototype_facts.mocked, true, "the setup records mocked prototype facts")
    local result = CaptureCase.capture(environment, setup)
    H.equal(result.stopped_phase, "search", "the bounded run names the stopped phase")
    H.equal(result.status.state, "failure", "the real search fails after preparation")
    H.equal(result.status.reason_codes[1], "BP_FAIL_SEARCH_BUDGET", "the setup's explicit search bound is observed")
    H.equal(result.capture.source_kind, "harness", "offline preparation is not runtime evidence")
    H.equal(result.capture.provenance.outcome, "failure", "capture records terminal outcome")
    H.equal(result.capture.provenance.stage, "search", "capture records terminal stage")
    H.equal(result.capture.provenance.reason_codes[1], "BP_FAIL_SEARCH_BUDGET", "capture records the search reason")
    H.equal(result.capture.solver_result.status, "ok", "the sliced calculation was real and successful")
    H.equal(type(result.capture.snapshot) == "table", true, "prepared snapshot is preserved")

    local decoded, decode_reason = H.decode_export(result.encoded)
    H.equal(decoded ~= nil, true, "the existing export encoding decodes (" .. tostring(decode_reason) .. ")")
    H.equal(decoded.source_kind, "harness", "decoded source kind stays harness")
    H.equal(decoded.prepared_input.snapshot.sheet_id, sheet_id, "decoded prepared input keeps the sheet")
    H.equal(decoded.prepared_input.solver_result.status, "ok", "decoded prepared solver result is present")
    H.equal(decoded.provenance.outcome, "failure", "decoded provenance keeps failure separate")
    H.equal(decoded.provenance.stage, "search", "decoded provenance keeps search stage")
    H.equal(decoded.source_export, "blueprint-export/" .. sheet_id, "capture names, rather than nests, its source export")

    local root = os.tmpname()
    local export_path = root .. ".export.txt"
    local options_path = root .. ".options.json"
    os.remove(root)
    os.execute("mkdir -p " .. shell_quote(root .. "/cases"))
    local export_file = assert(io.open(export_path, "wb"))
    export_file:write(result.encoded .. "\n")
    export_file:close()
    local options_file = assert(io.open(options_path, "wb"))
    options_file:write(helpers.table_to_json(result.options) .. "\n")
    options_file:close()
    local status_a, status_b, status_c = os.execute("python3 tests/golden/add_case tiny-chain-capture"
        .. " --export " .. shell_quote(export_path) .. " --options " .. shell_quote(options_path)
        .. " --cases " .. shell_quote(root .. "/cases"))
    H.equal(command_ok(status_a, status_b, status_c), true, "add_case files the captured draft")

    local case_root = root .. "/cases/tiny-chain-capture"
    local manifest = helpers.json_to_table(read_file(case_root .. "/manifest.json"))
    H.equal(manifest.state, "draft", "capture never accepts a baseline")
    H.equal(manifest.source_kind, "harness", "draft keeps capture source kind")
    H.equal(manifest.supported_outcome, "production", "supported outcome remains independent")
    H.equal(manifest.expected_outcome, "production", "expected outcome remains production")
    H.equal(manifest.observed_outcome.state, "failure", "observed failure is separate from support")
    H.equal(manifest.observed_outcome.stage, "search", "draft records observed search stage")
    H.equal(manifest.observed_outcome.reason_codes[1], "BP_FAIL_SEARCH_BUDGET", "draft records observed reason")
    H.equal(file_exists(case_root .. "/prepared_input.json"), true, "draft keeps prepared input")
    H.equal(file_exists(case_root .. "/expected_canonical.json"), false, "no baseline was accepted")
end)

H.done("test_case_capture")

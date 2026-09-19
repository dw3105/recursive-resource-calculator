#!/usr/bin/env lua
--Capture one named setup through the real sliced calculation and blueprint
--preparation path.  This file is also a small module for the focused Lua test;
--the command entry point below is the only place that creates a harness world.

local H = require "tests.harness"
local Setup = require "tests.golden.setup.init"
local Settings = require "logic.bp.settings"

local CaptureCase = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function merge(left, right)
    local result = copy(left or {})
    for key, value in pairs(right or {}) do result[key] = copy(value) end
    return result
end

local function bounded_ticks(description)
    local scenario = description.engine_scenario or {}
    return math.max(1, math.floor(description.max_ticks or scenario.max_ticks or 900))
end

local function stop_error(phase, ticks, detail)
    return string.format("capture stopped in phase %s after %d ticks: %s", phase, ticks, tostring(detail))
end

--The option file is consumed by add_case.  It carries policy and engine
--assumptions, while generation controls remain inputs to the real search job.
function CaptureCase.options_for(description, shape)
    local base_version = shape == "2.1" and "2.1.17" or "2.0.77"
    return {
        factorio_branch = shape,
        base_game_version = base_version,
        supported_outcome = description.supported_outcome or "production",
        expected_outcome = description.expected_outcome or description.supported_outcome or "production",
        engine_scenario = copy(description.engine_scenario or {}),
    }
end

--environment contains modules that were loaded while control.lua was parsed.
--No module is required from this function: the same routine is used by the
--command and by tests without creating a second preparation implementation.
function CaptureCase.capture(environment, description)
    local world, Sheet, Generation = environment.world, environment.Sheet, environment.Generation
    local Export = environment.ExportPayload
    if type(Export) ~= "table" then error("capture environment is missing ExportPayload", 2) end
    local player_index, sheet, sheet_id = environment.player_index or 1, environment.sheet, environment.sheet_id
    local maximum = bounded_ticks(description)
    local ticks = 0

    Sheet.calculate(Sheet.compute_button_of(sheet))
    while storage[player_index] and storage[player_index].calc_jobs
        and storage[player_index].calc_jobs[sheet_id] do
        if ticks >= maximum then error(stop_error("calculation", ticks, "tick bound reached"), 2) end
        H.run_ticks(world, 1)
        ticks = ticks + 1
    end

    local settings = environment.settings or Settings.of_sheet(player_index, sheet_id)
    local sheet_options = merge(environment.sheet_options or Sheet.read_inputs(sheet).options, description.generation)
    local generation_input = merge(description.generation, {
        schema_version = 1,
        player_index = player_index,
        sheet_id = sheet_id,
        settings = settings,
        options = sheet_options,
        surface = "nauvis",
        force = "player",
        source_kind = "harness",
        provenance = {
            candidate_sha = "harness",
            mod_version = "harness",
            factorio_branch = environment.shape,
            packaged = false,
        },
        deliver = false,
    })
    local generation_id, start_reason = Generation.start(generation_input)
    if not generation_id then error(stop_error("queued", ticks, start_reason), 2) end
    --ExportPayload discovers the service identity through plain storage data;
    --the handle itself remains process-local inside Generation.
    storage[player_index].generation_id = generation_id

    local status = Generation.status(player_index, generation_id)
    while status and status.state == "pending" do
        if ticks >= maximum then
            error(stop_error(status.phase or "queued", ticks, "tick bound reached"), 2)
        end
        H.run_ticks(world, 1)
        ticks = ticks + 1
        status = Generation.status(player_index, generation_id)
    end
    if not status then error(stop_error("status", ticks, "generation status disappeared"), 2) end

    local capture = Generation.capture(player_index, generation_id)
    if type(capture) ~= "table" then error(stop_error(status.phase or "unknown", ticks, "prepared capture missing"), 2) end
    local payload = Export.build(player_index, sheet)
    local encoded, encode_reason = Export.encode(payload)
    if not encoded then error(stop_error(status.phase or "unknown", ticks, encode_reason), 2) end

    return {
        setup_id = description.setup_id,
        shape = environment.shape,
        ticks = ticks,
        status = status,
        stopped_phase = status.phase or "unknown",
        generation_id = generation_id,
        capture = capture,
        payload = payload,
        encoded = encoded,
        options = CaptureCase.options_for(description, environment.shape),
    }
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_ok(code_a, code_b, code_c)
    if type(code_a) == "number" then return code_a == 0 end
    return code_a == true and (code_c == nil or code_c == 0)
end

local function write_file(path, text)
    local file, reason = io.open(path, "wb")
    if not file then error("cannot write " .. tostring(path) .. ": " .. tostring(reason), 2) end
    file:write(text)
    file:close()
end

local function parse_arguments(arguments)
    local result = {shape = "2.0"}
    result.setup_name = arguments[1]
    local index = 2
    while index <= #arguments do
        local key = arguments[index]
        local value = arguments[index + 1]
        if key == "--shape" or key == "--output" or key == "--options" then
            if value == nil then error(key .. " needs a value", 2) end
            result[key:sub(3)] = value
            index = index + 2
        else
            error("unknown argument " .. tostring(key), 2)
        end
    end
    if not result.setup_name or result.setup_name == "" then
        error("usage: capture_case.lua SETUP [--shape 2.0|2.1] [--output FILE] [--options FILE]", 2)
    end
    return result
end

local arguments = {...}
--When required by tests, return the orchestration module before the command
--entry point creates a world or parses control.lua.
if arguments[1] == "tests.golden.capture_case" then return CaptureCase end

local command = parse_arguments(arguments)
local description = require("tests.golden.setup." .. command.setup_name)
Setup.validate(description)
local shape = command.shape or description.factorio_branch or "2.0"
local world = Setup.new_world(description, shape)
require "control"
local Sheet = require "gui.sheet"
local Generation = require "logic.bp.generation"
local ExportPayload = require "logic.export_payload"
local Registry = require "logic.registry"
Registry.generation = Generation
local pane, sheet, sheet_id = Setup.make_sheet(world, description, 1)
local result = CaptureCase.capture({world = world, Sheet = Sheet, Generation = Generation, ExportPayload = ExportPayload,
    Registry = Registry, shape = shape, player_index = 1, pane = pane, sheet = sheet, sheet_id = sheet_id}, description)

local output_path = command.output or os.tmpname()
local options_path = command.options or output_path .. ".options.json"
write_file(output_path, result.encoded .. "\n")
write_file(options_path, helpers.table_to_json(result.options) .. "\n")
print(string.format("CAPTURE setup=%s shape=%s phase=%s state=%s ticks=%d", result.setup_id, result.shape,
    result.stopped_phase, result.status.state, result.ticks))
print("CAPTURE source_kind=" .. tostring(result.capture.source_kind))
print("CAPTURE prepared_input=" .. helpers.table_to_json(result.capture))
print("CAPTURE export=" .. output_path)
print("CAPTURE options=" .. options_path)

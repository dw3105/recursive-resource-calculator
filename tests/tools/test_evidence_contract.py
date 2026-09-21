"""Carry the companion's emitted observation bytes through receipt and release gate."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from .test_release_gate import (
    GATE,
    PRODUCTION_EXAMPLE,
    ReleaseGateFixture,
)


ROOT = Path(__file__).resolve().parents[2]


LUA_DRIVER = r'''
local output_path = arg[1]
local scenario_path = arg[2]
local canonical_sha = arg[3]
local prepared_input_path = arg[4]
local config_path = arg[5]

local Scenario = dofile(scenario_path)

local function read_file(path)
    local stream = assert(io.open(path, "rb"))
    local value = stream:read("*a")
    stream:close()
    return value
end

local prepared_input_bytes = read_file(prepared_input_path)
local config_bytes = read_file(config_path)

local function quote(value)
    value = tostring(value)
    value = value:gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
    return '"' .. value .. '"'
end

local function encode(value, seen)
    local value_type = type(value)
    if value == nil then return "null" end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "number" then return string.format("%.17g", value) end
    if value_type == "string" then return quote(value) end
    if value_type ~= "table" then error("cannot encode " .. value_type) end

    seen = seen or {}
    if seen[value] then error("cycle in observation") end
    seen[value] = true
    local array, count = true, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            array = false
            break
        end
        if key > count then count = key end
    end
    if array then
        for index = 1, count do
            if value[index] == nil then array = false; break end
        end
    end
    local result = {}
    if array then
        for index = 1, count do result[#result + 1] = encode(value[index], seen) end
        seen[value] = nil
        return "[" .. table.concat(result, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do result[#result + 1] = quote(key) .. ":" .. encode(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(result, ",") .. "}"
end

local candidate = {
    build_id = function()
        return {
            candidate_sha = "fixture-candidate-sha",
            mod_version = "1.1.99",
            factorio_branch = "2.0",
            packaged = true,
        }
    end,
    start_generation = function() return "synthetic-job" end,
    generation_status = function()
        return {
            state = "success",
            blueprint_string = "synthetic-blueprint",
            canonical_sha256 = canonical_sha,
            canonical_version = 1,
        }
    end,
    cancel_generation = function() return {state = "cancelled"} end,
    canonical = function()
        return {canonical_sha256 = canonical_sha, canonical_version = 1}
    end,
}

local written = false
local adapter = {
    tick = function() return 0 end,
    setup_environment = function() return {surface_name = "nauvis", force_name = "player"} end,
    generation_context = function()
        return {
            sheet_id = "synthetic-sheet",
            prepared_input_bytes = prepared_input_bytes,
            config_bytes = config_bytes,
        }
    end,
    build_blueprint = function() return {entities = {"synthetic-factory"}} end,
    prepare_supply = function()
        return {{entry = {full_name = "item/iron-plate", rate_per_second = 1}, kind = "item", name = "iron-plate"}}
    end,
    provide_power = function() return true end,
    prepare_drain = function()
        return {{entry = {full_name = "item/stone-brick", rate_per_second = 1}, kind = "item", name = "stone-brick"}}
    end,
    supply = function() return {accepted = {['item/iron-plate'] = 1 / 3}} end,
    drain = function() return {drained = {['item/stone-brick'] = 1 / 3}} end,
    metadata = function()
        return {
            engine_version = "2.0.77",
            active_mods = {base = "2.0.77"},
            force_research = {},
            surface = "nauvis",
        }
    end,
    write_observation = function(observation)
        -- These host-visible fields identify the synthetic adapter output.  They do not
        -- turn this temporary file into engine evidence.
        for _, field in ipairs({"prepared_input_sha256", "config_sha256", "harness_qualification_id"}) do
            if observation[field] == nil or tostring(observation[field]) == "" then
                error("controller wrote no " .. field .. " binding")
            end
        end
        observation.note = "Synthetic controller output; never engine evidence."
        observation.factorio_branch = "2.0"
        observation.factorio_version = "2.0.77"
        observation.mod_version = "1.1.99"
        observation.environment = {
            factorio_branch = "2.0",
            mod_version = "1.1.99",
            active_mods = {"base"},
        }
        local stream = assert(io.open(output_path, "w"))
        stream:write(encode(observation), "\n")
        stream:close()
        written = true
    end,
    cleanup = function() end,
    announce = function() end,
}

local controller = Scenario.new({candidate = candidate, adapter = adapter})
local accepted = controller:submit({
    case_id = "fixture-production",
    expected_candidate_sha = "fixture-candidate-sha",
    engine_scenario = {
        warm_up_ticks = 5,
        sampling_window_ticks = 10,
        timeout_seconds = 10,
        expected_rates = {['item/stone-brick'] = 1},
    },
})
if not accepted then error("synthetic controller rejected its packaged fixture") end
for tick = 1, 100 do
    controller:tick(tick)
    if written then break end
end
if not written then error("synthetic controller did not emit an observation") end
'''


class EvidenceContractTests(unittest.TestCase):
    def test_companion_shape_is_the_bytes_consumed_by_the_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = ReleaseGateFixture(root)
            fixture.prepare()
            (root / "config.json").write_text(json.dumps(fixture.config, sort_keys=True, separators=(",", ":")), encoding="utf-8")
            output = root / "synthetic-controller.observation.json"
            driver = root / "synthetic-controller.lua"
            driver.write_text(LUA_DRIVER, encoding="utf-8")
            result = subprocess.run(
                [
                    "lua5.2",
                    str(driver),
                    str(output),
                    str(ROOT / "tests" / "golden" / "engine" / "mod" / "scenario.lua"),
                    GATE.canonical_sha256(fixture.expected),
                    str(fixture.prepared_input),
                    str(root / "config.json"),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            raw_observation = output.read_bytes()
            observation = json.loads(raw_observation)
            self.assertEqual(observation["note"], "Synthetic controller output; never engine evidence.")
            self.assertEqual(observation["outcome_kind"], PRODUCTION_EXAMPLE["outcome_kind"])
            self.assertIn("production", observation)
            for field in ("prepared_input_sha256", "config_sha256", "harness_qualification_id"):
                self.assertTrue(observation[field])
            for field in ("rates", "warm_up", "window", "timings"):
                self.assertIn(field, observation["production"])
            evidence_path = fixture.evidence / fixture.candidate / fixture.branch
            evidence_path.mkdir(parents=True, exist_ok=True)
            observation_path = evidence_path / f"{fixture.case_id}.observation.json"
            receipt_path = evidence_path / f"{fixture.case_id}.receipt.json"
            observation_path.write_bytes(raw_observation)
            receipt_result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools" / "evidence_receipt.py"),
                    str(observation_path),
                    str(fixture.archive),
                    "--case",
                    fixture.case_id,
                    "--candidate",
                    fixture.candidate,
                    "--output",
                    str(receipt_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(receipt_result.returncode, 0, receipt_result.stderr or receipt_result.stdout)
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            for field in ("prepared_input_sha256", "config_sha256", "harness_qualification_id"):
                self.assertEqual(receipt[field], observation[field])
            self.assertEqual(observation_path.read_bytes(), raw_observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")
            self.assertFalse((ROOT / "docs" / "engine-evidence" / fixture.candidate).exists())


if __name__ == "__main__":
    unittest.main()

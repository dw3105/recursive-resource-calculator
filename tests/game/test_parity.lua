local S = require "tests.game.support"
local Generation = require "logic.bp.generation"
local RED1 = require "tests.game.fixtures.player_red_science_1s"
local RED1_EXPECTED = require "tests.game.fixtures.player_red_science_1s_expected"
local RED1_BULK = require "tests.game.fixtures.player_red_science_1s_bulk"
local RED1_BULK_EXPECTED = require "tests.game.fixtures.player_red_science_1s_bulk_expected"

local function compare_lines(blueprint_string, expected_text)
    local got, want = S.entity_lines(blueprint_string), S.split_lines(expected_text)
    if #want ~= #got then
        error(string.format("entity count differs: expected %d, got %d", #want, #got), 2)
    end
    for i = 1, #want do
        if want[i] ~= got[i] then
            error(string.format("entity line %d differs: expected <%s>, got <%s>", i, want[i], got[i]), 2)
        end
    end
end

local function start_player_generation(prepared)
    return assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
        prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
end

local function start_engine_generation(prepared)
    return assert(remote.call("rrc-engine-test", "start_generation", {sheet_id = S.sheet_id(S.first_sheet()),
        prepared_input = prepared, settings = prepared.settings, options = prepared.options}))
end

local function engine_result(job_id, then_fn)
    S.wait_until(function()
        return remote.call("rrc-engine-test", "generation_status", job_id).state ~= "pending"
    end, 36000, function()
        local status = remote.call("rrc-engine-test", "generation_status", job_id)
        assert.are_equal("success", status.state,
            "engine generation state; status " .. serpent.line(status, {maxlevel = 4}))
        then_fn(status)
    end, "engine generation terminal")
end

describe("parity", function()
    after_each(function()
        local player = S.player()
        if player.cursor_stack and player.cursor_stack.valid_for_read then player.cursor_stack.clear() end
        local calculator = storage[1] and storage[1].calculator
        if calculator and calculator.valid and calculator.visible then calculator.visible = false end
    end)

    it("red 1s matches offline via Generation", function()
        local prepared = S.prepared_input(RED1)
        local job_id = start_player_generation(prepared)
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
            local state, status = S.generation_state(job_id)
            assert.are_equal("success", state, "generation state; status " .. serpent.line(status, {maxlevel = 4}))
            compare_lines(status.blueprint_string, RED1_EXPECTED)
        end, "Generation parity terminal")
    end)

    it("red 1s bulk matches offline via Generation", function()
        local prepared = S.prepared_input(RED1_BULK)
        local job_id = start_player_generation(prepared)
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
            local state, status = S.generation_state(job_id)
            assert.are_equal("success", state, "generation state; status " .. serpent.line(status, {maxlevel = 4}))
            compare_lines(status.blueprint_string, RED1_BULK_EXPECTED)
        end, "bulk Generation parity terminal")
    end)

    it("red 1s matches offline via rrc-engine-test", function()
        local prepared = S.prepared_input(RED1)
        local job_id = start_engine_generation(prepared)
        engine_result(job_id, function(status)
            compare_lines(status.blueprint_string, RED1_EXPECTED)
            assert.is_true(type(status.canonical_sha256) == "string"
                and status.canonical_sha256:match("^[0-9a-fA-F]+$") ~= nil
                and #status.canonical_sha256 == 64, "canonical_sha256 should be 64 hexadecimal characters")
        end)
    end)

    it("canonical is stable", function()
        local prepared = S.prepared_input(RED1)
        local job_id = start_engine_generation(prepared)
        engine_result(job_id, function(status)
            local first = remote.call("rrc-engine-test", "canonical", status.blueprint_string)
            local second = remote.call("rrc-engine-test", "canonical", status.blueprint_string)
            assert.is_not_nil(first)
            assert.are_same(first, second, "canonical result should be stable")
        end)
    end)

    it("build id is packaged", function()
        local build = remote.call("rrc-engine-test", "build_id")
        assert.is_true(build.packaged == true, "packaged build id")
        if not RRC_OFFLINE then
            assert.is_true(type(build.candidate_sha) == "string"
                and #build.candidate_sha == 40 and build.candidate_sha:match("^[0-9a-fA-F]+$") ~= nil,
                "candidate_sha should be 40 hexadecimal characters")
            assert.is_true(build.factorio_branch == "2.0" or build.factorio_branch == "2.1",
                "factorio_branch should be 2.0 or 2.1")
        end
    end)
end)

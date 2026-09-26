--Step 0 probes: one per lane flow, proved headless on 2.0 and 2.1 before lanes widen them (round 42 plan).
local S = require "tests.game.support"
local Calculator = require "gui.calculator"
local Generation = require "logic.bp.generation"
local RED1 = require "tests.game.fixtures.player_red_science_1s"
local RED1_EXPECTED = require "tests.game.fixtures.player_red_science_1s_expected"

describe("probe", function()
    it("rrc loads", function()
        assert.is_not_nil(storage[1], "player data")
        assert.is_true(S.sheet_pane().valid, "sheet pane built on init")
        assert.is_not_nil(remote.interfaces["rrc-engine-test"], "packaged build registers rrc-engine-test")
    end)

    it("calculator opens", function()
        local player = S.player()
        local frame = storage[1].calculator
        local before = frame.visible
        Calculator.toggle(player)
        assert.are_equal(not before, frame.visible, "toggle flips visibility")
        Calculator.toggle(player)
        assert.are_equal(before, frame.visible, "second toggle restores")
    end)

    it("sheet calculates", function()
        local sheet = S.first_sheet()
        S.fill_row(sheet, 1, "automation-science-pack", 1, "/s")
        S.calculate(sheet)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function() end, "report rows")
    end)

    it("generation delivers", function()
        local sheet = S.first_sheet()
        S.bind("item/automation-science-pack", "automation-science-pack")
        S.bind("item/iron-gear-wheel", "iron-gear-wheel")
        S.fill_row(sheet, 1, "automation-science-pack", 1, "/s")
        S.calculate(sheet)
        local job_id
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = true})
            S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
                local state, status = S.generation_state(job_id)
                assert.are_equal("success", state, "generation state; status " .. serpent.line(status, {maxlevel = 4}))
                assert.is_true(S.player().cursor_stack.valid_for_read and S.player().cursor_stack.is_blueprint,
                    "blueprint reached the cursor; delivery " .. serpent.line({reason = storage[1].blueprint_delivery_last_reason,
                    err = storage[1].blueprint_delivery_last_error, cursor = S.player().cursor_stack.valid_for_read and S.player().cursor_stack.name}))
            end, "generation terminal")
        end, "report rows")
    end)

    it("golden parity red-1s", function()
        local prepared = S.prepared_input(RED1)
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
            local state, status = S.generation_state(job_id)
            assert.are_equal("success", state, "generation state; status " .. serpent.line(status, {maxlevel = 4}))
            local got, want = S.entity_lines(status.blueprint_string), S.split_lines(RED1_EXPECTED)
            assert.are_equal(#want, #got, "entity count")
            for i = 1, #want do assert.are_equal(want[i], got[i], "entity line " .. i) end
        end, "parity terminal")
    end)
end)

--Round 48 G7 + I3: sheets generated INSIDE the real game through the player's own path (sheet row -> calculate ->
--Generation job, the Jobs path the GUI button uses), written to script-output/rrc-capture/<case>.json as
--{result = <generation result>, factorio = <version>}. tools/sheet_ports.py turns that into a sheet fixture; the
--sheet sim then builds and runs it (tests/game/test_sheets.lua). Vanilla profile only; offline it registers nothing.
local S = require "tests.game.support"
local Generation = require "logic.bp.generation"

local BINDS = {
    ["item/iron-gear-wheel"] = "iron-gear-wheel",  --plates stay sheet inputs: smelting in a fresh vanilla game is a burner stone-furnace, which preflight refuses (round 48)
    ["item/copper-cable"] = "copper-cable", ["item/electronic-circuit"] = "electronic-circuit",
    ["item/transport-belt"] = "transport-belt", ["item/inserter"] = "inserter",
    ["item/automation-science-pack"] = "automation-science-pack", ["item/logistic-science-pack"] = "logistic-science-pack",
}
local CASES = {
    {case = "red-science-1s", item = "automation-science-pack"},
    {case = "green-science-1s", item = "logistic-science-pack"},
}

local function version() return (script.active_mods.base or "2.0"):match("^(%d+%.%d+)") end

describe("capture", function()
    for _, c in ipairs(CASES) do
        it("vanilla " .. c.case, function()
            if RRC_OFFLINE or script.active_mods["Moshine"] then return end
            for full_name, recipe in pairs(BINDS) do S.bind(full_name, recipe) end
            local sheet = S.first_sheet()
            S.fill_row(sheet, 1, c.item, 1, "/s")
            S.calculate(sheet)
            S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
                local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = false})
                S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
                    local state, status = S.generation_state(job_id)
                    assert.are_equal("success", state, "in-game generation; status " .. serpent.line(status, {maxlevel = 3}))
                    local name = "vanilla-" .. version() .. "-" .. c.case
                    helpers.write_file("rrc-capture/" .. name .. ".json",
                        helpers.table_to_json({ok = true, result = status.result, blueprint_string = status.blueprint_string, factorio = version()}), false)
                    log("CAPTURE " .. name .. " entities=" .. #(status.result.entities or {}))
                end, "generation terminal")
            end, "report rows")
        end)
    end
end)

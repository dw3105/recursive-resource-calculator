--Optional API members and removed prototypes that must not crash the mod
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B10 a crafting machine without an effect receiver has no base productivity", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "plain-assembler", categories = {"crafting"}, speed = 1, no_effect_receiver = true})
        world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        local report = H.run_sheet({{item = "gear", rate = 3, unit = "/s"}})
        H.near(report.rows["item/raw"].rate, 3, "raw demand without productivity")
    end)

    H.test(shape .. " B11 a machine emitting no pollution key indexes as zero pollution", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "spore-assembler", categories = {"crafting"}, speed = 1, emissions_per_joule = {spores = 0.000001}})
        world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        local report = H.run_sheet({{item = "gear", rate = 3, unit = "/s"}})
        H.near(report.pollution_per_minute, 0, "pollution")
    end)

    H.test(shape .. " B12 a sheet whose item prototype was removed falls back to the empty sheet title", function()
        local world = H.new_world(shape)
        world.add_item("gone-item")
        world.add_player(1)
        world.init()
        --the item is chosen while it exists and removed by a mod afterwards
        local sheet_pane, sheet_flow = H.fill_sheet({{item = "gone-item", rate = 0, unit = "/s"}})
        prototypes.item["gone-item"] = nil
        require("gui.sheet").calculate(require("gui.sheet").compute_button_of(sheet_flow))
        H.equal(H.parse_report(sheet_flow.output_flow), nil, "report")
        H.equal(sheet_pane.tabs[1].tab.caption[1], "hxrrc.empty_sheet", "tab title")
    end)
end

H.done("test_guards")

--Targets with quality: the item button picks a quality, saved item buttons are replaced in place, and items above normal get their own identity
local H = require "tests.harness"

--gear is made by a recipe that also yields scrap, so no binding is made for it at init
local function gear_world(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_item("scrap")
    world.add_fluid("lube")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "gear", amount = 1}, {name = "scrap", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

local function children_named(element, name)
    local found = {}
    for index, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = index end
    end
    return found
end

local function rates_of(sheet_flow)
    return require("gui.input_container").get_desired_production_rates_by_full_item_name(sheet_flow.input_container)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " Q-10a a new sheet's item button picks an item with its quality", function()
        gear_world(shape)
        local _, sheet_flow = H.fill_sheet({})
        H.equal(sheet_flow.input_container.children[1].hxrrc_desired_item_button.elem_type, "item-with-quality", "button type")
    end)

    H.test(shape .. " Q-10b a saved item button is replaced at its place with its item kept, once", function()
        local world = gear_world(shape)
        require "control"
        world.handlers.on_init()
        local sheet_pane = storage[1].sheet_section.sheet_pane
        local input_container = sheet_pane.tabs[1].content.input_container
        --what a 1.1.17 save holds: a filled row and an empty last row, both with an "item" button
        input_container.children[1].hxrrc_desired_item_button.elem_value = {name = "gear"}
        event_handlers.on_gui_elem_changed["hxrrc_desired_item_button"]({element = input_container.children[1].hxrrc_desired_item_button, player_index = 1})
        for row_index, value in ipairs({"gear", false}) do
            local row = input_container.children[row_index]
            local index = children_named(row, "hxrrc_desired_item_button")[1]
            row.children[index].destroy()
            row.add{type = "choose-elem-button", name = "hxrrc_desired_item_button", elem_type = "item", item = value or nil, index = index}
        end
        input_container.children[1].rate_textfield.text = "2"
        input_container.children[1].time_unit_dropdown.selected_index = 2
        for _ = 1, 2 do
            world.handlers.on_configuration_changed({mod_changes = {}})
            while storage.computation_stack[1] do world.handlers.events[defines.events.on_tick]({tick = 0}) end
        end
        for row_index, expected in ipairs({"gear", false}) do
            local row = input_container.children[row_index]
            local item_buttons = children_named(row, "hxrrc_desired_item_button")
            H.equal(#item_buttons, 1, "item buttons in row " .. row_index)
            H.equal(item_buttons[1], 3, "item button position in row " .. row_index)
            H.equal(#children_named(row, "hxrrc_desired_fluid_button"), 1, "fluid button kept in row " .. row_index)
            H.equal(children_named(row, "hxrrc_desired_fluid_button")[1], 4, "fluid button position in row " .. row_index)
            local button = row.hxrrc_desired_item_button
            H.equal(button.elem_type, "item-with-quality", "replaced type in row " .. row_index)
            if expected then
                H.equal(button.elem_value.name, expected, "item kept")
                H.equal(button.elem_value.quality, nil, "kept at normal")
            else
                H.equal(button.elem_value, nil, "empty row stays empty")
            end
        end
        local report = H.parse_report(sheet_pane.tabs[1].content.output_flow)
        assert(report and report.rows["item/gear"], "no gear row after repair")
        H.near(report.rows["item/gear"].rate, 2, "repaired row computes")
        H.equal(sheet_pane.tabs[1].tab.caption[1], "item-name.gear", "title from the repaired button")
    end)

    H.test(shape .. " Q-10c a saved item button whose item was removed is replaced empty", function()
        local world = gear_world(shape)
        require "control"
        world.handlers.on_init()
        local row = storage[1].sheet_section.sheet_pane.tabs[1].content.input_container.children[1]
        local index = children_named(row, "hxrrc_desired_item_button")[1]
        row.children[index].destroy()
        row.add{type = "choose-elem-button", name = "hxrrc_desired_item_button", elem_type = "item", item = "scrap", index = index}
        prototypes.item.scrap = nil
        world.handlers.on_configuration_changed({mod_changes = {}})
        H.equal(row.hxrrc_desired_item_button.elem_type, "item-with-quality", "replaced")
        H.equal(row.hxrrc_desired_item_button.elem_value, nil, "removed item not kept")
    end)

    H.test(shape .. " Q-10d normal quality, given as a name or not at all, targets the plain item as before", function()
        gear_world(shape)
        storage[1].recipes_by_product_full_name["item/gear"] = prototypes.recipe.gear
        storage[1].product_full_names_by_recipe_name.gear = "item/gear"
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}, {item = "gear", quality = "normal", rate = 2, unit = "/s"}})
        local rates, parts = rates_of(sheet_flow)
        H.near(rates["item/gear"], 3, "both rows on the plain item")
        H.equal(next(parts), nil, "no parts for normal targets")
        require("gui.sheet").calculate(require("gui.sheet").compute_button_of(sheet_flow))
        local report = H.parse_report(sheet_flow.output_flow)
        H.near(report.rows["item/gear"].rate, 3, "gear row")
        H.near(report.rows["item/gear"].machines, 3, "gear machines")
        H.near(report.rows["item/raw"].rate, 3, "raw demand")
        H.equal(report.row_count, 3, "gear, raw and scrap rows only")
    end)

    H.test(shape .. " Q-10e a target whose quality was removed by a mod is left out; one given as a prototype is read by name", function()
        gear_world(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", quality = "rare", rate = 1, unit = "/s"}, {item = "gear", quality = "epic", rate = 2, unit = "/s"}})
        --the engine may hand back the quality as a prototype instead of its name
        local second_button = sheet_flow.input_container.children[2].hxrrc_desired_item_button
        rawget(second_button, "_values").elem_value = {name = "gear", quality = prototypes.quality.epic}
        local QualityId = require "logic.quality_id"
        local rates = rates_of(sheet_flow)
        H.near(rates[QualityId.encode("gear", "epic")], 2, "quality read from a prototype")
        prototypes.quality.rare = nil
        rates = rates_of(sheet_flow)
        H.equal(rates[QualityId.encode("gear", "rare")], nil, "removed quality left out")
        H.equal(rates["item/gear"], nil, "not moved to normal")
    end)

    H.test(shape .. " Q-10f an unbound target above normal shows its quality and offers its item's producers", function()
        gear_world(shape)
        local report, sheet_pane = H.run_sheet({{item = "gear", quality = "legendary", rate = 1, unit = "/s"}})
        local QualityId = require "logic.quality_id"
        local row = report.rows[QualityId.encode("gear", "legendary")]
        assert(row, "no legendary gear row")
        H.equal(row.kind, "hxrrc.unselected_recipe", "unselected")
        H.equal(row.quality, "legendary", "quality badge")
        H.near(row.rate, 1, "rate")
        H.equal(row.recipe_button.tags.product_full_name, "item/gear", "binds the plain item")
        H.equal(row.recipe_button.elem_filters[1].filter, "has-product-item", "producer filter")
        H.equal(row.recipe_button.elem_filters[1].elem_filters[1].name, "gear", "filter names the item")
        H.equal(sheet_pane.tabs[1].tab.caption[1], "item-name.gear", "title")
    end)

    H.test(shape .. " Q-12 input: an item named a@rare and item a at rare are two targets", function()
        local world = H.new_world(shape)
        world.add_item("a")
        world.add_item("a@rare")
        world.add_player(1)
        world.init()
        local QualityId = require "logic.quality_id"
        local _, sheet_flow = H.fill_sheet({{item = "a@rare", rate = 5, unit = "/s"}, {item = "a", quality = "rare", rate = 1, unit = "/s"}})
        local rates, parts = rates_of(sheet_flow)
        H.near(rates["item/a@rare"], 5, "legacy demand")
        H.near(rates[QualityId.encode("a", "rare")], 1, "quality demand")
        H.equal(parts["item/a@rare"], nil, "no parts for the normal target")
        local quality_parts = parts[QualityId.encode("a", "rare")]
        H.equal(quality_parts.type, "item", "parts type")
        H.equal(quality_parts.name, "a", "parts name")
        H.equal(quality_parts.quality, "rare", "parts quality")
    end)
end

H.done("test_quality_input")

--Blueprint infrastructure settings stay per sheet, preserve belt families, and the dialog rejects unusable choices.
local H = require "tests.harness"

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_default_infrastructure()
    world.add_player(1)
    storage[1] = {}
    local pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, 1)
    local first = pane.add{type = "flow", name = "sheet-1", tags = {hxrrc_sheet_id = "sheet-1"}}
    local second = pane.add{type = "flow", name = "sheet-2", tags = {hxrrc_sheet_id = "sheet-2"}}
    local Settings = require "logic.bp.settings"
    return world, pane, first, second, Settings
end

local function catalog_for(Settings, player_index, settings)
    local belt = settings.belt
    local pipe = settings.pipe
    local underground_pipe = settings.underground_pipe
    return require("logic.catalog").build(player_index, {
        belt = {belt = belt.name, underground = belt.underground, splitter = belt.splitter, quality = belt.quality},
        pipe = {pipe = pipe.name, underground = underground_pipe.name, quality = pipe.quality},
        inserter = settings.inserter,
        pole = settings.pole,
        robo = settings.roboport,
    })
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP1 defaults put inputs on the left and outputs on the top", function()
        local _, _, _, _, Settings = fixture(shape)
        local settings = Settings.of_sheet(1, "sheet-1")
        H.equal(settings.input_edge, "left", "default input edge")
        H.equal(settings.output_edge, "top", "default output edge")
        H.equal(settings.belt.name, "transport-belt", "default belt")
        H.equal(settings.belt.underground, "underground-belt", "default underground family")
        H.equal(settings.belt.splitter, "splitter", "default splitter family")
    end)

    H.test(shape .. " BP2 an override survives close and reopen", function()
        local _, _, sheet, _, Settings = fixture(shape)
        local BlueprintDialog = require "gui.blueprint_dialog"
        local frame = BlueprintDialog.open(1, sheet)
        local pole = frame.hxrrc_blueprint_pole_row.hxrrc_blueprint_pole_button
        pole.elem_value = {name = "medium-electric-pole", quality = "rare"}
        event_handlers.on_gui_elem_changed[pole.name]({element = pole, player_index = 1})
        BlueprintDialog.close(1)
        local reopened = BlueprintDialog.open(1, sheet)
        H.equal(reopened.hxrrc_blueprint_pole_row.hxrrc_blueprint_pole_button.elem_value.quality, "rare",
            "pole quality survives close and reopen")
        BlueprintDialog.close(1)
        H.equal(BlueprintDialog.is_open(1), false, "dialog closes")
        H.equal(sheet.tags.hxrrc_sheet_id, "sheet-1", "sheet identity survives")
        H.equal(Settings.of_sheet(1, "sheet-1").pole.quality, "rare", "stored pole quality")
    end)

    H.test(shape .. " BP3 two sheets keep separate settings", function()
        local _, _, first, second, Settings = fixture(shape)
        Settings.store(1, "sheet-1", {input_edge = "right", output_edge = "top"})
        Settings.store(1, "sheet-2", {input_edge = "bottom", output_edge = "left"})
        H.equal(Settings.of_sheet(1, "sheet-1").input_edge, "right", "first sheet input")
        H.equal(Settings.of_sheet(1, "sheet-2").input_edge, "bottom", "second sheet input")
        H.equal(first.tags.hxrrc_sheet_id, "sheet-1", "first sheet id")
        H.equal(second.tags.hxrrc_sheet_id, "sheet-2", "second sheet id")
    end)

    H.test(shape .. " BP4 a new sheet seeds from the player's last choices", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_electric_pole({name = "custom-pole", supply_area = 4, wire_distance = 10})
        local chosen = Settings.of_sheet(1, "sheet-1")
        chosen.pole = {name = "custom-pole", quality = "normal"}
        Settings.store(1, "sheet-1", chosen)
        local new_settings = Settings.of_sheet(1, "sheet-2")
        H.equal(new_settings.pole.name, "custom-pole", "new sheet copied last pole")
        H.equal(new_settings.input_edge, "left", "new sheet copied last edge defaults")
        new_settings.input_edge = "right"
        Settings.store(1, "sheet-2", new_settings)
        H.equal(Settings.of_sheet(1, "sheet-1").input_edge, "left", "changing new sheet leaves old sheet alone")
    end)

    H.test(shape .. " BP5 a belt yields its underground and splitter family at its quality", function()
        local _, _, _, _, Settings = fixture(shape)
        local family = Settings.belt_family("transport-belt", "rare")
        H.equal(family ~= nil, true, "vanilla belt family exists")
        H.equal(family.underground, "underground-belt", "underground name")
        H.equal(family.splitter, "splitter", "splitter name")
        H.equal(family.quality, "rare", "family quality")
    end)

    H.test(shape .. " BP6 BP_REJ_BELT_FAMILY_MISSING refuses a belt with only an underground belt", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_transport_belt({name = "half-transport-belt", items_per_second = 15})
        world.add_underground_belt({name = "half-underground-belt", items_per_second = 15})
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.belt = {name = "half-transport-belt", quality = "normal"}
        local family = Settings.belt_family(settings.belt.name, settings.belt.quality)
        H.equal(family ~= nil, false, "a missing splitter leaves the family incomplete")
        local catalog = catalog_for(Settings, 1, settings)
        local ok, code, subject = Settings.validate(settings, catalog)
        H.equal(ok, false, "belt without a splitter is refused")
        H.equal(code, "BP_REJ_BELT_FAMILY_MISSING", "missing splitter reason")
        H.equal(subject ~= nil, true, "missing splitter subject exists")
        H.equal(subject.name, "half-transport-belt", "missing splitter subject")
        H.equal(settings.belt.underground, nil, "no underground belt is written onto the choice")
        H.equal(settings.belt.splitter, nil, "no splitter is written onto the choice")
    end)

    H.test(shape .. " BP7 BP_REJ_BELT_FAMILY_MISSING refuses a belt with only a splitter", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_transport_belt({name = "splitter-only-transport-belt", items_per_second = 15})
        world.add_splitter({name = "splitter-only-splitter", items_per_second = 15})
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.belt = {name = "splitter-only-transport-belt", quality = "normal"}
        local family = Settings.belt_family(settings.belt.name, settings.belt.quality)
        H.equal(family ~= nil, false, "a missing underground belt leaves the family incomplete")
        local catalog = catalog_for(Settings, 1, settings)
        local ok, code, subject = Settings.validate(settings, catalog)
        H.equal(ok, false, "belt without an underground belt is refused")
        H.equal(code, "BP_REJ_BELT_FAMILY_MISSING", "missing underground reason")
        H.equal(subject ~= nil, true, "missing underground subject exists")
        H.equal(subject.name, "splitter-only-transport-belt", "missing underground subject")
        H.equal(settings.belt.underground, nil, "no underground belt is written onto the choice")
        H.equal(settings.belt.splitter, nil, "no splitter is written onto the choice")
    end)

    H.test(shape .. " BP8 a related modded underground belt completes its own family", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_transport_belt({name = "modded-transport-belt", items_per_second = 15})
        world.add_underground_belt({name = "modded-buried-belt", items_per_second = 15, related = "modded-transport-belt"})
        world.add_splitter({name = "modded-splitter", items_per_second = 15})
        local family = Settings.belt_family("modded-transport-belt", "rare")
        H.equal(family ~= nil, true, "related underground belt completes the family")
        H.equal(family.underground, "modded-buried-belt", "related underground name")
        H.equal(family.splitter, "modded-splitter", "belt-prefix splitter name")
        H.equal(family.quality, "rare", "modded family quality")
    end)

    H.test(shape .. " BP9 a different-prefix splitter never completes a belt family", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_transport_belt({name = "alpha-transport-belt", items_per_second = 15})
        world.add_underground_belt({name = "alpha-underground-belt", items_per_second = 15})
        world.add_splitter({name = "beta-splitter", items_per_second = 15})
        local family = Settings.belt_family("alpha-transport-belt", "normal")
        H.equal(family ~= nil, false, "a different-prefix splitter is not a family member")
    end)

    H.test(shape .. " BP_REJ_BELT_FAMILY_MISSING refuses an orphan belt without vanilla substitution", function()
        local world, _, _, _, Settings = fixture(shape)
        world.add_transport_belt({name = "orphan-belt", items_per_second = 15})
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.belt = {name = "orphan-belt", quality = "normal"}
        local catalog = catalog_for(Settings, 1, settings)
        local ok, code, subject = Settings.validate(settings, catalog)
        H.equal(ok, false, "orphan belt is refused")
        H.equal(code, "BP_REJ_BELT_FAMILY_MISSING", "orphan belt reason")
        H.equal(subject.name, "orphan-belt", "orphan belt subject")
        H.equal(settings.belt.underground, nil, "no underground belt is substituted")
        H.equal(settings.belt.splitter, nil, "no splitter is substituted")
    end)

    H.test(shape .. " BP_REJ_BELT_FAMILY_MISSING dialog names an invalid belt and stays open", function()
        local world, _, sheet, _, Settings = fixture(shape)
        world.add_transport_belt({name = "orphan-belt", items_per_second = 15})
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.belt = {name = "orphan-belt", quality = "normal"}
        Settings.store(1, "sheet-1", settings)
        local BlueprintDialog = require "gui.blueprint_dialog"
        local frame = BlueprintDialog.open(1, sheet)
        local button = frame.hxrrc_blueprint_footer.hxrrc_blueprint_generate_button
        local ok, code, subject = event_handlers.on_gui_click[button.name]({element = button, player_index = 1})
        H.equal(ok, false, "invalid belt blocks generation")
        H.equal(code, "BP_REJ_BELT_FAMILY_MISSING", "dialog belt reason")
        H.equal(subject.name, "orphan-belt", "dialog belt subject")
        H.equal(BlueprintDialog.is_open(1), true, "invalid dialog remains open")
        H.equal(frame.hxrrc_blueprint_error.visible, true, "dialog shows the invalid choice")
        H.equal(frame.hxrrc_blueprint_error.caption[2], "orphan-belt", "dialog names the invalid belt")
        BlueprintDialog.close(1)
    end)

    H.test(shape .. " BP_REJ_EDGES_EQUAL refuses equal input and output edges", function()
        local _, _, _, _, Settings = fixture(shape)
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.input_edge, settings.output_edge = "left", "left"
        local valid_catalog = catalog_for(Settings, 1, Settings.of_sheet(1, "sheet-1"))
        local ok, code, subject = Settings.validate(settings, valid_catalog)
        H.equal(ok, false, "equal edges are refused")
        H.equal(code, "BP_REJ_EDGES_EQUAL", "equal edges reason")
        H.equal(subject.name, "input/output", "equal edges subject")
    end)

    H.test(shape .. " BP_REJ_QUALITY_UNAVAILABLE refuses a locked quality", function()
        local world, _, _, _, Settings = fixture(shape)
        world.locked_qualities.rare = true
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.pole = {name = "medium-electric-pole", quality = "rare"}
        local quality_catalog = catalog_for(Settings, 1, settings)
        local ok, code, subject = Settings.validate(settings, quality_catalog)
        H.equal(ok, false, "locked quality is refused")
        H.equal(code, "BP_REJ_QUALITY_UNAVAILABLE", "locked quality reason")
        H.equal(subject.name, "rare", "locked quality subject")
    end)

    H.test(shape .. " BP_REJ_OPTION_PROTOTYPE_MISSING refuses a missing infrastructure prototype", function()
        local _, _, _, _, Settings = fixture(shape)
        local settings = Settings.of_sheet(1, "sheet-1")
        settings.pipe = {name = "removed-pipe", quality = "normal"}
        local valid_catalog = catalog_for(Settings, 1, settings)
        local ok, code, subject = Settings.validate(settings, valid_catalog)
        H.equal(ok, false, "missing pipe is refused")
        H.equal(code, "BP_REJ_OPTION_PROTOTYPE_MISSING", "missing prototype reason")
        H.equal(subject.name, "removed-pipe", "missing prototype subject")
    end)

    H.test(shape .. " BP10 the dialog opens once, closes cleanly and leaves the sheet untouched", function()
        local _, _, sheet, _, Settings = fixture(shape)
        local BlueprintDialog = require "gui.blueprint_dialog"
        local before = sheet.tags.hxrrc_sheet_id
        local first = BlueprintDialog.open(1, sheet)
        local second = BlueprintDialog.open(1, sheet)
        H.equal(first, second, "opening an open dialog reuses the frame")
        H.equal(BlueprintDialog.is_open(1), true, "dialog is open")
        BlueprintDialog.close(1)
        H.equal(BlueprintDialog.is_open(1), false, "dialog is closed")
        H.equal(sheet.valid, true, "sheet remains valid")
        H.equal(sheet.tags.hxrrc_sheet_id, before, "sheet is untouched")
        H.equal(Settings.of_sheet(1, "sheet-1").input_edge, "left", "closing does not change settings")
    end)
end

H.done("test_bp_settings")

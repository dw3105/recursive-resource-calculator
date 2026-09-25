--End-to-end final blueprint delivery for real red-science generation jobs.
local H = require "tests.harness"

local function run(shape, mode)
    local world = H.new_world(shape); world.add_default_infrastructure(); world.add_item("iron-plate"); world.add_blueprint_item(); world.add_player(1); world.init()
    require "control"; world.handlers.on_init()
    local pane, sheet = H.fill_sheet({}); storage[1].sheet_section = {sheet_pane = pane}
    local sid = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
    require("logic.registry").calculation = {get = function() return nil end}
    local f = assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json", "r"))
    local prepared = helpers.json_to_table(f:read("*a")); f:close()
    prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
    prepared.revisions = {sheet = 0, config = 0}
    if mode == "stale" then storage[1].blueprint_delivery = {entities = {}, label = "old", icons = {}, description = ""} end
    if mode == "busy" then world.hold_item(1, "iron-plate", "normal", 1) end
    local player = game.get_player(1)
    local restore_stack_index
    if mode == "failure" then
        local stack = player.cursor_stack
        local mt = getmetatable(stack)
        local prior = mt.__index
        mt.__index = function(object, key)
            if object == stack and key == "set_blueprint_entities" then return function() error("forced cursor write failure") end end
            return prior(object, key)
        end
        restore_stack_index = function() mt.__index = prior end
    end
    local Generation = require "logic.bp.generation"
    local id = assert(Generation.start{player_index = 1, sheet_id = sid, prepared_input = prepared, deliver = true})
    local status
    for _ = 1, 20000 do
        H.run_ticks(world, 1)
        status = Generation.status(1, id)
        if status and status.state ~= "pending" then break end
    end
    H.equal(status.state, "success", "generation succeeds")
    if restore_stack_index then
        restore_stack_index()
        H.equal(status.state, "success", "delivery failure leaves generation successful")
        H.equal(storage[1].blueprint_delivery_last_reason, "blueprint_delivery_failed", "delivery reason is retained")
        local note = nil
        for _, child in ipairs(sheet.children) do if child.name == "hxrrc_job_note" then note = child end end
        H.equal(note ~= nil, true, "failure note is shown")
        local copy = false
        for _, child in ipairs(note.children) do if child.name == "hxrrc_copy_blueprint_string" then copy = child end end
        H.equal(copy ~= false, true, "copy-string button is present")
        event_handlers.on_gui_click[copy.name]({element = copy, player_index = 1})
        H.equal(player.opened.name, "hxrrc_export_dialog", "copy button opens the existing string box")
        H.equal(player.opened.hxrrc_export_text.text:gsub("%s", ""), status.blueprint_string, "box contains blueprint string")
        return
    end
    if mode == "busy" then
        H.equal(storage[1].blueprint_delivery.pending, true, "busy final is pending")
        local note
        for _, child in ipairs(sheet.children) do if child.name == "hxrrc_job_note" then note = child end end
        H.equal(note ~= nil, true, "busy result has a note")
        H.deep_equal(note.children[1].caption, {"hxrrc.blueprint_waiting_hand"}, "busy note explains the hand-off")
        player.clear_cursor()
        world.flush_cursor_events()
    end
    H.equal(#player.cursor_stack.get_blueprint_entities(), #status.result.entities, "final result is in hand")
end

for _, shape in ipairs(H.shapes()) do
    for _, mode in ipairs({"fresh", "stale", "busy", "failure"}) do
        H.test(shape .. " final delivery " .. mode, function() run(shape, mode) end)
    end
end
H.done("test_delivery_final")

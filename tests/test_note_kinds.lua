--A blueprint update note stays visible while configuration changes start calc recomputes.
local H = require "tests.harness"

local function start_world(shape)
    local world = H.new_world(shape)
    world.add_default_infrastructure(); world.add_blueprint_item(); world.add_player(1); world.init()
    require "control"; world.handlers.on_init()
    local pane, sheet = H.fill_sheet({})
    storage[1].sheet_section = {sheet_pane = pane}
    local sid = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
    require("logic.registry").calculation = {get = function() return nil end}
    local f = assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json", "r"))
    local prepared = helpers.json_to_table(f:read("*a")); f:close()
    prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
    prepared.revisions = {sheet = 0, config = 0}
    local Generation = require "logic.bp.generation"
    local args = {player_index=1, sheet_id=sid, prepared_input=prepared}
    return world, sid, Generation, args
end

local function find(parent, name)
    for _, child in ipairs(parent and parent.children or {}) do
        if child.name == name then return child end
        local nested = find(child, name)
        if nested then return nested end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " blueprint update note survives calc recompute and clears on blueprint start", function()
        local world, sid, Generation, args = start_world(shape)
        H.equal(Generation.start(args) ~= nil, true, "blueprint job starts")
        H.run_ticks(world, 30)
        world.handlers.on_configuration_changed({mod_changes = {['RRC-Fork']={old_version="1.1.77",new_version="1.1.79"}}})
        H.run_ticks(world, 60)
        local sheet = storage[1].sheet_section.sheet_pane.tabs[1].content
        local note = find(sheet, "hxrrc_job_note")
        H.equal(note ~= nil, true, "update note remains while calc recompute runs")
        H.equal(note and note.tags and note.tags.kind, "blueprint", "update note is tagged blueprint")
        H.equal(note and note.children[1].caption[1], "hxrrc.blueprint_stopped_update", "update note survives calc start")
        H.equal(Generation.start(args) ~= nil, true, "new blueprint job starts")
        H.run_ticks(world, 10)
        note = find(sheet, "hxrrc_job_note")
        H.equal(note, nil, "blueprint start clears prior blueprint note")
    end)
end

H.done("test_note_kinds")

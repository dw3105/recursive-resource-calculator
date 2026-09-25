local H = require "tests.harness"
local function start(world)
    world.add_default_infrastructure(); world.add_blueprint_item(); world.add_player(1); world.init()
    require "control"; world.handlers.on_init()
    local pane, sheet = H.fill_sheet({}); storage[1].sheet_section = {sheet_pane = pane}
    local sid = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
    require("logic.registry").calculation = {get = function() return nil end}
    local f=assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json","r"))
    local prepared=helpers.json_to_table(f:read("*a")); f:close()
    prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
    prepared.revisions = {sheet = 0, config = 0}
    local Generation=require "logic.bp.generation"
    return sid, Generation, assert(Generation.start{player_index=1,sheet_id=sid,prepared_input=prepared})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " U1 configuration update stops blueprint and records a sheet note", function()
        local world=H.new_world(shape); local sid, Generation = start(world)
        H.run_ticks(world, 30)
        local Registry=require "logic.registry"
        local called=false; local note=Registry.progress_note
        Registry.progress_note=function(p,s,caption)
            if p==1 and s==sid and caption[1]=="hxrrc.blueprint_stopped_update" then called=true end
            return note(p,s,caption)
        end
        world.handlers.on_configuration_changed({mod_changes = {["RRC-Fork"]={old_version="1.1.77",new_version="1.1.79"}}})
        H.run_ticks(world,30)
        H.equal(storage[1].blueprint_job,nil,"update removes the live blueprint job")
        H.equal(Generation.lookup(1,sid).state,"cancelled","update closes generation record")
        H.equal(called,true,"update note is sent through progress_note")
        Registry.progress_note=note
    end)

    H.test(shape .. " U2 lookup closes pending generation without matching live job", function()
        local world=H.new_world(shape); local sid, Generation, id = start(world)
        storage[1].blueprint_job=nil
        H.equal(Generation.lookup(1,sid).state,"cancelled","lookup closes orphaned record")
        H.equal(Generation.status(1,id).state,"cancelled","status keeps it closed")
    end)

    H.test(shape .. " U3 running generation resumes and cancel rebuilds a forgotten handle", function()
        local world=H.new_world(shape); local sid, Generation, id = start(world)
        H.run_ticks(world,10)
        H.equal(Generation.status(1,id).state,"pending","plain reload state remains live")
        Generation._forget_handles_for_test()
        H.equal(Generation.cancel(1,id),true,"cancel rebuilds from saved record")
        H.equal(storage[1].blueprint_job,nil,"cancel stops persisted job")
        H.equal(Generation.lookup(1,sid).state,"cancelled","cancel closes persisted record")
    end)
end
H.done("test_update_stops_jobs")

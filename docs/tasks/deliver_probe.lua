package.path = "./?.lua;./?/init.lua;" .. package.path
local H = require "tests.harness"
local stale = arg[1] == "stale"
local world=H.new_world(H.shapes()[1]); world.add_default_infrastructure(); world.add_blueprint_item(); world.add_player(1); world.init()
require "control"; world.handlers.on_init()
local pane, sheet = H.fill_sheet({}); storage[1].sheet_section = {sheet_pane = pane}
local sid = sheet.tags.hxrrc_sheet_id
storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
require("logic.registry").calculation = {get = function() return nil end}
local f=assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json","r"))
local prepared=helpers.json_to_table(f:read("*a")); f:close()
prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
prepared.revisions = {sheet = 0, config = 0}
if stale then storage[1].blueprint_delivery = {entities = {}, label = "old", icons = {}, description = ""} end
local Generation=require "logic.bp.generation"
local id=Generation.start{player_index=1,sheet_id=sid,prepared_input=prepared,deliver=true}
local player=game.get_player(1)
local first_cursor
for i=1,20000 do
  H.run_ticks(world,1)
  local c=player.cursor_stack
  if not first_cursor and c and c.valid_for_read then first_cursor=world.tick end
  local st=Generation.status(1,id)
  if st and st.state ~= "pending" then break end
end
local st=Generation.status(1,id)
local c=player.cursor_stack
print("stale", stale, "state", st.state, "interim", st.interim and st.interim.sequence, "first cursor tick", first_cursor, "cursor", c and c.valid_for_read and #(c.get_blueprint_entities() or {}), "final", st.result and #st.result.entities)

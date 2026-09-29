local H = require "tests.harness"
local function setup(shape)
    local world = H.new_world(shape)
    local Export = require "logic.export_payload"
    local Snapshot = require "logic.snapshot"
    world.add_item("raw"); world.add_item("gear")
    world.add_machine({name="assembler",categories={"crafting"},speed=1})
    world.add_recipe({name="gear",category="crafting",ingredients={{name="raw",amount=1}},products={{name="gear",amount=1}}})
    world.add_player(1); world.init()
    local _, sheet = H.fill_sheet({{item="gear",rate=1,unit="/s"}},1)
    local snap = Snapshot.of_sheet(sheet)
    storage[1].last_calculation = {sheet_id=snap.sheet_id,result={status="ok",columns={}},settings=snap}
    return world, Export, sheet
end
for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " ES1 player settings survive userdata settings object", function()
        local _, Export, sheet = setup(shape)
        local payload = Export.build(1,sheet)
        H.equal(payload.environment.mod_settings["hxrrc-displayed-floating-point-precision"],12,"player value copied")
    end)
    H.test(shape .. " ES2 startup settings are exported", function()
        local _, Export, sheet = setup(shape)
        local payload = Export.build(1,sheet)
        H.equal(payload.environment.startup_settings["hxrrc-startup-test"],true,"startup boolean copied")
        H.equal(payload.environment.startup_settings["hxrrc-startup-count"],7,"startup number copied")
    end)
    H.test(shape .. " ES3 settings pairs errors leave empty player settings", function()
        local _, Export, sheet = setup(shape)
        local values = {known={value=3}}
        local obj = H.lua_object("settings", values, {"known"})
        local mt = getmetatable(obj); mt.__pairs = function() error("pairs failed") end; setmetatable(obj,mt)
        settings.get_player_settings = function() return obj end
        local payload = Export.build(1,sheet)
        H.deep_equal(payload.environment.mod_settings,{},"failed iteration is empty")
    end)
end
H.done("test_export_settings")

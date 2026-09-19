--The companion is an engine client too. Keep its runtime boundary pinned to
--the downloaded API, including the distinction between value members and
--callable members. This inventory is deliberately source-backed: each entry
--must still occur in the named companion file, so a renamed or removed call
--cannot leave a silently stale assertion behind.
local H = require "tests.harness"

local PINNED = {
    ["2.0"] = "docs/api/2.0.77.members.json",
    ["2.1"] = "docs/api/2.1.19.members.json",
}

local function pinned_spec(shape)
    local file = assert(io.open(PINNED[shape]), "missing pinned API extract for " .. shape)
    local text = file:read("*a")
    file:close()
    return assert(helpers.json_to_table(text), "pinned extract is not JSON: " .. PINNED[shape])
end

local function set_of(list)
    local result = {}
    for _, name in ipairs(list or {}) do result[name] = true end
    return result
end

local function companion_sources()
    local result = {}
    local listing = assert(io.popen("find tests/golden/engine/mod -type f -name '*.lua' | sort"))
    for path in listing:lines() do
        local file = assert(io.open(path))
        result[path] = file:read("*a")
        file:close()
    end
    listing:close()
    return result
end

--Every direct runtime-object member named by the companion. Plain Lua tables
--such as case, blueprint, event, port.entry and decoded entities are excluded;
--these are the engine objects crossing the adapter boundary.
local ENGINE_MEMBERS = {
    {"tests/golden/engine/mod/control.lua", "remote.interfaces", "LuaRemote", "interfaces", "attribute"},
    {"tests/golden/engine/mod/control.lua", "remote.call", "LuaRemote", "call", "method"},
    {"tests/golden/engine/mod/control.lua", "remote.add_interface", "LuaRemote", "add_interface", "method"},
    {"tests/golden/engine/mod/control.lua", "game.print", "LuaGameScript", "print", "method"},
    {"tests/golden/engine/mod/control.lua", "rcon.print", "LuaRCON", "print", "method"},
    {"tests/golden/engine/mod/control.lua", "script.on_event", "LuaBootstrap", "on_event", "method"},

    {"tests/golden/engine/mod/scenario.lua", "helpers.decode_string", "LuaHelpers", "decode_string", "method"},
    {"tests/golden/engine/mod/scenario.lua", "helpers.json_to_table", "LuaHelpers", "json_to_table", "method"},
    {"tests/golden/engine/mod/scenario.lua", "helpers.table_to_json", "LuaHelpers", "table_to_json", "method"},
    {"tests/golden/engine/mod/scenario.lua", "remote.interfaces", "LuaRemote", "interfaces", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "remote.call", "LuaRemote", "call", "method"},
    {"tests/golden/engine/mod/scenario.lua", "game_object().tick", "LuaGameScript", "tick", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "game.surfaces", "LuaGameScript", "surfaces", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "game.create_surface", "LuaGameScript", "create_surface", "method"},
    {"tests/golden/engine/mod/scenario.lua", "game.forces", "LuaGameScript", "forces", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "game.create_force", "LuaGameScript", "create_force", "method"},
    {"tests/golden/engine/mod/scenario.lua", "game.speed", "LuaGameScript", "speed", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "force.technologies", "LuaForce", "technologies", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "technology.researched", "LuaTechnology", "researched", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "environment.surface.create_entities_from_blueprint_string",
        "LuaSurface", "create_entities_from_blueprint_string", "method"},
    {"tests/golden/engine/mod/scenario.lua", "surface.create_entity", "LuaSurface", "create_entity", "method"},
    {"tests/golden/engine/mod/scenario.lua", "poles[1].position", "LuaEntity", "position", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "entity.valid", "LuaEntity", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "entity.type", "LuaEntity", "type", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "source.power_production", "LuaEntity", "power_production", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "source.get_wire_connector", "LuaEntity", "get_wire_connector", "method"},
    {"tests/golden/engine/mod/scenario.lua", "entity.revive", "LuaEntity", "revive", "method"},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.fluidbox", "LuaEntity", "fluidbox", "attribute", {"2.0"}},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.get_fluid", "LuaEntity", "get_fluid", "method", {"2.1"}},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.add_fluid", "LuaEntity", "add_fluid", "method", {"2.1"}},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.remove_fluid", "LuaEntity", "remove_fluid", "method", {"2.1"}},
    {"tests/golden/engine/mod/scenario.lua", "inventory(port.buffer).insert", "LuaInventory", "insert", "method"},
    {"tests/golden/engine/mod/scenario.lua", "inventory(port.buffer).remove", "LuaInventory", "remove", "method"},
    {"tests/golden/engine/mod/scenario.lua", "script.active_mods", "LuaBootstrap", "active_mods", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "helpers.write_file", "LuaHelpers", "write_file", "method"},
    {"tests/golden/engine/mod/scenario.lua", "game.print", "LuaGameScript", "print", "method"},
    {"tests/golden/engine/mod/scenario.lua", "rcon.print", "LuaRCON", "print", "method"},
    {"tests/golden/engine/mod/scenario.lua", "game.delete_surface", "LuaGameScript", "delete_surface", "method"},
    {"tests/golden/engine/mod/scenario.lua", "environment.surface.valid", "LuaSurface", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "port.inserter.valid", "LuaEntity", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "port.inserter.destroy", "LuaEntity", "destroy", "method"},
    {"tests/golden/engine/mod/scenario.lua", "port.pipe.valid", "LuaEntity", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "port.pipe.destroy", "LuaEntity", "destroy", "method"},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.valid", "LuaEntity", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "port.buffer.destroy", "LuaEntity", "destroy", "method"},
    {"tests/golden/engine/mod/scenario.lua", "built.power.valid", "LuaEntity", "valid", "attribute"},
    {"tests/golden/engine/mod/scenario.lua", "built.power.destroy", "LuaEntity", "destroy", "method"},
    {"tests/golden/engine/mod/scenario.lua", "entity.destroy", "LuaEntity", "destroy", "method"},
}

local REQUIRED_CLASSES = {"LuaEntity", "LuaTechnology", "LuaRemote", "LuaRCON", "LuaHelpers"}

local function assert_member(spec, sources, entry, shape)
    local file, needle, class_name, member, kind = table.unpack(entry)
    local shapes = entry[6]
    if shapes then
        local applicable = false
        for _, supported_shape in ipairs(shapes) do
            if supported_shape == shape then applicable = true; break end
        end
        if not applicable then return end
    end
    local label = file .. ": " .. class_name .. "." .. member
    H.equal(sources[file] ~= nil, true, label .. " source file exists")
    H.equal(sources[file] and sources[file]:find(needle, 1, true) ~= nil, true,
        label .. " is still named by the companion")
    local class = spec.classes[class_name]
    H.equal(class ~= nil, true, label .. " class is in the pinned extract")
    if not class then return end
    local attributes, methods = set_of(class.attributes), set_of(class.methods)
    local expected, opposite
    if kind == "attribute" then expected, opposite = attributes, methods else expected, opposite = methods, attributes end
    H.equal(expected[member] == true, true,
        label .. " is a pinned " .. kind)
    H.equal(opposite[member] == nil, true,
        label .. " is not pinned as the opposite kind")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " C1 every companion engine member is pinned with its source kind", function()
        H.new_world(shape)
        local spec = pinned_spec(shape)
        local sources = companion_sources()
        for _, class_name in ipairs(REQUIRED_CLASSES) do
            H.equal(spec.classes[class_name] ~= nil, true,
                "companion class " .. class_name .. " is in the " .. shape .. " extract")
        end
        H.equal(spec.classes.LuaEntity and spec.classes.LuaEntity.parent, "LuaControl", "LuaEntity parent chain starts at LuaControl")
        if shape == "2.0" then
            H.equal(spec.classes.LuaFluidBox ~= nil, true, "2.0 fluidbox class is pinned")
        end
        local errors = {}
        for _, entry in ipairs(ENGINE_MEMBERS) do
            local ok, message = pcall(assert_member, spec, sources, entry, shape)
            if not ok then errors[#errors + 1] = tostring(message) end
        end
        H.equal(#errors, 0, table.concat(errors, "\n"))
    end)
end

H.done("test_companion_api_shapes")

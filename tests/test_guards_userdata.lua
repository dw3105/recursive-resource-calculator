--No module may decide a LuaObject's existence by asking whether it is a table.
--In the game `prototypes` is a LuaPrototypes object and `prototypes.entity` is a LuaCustomTable: both report
--`userdata`. A guard written as `type(prototypes) == "table"` is therefore false in the game and true offline, so
--the code silently finds no prototype in a real factory while every offline case passes. 1.1.27 shipped exactly
--this shape in the pipette. The harness now reports `prototypes` as userdata, and this file keeps the pattern out.
local H = require "tests.harness"

local FORBIDDEN = {
    'type%(prototypes%)%s*==%s*"table"',
    'type%(prototypes%)%s*~=%s*"table"',
    'type%(prototypes%.[%w_]+%)%s*==%s*"table"',
    'type%(prototypes%.[%w_]+%)%s*~=%s*"table"',
    'type%(game%)%s*==%s*"table"',
    'type%(script%)%s*==%s*"table"',
    'type%(helpers%)%s*==%s*"table"',
}

local function shipped_files()
    local files = {}
    for _, name in ipairs({"control.lua", "data.lua", "updates.lua", "settings.lua"}) do files[#files + 1] = name end
    for _, directory in ipairs({"gui", "logic", "logic/bp"}) do
        local listing = io.popen('ls -1 "' .. directory .. '" 2>/dev/null')
        if listing then
            for entry in listing:lines() do
                if entry:match("%.lua$") then files[#files + 1] = directory .. "/" .. entry end
            end
            listing:close()
        end
    end
    return files
end

H.test("U1 no shipped file decides a LuaObject exists by testing for a table", function()
    local files = shipped_files()
    H.equal(#files > 20, true, "the listing found the shipped source files")
    for _, path in ipairs(files) do
        local handle = io.open(path)
        local source = handle:read("*a")
        handle:close()
        local line_number = 0
        for line in (source .. "\n"):gmatch("([^\n]*)\n") do
            line_number = line_number + 1
            local code = line:gsub("%-%-.*$", "")
            for _, pattern in ipairs(FORBIDDEN) do
                if code:find(pattern) then
                    error(H.ASSERT_MARK .. path .. ":" .. line_number .. " guards a LuaObject with a table test: " .. line:gsub("^%s+", ""), 2)
                end
            end
        end
    end
end)

H.test("U2 the harness reports the engine globals the way the engine does", function()
    local world = H.new_world("2.0")
    world.add_item("plate")
    world.add_player(1)
    world.init()
    H.equal(type(prototypes), "userdata", "prototypes is a LuaPrototypes object, never a table")
    H.equal(type(prototypes.item.plate), "userdata", "a prototype is a LuaObject too")
    H.equal(rawget(_G, "prototypes") ~= nil, true, "presence is what a guard may ask about")
end)

H.done("test_guards_userdata")

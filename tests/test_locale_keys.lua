--Every locale key the mod names exists in every language, including the ones built at runtime from a reason code
--The older check in tests/test_module_picker.lua scans a hardcoded list of files, so a key in any file added after
--it was written would never be looked at. This one lists the source directories instead, and it also walks the
--reason-code enum, because those keys are built by concatenation and no literal scan can see them.
local H = require "tests.harness"

local LANGUAGES = {"en", "cs", "ro"}
local DIRECTORIES = {"gui", "logic", "logic/bp"}
local ROOT_FILES = {"control.lua", "data.lua", "updates.lua", "settings.lua"}

local function read(path)
    local file = io.open(path)
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

--Every .lua file under the directories the mod ships, found by listing rather than by a written-down list
local function source_files()
    local files = {}
    for _, name in ipairs(ROOT_FILES) do
        if read(name) then files[#files + 1] = name end
    end
    for _, directory in ipairs(DIRECTORIES) do
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

local function locale_of(language)
    return "\n" .. assert(read("locale/" .. language .. "/locale.cfg"), "no locale for " .. language)
end

H.test("L1 every literal hxrrc key in every shipped source file exists in every language", function()
    local files = source_files()
    H.equal(#files > 20, true, "the listing found the mod's source files")
    local keys, seen_files = {}, {}
    for _, path in ipairs(files) do
        seen_files[path] = true
        for key in read(path):gmatch('"hxrrc%.([%w_]+)"') do
            --A literal ending in "_" is a prefix a reason code is appended to, never a whole key; L2 covers those
            if not key:match("_$") then keys[key] = path end
        end
    end
    H.equal(seen_files["gui/sheet.lua"], true, "the sheet is scanned")
    H.equal(keys.calculator_title, "gui/calculator.lua", "the scan finds a known key")
    for _, language in ipairs(LANGUAGES) do
        local locale = locale_of(language)
        for key, path in pairs(keys) do
            if not locale:find("\n" .. key .. "=", 1, true) then
                error(H.ASSERT_MARK .. language .. " locale lacks " .. key .. " (used in " .. path .. ")", 2)
            end
        end
    end
end)

H.test("L2 every reason code a player can be shown has its locale key", function()
    local ReasonCodes = dofile("logic/bp/reason_codes.lua")
    local shown = {}
    for _, code in ipairs(ReasonCodes.REJECT) do shown[#shown + 1] = code end
    for _, code in ipairs(ReasonCodes.FAIL) do shown[#shown + 1] = code end
    H.equal(#shown > 30, true, "the enum carries the codes a player can meet")
    for _, language in ipairs(LANGUAGES) do
        local locale = locale_of(language)
        for _, code in ipairs(shown) do
            local key = ReasonCodes.locale_key(code):gsub("^hxrrc%.", "")
            if not locale:find("\n" .. key .. "=", 1, true) then
                error(H.ASSERT_MARK .. language .. " locale lacks " .. key .. " (reason code " .. code .. ")", 2)
            end
        end
    end
end)

H.test("L3 an internal or validator code carries no player-facing key", function()
    local ReasonCodes = dofile("logic/bp/reason_codes.lua")
    H.equal(ReasonCodes.locale_key("BP_V_COLLISION"), nil, "a validator violation is a diagnostic, not a message")
    H.equal(ReasonCodes.locale_key("BP_R_NO_PATH"), nil, "an internal retry signal is never shown")
    H.equal(ReasonCodes.all()["BP_V_WIRE_ILLEGAL"], true, "the wire legality code is in the enum")
end)

H.done("test_locale_keys")

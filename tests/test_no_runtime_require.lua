--Factorio allows require only while control.lua is parsed. A require reached from a handler raises
--"Require can't be used outside of control.lua parsing" and kills the save's session.
--
--Version 1.1.39 shipped that crash: logic/solver.lua called require inside Solver.solve_for, so the first
--computed sheet ended the game with a non-recoverable error. Offline Lua allows require at any moment, so no
--mock can catch this; only the shape of the source can. A require must therefore sit at the top level of a
--file, never indented, and logic/registry.lua carries the edges that used to be lazy.
local H = require "tests.harness"

local DIRECTORIES = {"gui", "logic", "logic/bp"}
local ROOT_FILES = {"control.lua", "data.lua", "updates.lua", "settings.lua"}

local function read(path)
    local file = io.open(path)
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function shipped_files()
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
    table.sort(files)
    return files
end

--A line is a comment when its first non-space character starts one, and a string mention is not a call.
local function is_comment(line)
    return line:match("^%s*%-%-") ~= nil
end

local function mentions_require(line)
    return line:match("[^%w_]require%s*[%(\"']") ~= nil or line:match("^require%s*[%(\"']") ~= nil
        or line:match("pcall%s*%(%s*require") ~= nil
end

H.test("NR1 every require sits at the top level of its file", function()
    local files = shipped_files()
    H.equal(#files > 20, true, "the scan found the shipped files")
    local offenders = {}
    for _, path in ipairs(files) do
        local number = 0
        for line in (read(path) or ""):gmatch("[^\n]*") do
            number = number + 1
            if not is_comment(line) and mentions_require(line) and line:match("^%s") then
                offenders[#offenders + 1] = path .. ":" .. number .. ": " .. line:gsub("^%s+", "")
            end
        end
    end
    H.deep_equal(offenders, {}, "an indented require runs inside a function, which the game refuses")
end)

H.test("NR2 the registry carries the edges that used to be lazy", function()
    local registry = read("logic/registry.lua")
    H.equal(registry ~= nil, true, "logic/registry.lua exists")
    H.equal(mentions_require(registry) == false, true, "the registry calls require nowhere, so it can never join a cycle")
    for _, pair in ipairs({
        {"gui/sheet.lua", "Registry.sheet"},
        {"logic/jobs.lua", "Registry.jobs"},
        {"logic/snapshot.lua", "Registry.snapshot"},
        {"logic/solver_steps.lua", "Registry.solver_steps"},
    }) do
        local text = read(pair[1])
        H.equal(text ~= nil, true, pair[1] .. " exists")
        H.equal(text:find(pair[2] .. " =", 1, true) ~= nil, true, pair[1] .. " publishes " .. pair[2])
    end
end)

H.test("NR3 control.lua loads every module a handler reads back", function()
    local control = read("control.lua")
    H.equal(control ~= nil, true, "control.lua exists")
    for _, module in ipairs({"gui.sheet", "logic.jobs", "logic.snapshot", "logic.solver_steps"}) do
        H.equal(control:find('require "' .. module .. '"', 1, true) ~= nil, true,
            "control.lua requires " .. module .. " while it is parsed")
    end
end)

H.done("test_no_runtime_require")

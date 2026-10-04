--Small JUnit writer shared by offline harness cases and runner metadata.
local J = {}

local function stem(file)
    return (file:gsub(".*/", ""):gsub("%.lua$", ""))
end

function J.classname(file, name)
    local id = stem(file)
    if id == "test_turn_flip_census" or id == "census" then return "census/" .. name end
    if id == "test_sheets" or id == "sheets" then return "sheets/" .. name end
    if id == "test_turn_flip_sims" or id == "turnflip" then return "turnflip/" .. name end
    if file:match("^tests/game/") then return "game/" .. id end
    return "lua/" .. id
end

function J.escape(value)
    return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&apos;")
end

function J.address(classname, name)
    assert(not classname:find("::", 1, true), "JUnit classname cannot contain ::")
    return classname .. "::" .. name
end

function J.write(directory, file, cases)
    local ok, err = os.execute("mkdir -p " .. string.format("%q", directory))
    if not ok then return nil, err or "could not create JUnit directory" end
    local path = directory .. "/junit-" .. stem(file) .. ".xml"
    local out = assert(io.open(path, "w"))
    local lines, failures = {}, 0
    for _, case in ipairs(cases) do if case.outcome ~= "pass" then failures = failures + 1 end end
    lines[#lines + 1] = string.format('<testsuite name="%s" tests="%d" failures="%d">', J.escape(stem(file)), #cases, failures)
    for _, case in ipairs(cases) do
        local classname = case.classname or J.classname(file, case.name)
        lines[#lines + 1] = string.format('  <testcase classname="%s" name="%s">', J.escape(classname), J.escape(case.name))
        if case.outcome ~= "pass" then
            lines[#lines + 1] = string.format('    <failure message="%s">%s</failure>', J.escape(case.outcome or "error"), J.escape(case.message or ""))
        end
        lines[#lines + 1] = "  </testcase>"
    end
    lines[#lines + 1] = "</testsuite>"
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    return path
end

--CLI used by the shell adapter for FactorioTest units, whose runner emits JSON rather than JUnit.
if ... == "record" and arg then
    local directory, file, name, classname, outcome, message = arg[2], arg[3], arg[4], arg[5], arg[6], arg[7]
    if not directory or not file or not name or not classname or not outcome then
        io.stderr:write("usage: lua5.2 tools/junit.lua record <dir> <file> <name> <classname> <pass|fail> [message]\n")
        os.exit(2)
    end
    local path, err = J.write(directory, file, {{name = name, classname = classname, outcome = outcome, message = message}})
    if not path then io.stderr:write("JUnit write failed: " .. tostring(err) .. "\n"); os.exit(2) end
    os.exit(0)
end

return J

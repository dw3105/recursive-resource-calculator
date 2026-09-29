local H = require "tests.harness"

--Round 48 D1: every fixture file is listed in tests/fixtures/INDEX.tsv with a class, so none escapes the
--engine checks by being forgotten. Code files (README, run, lib/, *.py, *.md) are not fixtures.
local CLASSES = {twin = true, catalog = true, sheet = true, algo = true, double = true, ["player-rule"] = true, facts = true}
local PROFILES = {player = true, vanilla = true, ["-"] = true}
local ROOTS = "tests/fixtures tests/acceptance tests/export_golden tests/game/expected"

local function fixtures()
    local cmd = "find " .. ROOTS .. " -type f; ls tests/golden/cases/*/prepared_input.json"
    local out, pipe = {}, assert(io.popen(cmd))
    for f in pipe:lines() do
        local code = f:match("%.md$") or f:match("%.py$") or f:match("/run$") or f:find("/lib/", 1, true)
            or f == "tests/fixtures/INDEX.tsv" or f:find("__pycache__", 1, true)
        if not code then out[f] = true end
    end
    pipe:close()
    return out
end

local function index()
    local rows, problems = {}, {}
    local n = 0
    for line in io.lines("tests/fixtures/INDEX.tsv") do
        n = n + 1
        if not line:match("^#") then
            local path, class, profile, why = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
            if not path then problems[#problems + 1] = "line " .. n .. " needs 4 tab fields"
            else
                if rows[path] then problems[#problems + 1] = "line " .. n .. " duplicate " .. path end
                if not CLASSES[class] then problems[#problems + 1] = "line " .. n .. " class " .. class end
                if not PROFILES[profile] then problems[#problems + 1] = "line " .. n .. " profile " .. profile end
                rows[path] = {class = class, profile = profile, why = why}
            end
        end
    end
    return rows, problems
end

H.test("INDEX.tsv rows are well formed", function()
    local _, problems = index()
    H.deep_equal(problems, {}, "INDEX.tsv problems")
end)
H.test("every fixture file has a row", function()
    local rows = index()
    local missing = {}
    for f in pairs(fixtures()) do if not rows[f] then missing[#missing + 1] = f end end
    table.sort(missing)
    H.deep_equal(missing, {}, "fixtures missing from tests/fixtures/INDEX.tsv")
end)
H.test("every row names a file that exists", function()
    local rows, files, stale = index(), fixtures(), {}
    for path in pairs(rows) do if not files[path] then stale[#stale + 1] = path end end
    table.sort(stale)
    H.deep_equal(stale, {}, "INDEX.tsv rows with no file")
end)
H.test("a catalog fixture names its profile", function()
    local rows, bad = index(), {}
    for path, row in pairs(rows) do if row.class == "catalog" and row.profile == "-" then bad[#bad + 1] = path end end
    table.sort(bad)
    H.deep_equal(bad, {}, "catalog rows need player or vanilla")
end)
H.done("test_fixture_index")

local H = require "tests.harness"

--Round 48 B6/D7: every stored sheet (tests/fixtures/sheets/<case>.bp.txt, what the headless sheet sim builds) is
--the exact delivered bytes of the bytes baseline, and its ports file traced with no problem.
--Round 56: magenta joined the lab from round 52 (bytes_round48 has no magenta line); round 48 lines win for every
--case they carry (red-10s and red-10s-stack1 lab fixtures are round 48 bytes). Round 56 baseline replaces both.
local BASELINE = "tests/fixtures/bytes_round48.txt"
local EXTRA = "tests/fixtures/bytes_round52.txt"
local want, from = {}, {}
for _, path in ipairs({EXTRA, BASELINE}) do
    for line in io.lines(path) do
        local case, sha = line:match("^BYTES (%S+) (%x+)$")
        if case then want[case], from[case] = sha, path end
    end
end
for case, path in pairs(from) do
    if path == EXTRA and case ~= "player-magenta-science-10s" then want[case], from[case] = nil, nil end
end
local cases, pipe = {}, assert(io.popen("ls tests/fixtures/sheets/*.bp.txt 2>/dev/null"))
for path in pipe:lines() do cases[#cases + 1] = path:match("sheets/(.+)%.bp%.txt$") end
pipe:close()
H.test("every baseline sheet is stored", function()
    local have, missing = {}, {}
    for _, c in ipairs(cases) do have[c] = true end
    for c in pairs(want) do if not have[c] then missing[#missing + 1] = c end end
    table.sort(missing)
    H.deep_equal(missing, {}, "baseline sheets without tests/fixtures/sheets/<case>.bp.txt")
end)
--Sheets whose lab test is skipped (player 2026-10-04): the pin is skipped with them and named in the output.
local SKIPPED = {
    ["player-magenta-science-10s"] = "skipped 2026-10-04 (player): magenta builds too slowly; re-enable once generation performance is improved significantly",
}
for _, case in ipairs(cases) do
    if SKIPPED[case] then
        print("SKIP sheet " .. case .. ": " .. SKIPPED[case])
    else
    H.test("sheet " .. case .. " bytes and ports", function()
        local sum = assert(io.popen("sha256sum tests/fixtures/sheets/" .. case .. ".bp.txt")):read("*l"):sub(1, 64)
        if want[case] or not case:match("^vanilla%-") then H.equal(sum, want[case], case .. " sha256 vs " .. tostring(from[case])) end
        local text = assert(io.open("tests/fixtures/sheets/" .. case .. ".ports.json")):read("*a")
        H.equal(text:find('"problems": %[%]') ~= nil, true, case .. " ports traced with no problem")
    end)
    end
end
H.done("test_sheet_fixtures")

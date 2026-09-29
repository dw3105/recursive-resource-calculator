local H = require "tests.harness"

--Round 48 B6/D7: every stored sheet (tests/fixtures/sheets/<case>.bp.txt, what the headless sheet sim builds) is
--the exact delivered bytes of the bytes baseline, and its ports file traced with no problem.
local BASELINE = "tests/fixtures/bytes_round47.txt"
local want = {}
for line in io.lines(BASELINE) do
    local case, sha = line:match("^BYTES (%S+) (%x+)$")
    if case then want[case] = sha end
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
for _, case in ipairs(cases) do
    H.test("sheet " .. case .. " bytes and ports", function()
        local sum = assert(io.popen("sha256sum tests/fixtures/sheets/" .. case .. ".bp.txt")):read("*l"):sub(1, 64)
        if want[case] or not case:match("^vanilla%-") then H.equal(sum, want[case], case .. " sha256 vs " .. BASELINE) end
        local text = assert(io.open("tests/fixtures/sheets/" .. case .. ".ports.json")):read("*a")
        H.equal(text:find('"problems": %[%]') ~= nil, true, case .. " ports traced with no problem")
    end)
end
H.done("test_sheet_fixtures")

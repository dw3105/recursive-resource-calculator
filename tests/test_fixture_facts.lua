local H = require "tests.harness"
H.new_world("2.0")
local function read(path)
    local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s
end
local function run(command)
    local ok, reason, code = os.execute(command)
    assert(ok == true or ok == 0 or code == 0, command .. " failed: " .. tostring(reason))
end
H.test("FF1 catalog facts match a fresh extractor run", function()
    local before=read("tests/fixtures/engine_facts/catalog_facts.tsv")
    run("lua5.2 tools/fixture_facts.lua")
    H.equal(read("tests/fixtures/engine_facts/catalog_facts.tsv"),before,"catalog data is current")
end)
H.test("FF2 every indexed catalog fixture appears in facts", function()
    local expected={}
    for line in io.lines("tests/fixtures/INDEX.tsv") do
        local path,class=line:match("^([^\t]+)\t([^\t]+)"); if class=="catalog" then expected[path]=false end
    end
    for line in io.lines("tests/fixtures/engine_facts/catalog_facts.tsv") do
        local list=line:match("^[^\t]+\t[^\t]+\t[^\t]+\t(.*)$") or ""
        for path in list:gmatch("[^,]+") do if expected[path]~=nil then expected[path]=true end end
    end
    for path,present in pairs(expected) do H.equal(present,true,path .. " represented") end
end)
H.test("FF3 mock members match a fresh extractor run", function()
    local before=read("tests/fixtures/engine_facts/mock_members.json")
    run("lua5.2 tools/fixture_facts.lua --mock")
    H.equal(read("tests/fixtures/engine_facts/mock_members.json"),before,"mock data is current")
end)
H.test("FF4 constants have provenance, value, and a matching source line", function()
    local constants=helpers.json_to_table(read("tests/fixtures/engine_facts/constants.json"))
    for _,row in ipairs(constants) do
        H.equal(not not (row.file and row.line and row.name and row.value~=nil and row.probe and row.probe.kind and row.probe.field),true,"required fields")
        local lines={}; for line in io.lines(row.file) do lines[#lines+1]=line end
        local source=lines[row.line]
        H.equal(not not source,true,"source line exists: " .. row.file)
        H.equal(not not source:find(tostring(row.value),1,true),true,"source line contains value: " .. row.name)
    end
end)
H.done("test_fixture_facts")

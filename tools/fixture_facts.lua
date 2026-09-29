package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
if arg[1] == "--mock" then
    local captured, current_shape = {}, nil
    local original = H.lua_object
    H.lua_object = function(class, fields, members, ...)
        for _, member in ipairs(members) do
            local value = fields[member]
            local value_type = value == nil and "nil" or type(value)
            local key = class .. "\0" .. member .. "\0" .. value_type
            captured[key] = captured[key] or {}; captured[key][current_shape] = true
        end
        return original(class, fields, members, ...)
    end
    for _, shape in ipairs(H.shapes()) do current_shape = shape; H.new_world(shape) end
    local rows = {}
    for key, shapes in pairs(captured) do
        local class, member, value_type = key:match("^(.-)%z(.-)%z(.*)$")
        local shape_list = {}; for shape in pairs(shapes) do shape_list[#shape_list + 1] = shape end
        table.sort(shape_list)
        rows[#rows + 1] = {class = class, member = member, type = value_type, shapes = shape_list}
    end
    table.sort(rows, function(a, b) return a.class .. a.member .. a.type < b.class .. b.member .. b.type end)
    local file = assert(io.open("tests/fixtures/engine_facts/mock_members.json", "wb"))
    file:write(helpers.table_to_json(rows), "\n"); file:close()
    os.exit(0)
end
H.new_world("2.0")
local json = helpers
local index = {}
for line in io.lines("tests/fixtures/INDEX.tsv") do
    local path, class, profile = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)")
    if path and class == "catalog" then index[#index + 1] = {path = path, profile = profile} end
end
local function read(path)
    if path:match("%.lua$") then return dofile(path) end
    local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close()
    return json.json_to_table(text)
end
local function catalog_of(path, root)
    if path == "tests/fixtures/engine/roboport-cell.json" then return root.measured end
    if path:match("^tests/export_golden/.*%.json$") then return root.prototypes or root end
    return root.catalog or (root.candidate and root.candidate.catalog) or root.prototypes
end
local function leaves(value, prefix, out)
    if type(value) ~= "table" then out[#out + 1] = {path = prefix, value = json.table_to_json(value)}; return end
    local keys = {}; for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do leaves(value[key], prefix == "" and tostring(key) or prefix .. "." .. tostring(key), out) end
end
local facts, conflicts = {}, {}
for _, fixture in ipairs(index) do
    local ok, root = pcall(read, fixture.path)
    if ok and type(root) == "table" then
        local catalog = catalog_of(fixture.path, root)
        if type(catalog) == "table" then
            local rows = {}; leaves(catalog, "", rows)
            for _, leaf in ipairs(rows) do
                local key = fixture.profile .. "\0" .. leaf.path
                facts[key] = facts[key] or {}
                local values = facts[key]
                values[leaf.value] = values[leaf.value] or {}; table.insert(values[leaf.value], fixture.path)
            end
        end
    end
end
local output = {}
for key, by_value in pairs(facts) do
    local profile, path = key:match("^(.-)%z(.*)$")
    local n = 0; for value, paths in pairs(by_value) do
        table.sort(paths); n = n + 1
        output[#output + 1] = {line = profile .. "\t" .. path .. "\t" .. value .. "\t" .. table.concat(paths, ",")}
    end
    if n > 1 then conflicts[#conflicts + 1] = profile .. "\t" .. path end
end
table.sort(output, function(a,b) return a.line < b.line end); table.sort(conflicts)
local function write(path, lines)
    local f = assert(io.open(path, "wb")); f:write(table.concat(lines, "\n"), "\n"); f:close()
end
local lines = {}; for _, row in ipairs(output) do lines[#lines+1] = row.line end
write("tests/fixtures/engine_facts/catalog_facts.tsv", lines)
write("tests/fixtures/engine_facts/catalog_conflicts.tsv", conflicts)

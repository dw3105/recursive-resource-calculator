--SL1 SL2 SL4 SL5 SL6 SL7 red on round-50-base: begin_sheet / step / progress missing; SL3 green on base, pins bytes.
local H = require "tests.harness"
local warmup = H.new_world("2.0")
warmup.init()
local Snapshot = require "logic.snapshot"

local function world()
    local w = H.new_world("2.0")
    w.add_item("raw")
    for _, name in ipairs({"gear", "plate", "wire", "circuit"}) do w.add_item(name) end
    w.add_module("speed-module", "speed", {speed = 0.2})
    w.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    for _, name in ipairs({"gear", "plate", "wire", "circuit"}) do
        w.add_recipe({name = name, category = "crafting", ingredients = {{name = "raw", amount = 1}},
            products = {{name = name, amount = 1}}})
    end
    w.add_player(1)
    w.init()
    for _, name in ipairs({"gear", "plate", "wire", "circuit"}) do
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name[name] = {name = "assembler"}
        storage[1].module_setups_by_recipe_name[name] = {modules = {}, beacons = {}}
    end
end

local function filled()
    local _, flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}})
    return flow
end

local function plain(value, path)
    path = path or "build"
    H.equal(type(value) ~= "function" and type(value) ~= "userdata", true, path .. " scalar type")
    if type(value) == "table" then
        H.equal(getmetatable(value), nil, path .. " has no metatable")
        for k, v in pairs(value) do plain(k, path .. ".key"); plain(v, path .. ".value") end
    end
end

local function complete(snapshot, ops)
    local done = false
    while not done do done = Snapshot.step(snapshot, {ops = ops}) end
    return snapshot
end

local fixture = dofile("tests/fixtures/r50_player_selection.lua")
H.test("SL3 player fixture fingerprint bytes are pinned", function()
    local fp = Snapshot.fingerprint(fixture)
    H.equal(#fp, 210696, "fingerprint length")
    local path = os.tmpname()
    local f = assert(io.open(path, "w")); f:write(fp); f:close()
    local pipe = assert(io.popen("sha256sum " .. string.format("%q", path), "r"))
    local digest = pipe:read("*l"):match("^(%w+)")
    pipe:close(); os.remove(path)
    H.equal(digest, "a1e319902c0252d2343fb89c8ce445d53eb0344a170de41c6525071bedad8466", "fingerprint sha256")
end)

H.test("SL4 sliced fixture encoding equals whole fingerprint", function()
    local encode, assemble = Snapshot._test.encode_value, Snapshot._test.assemble
    local selection = fixture.selection
    local keys, by = {}, {}
    for i, entry in ipairs(selection) do
        local key = encode(i); keys[#keys + 1] = key; by[key] = encode(entry)
    end
    for _, name in ipairs({"burners", "quality_loops"}) do
        local key = encode(name); keys[#keys + 1] = key; by[key] = encode(selection[name])
    end
    local skey = encode("selection")
    local topkeys, topby = {}, {}
    for _, name in ipairs({"targets", "options"}) do
        local key = encode(name); topkeys[#topkeys + 1] = key; topby[key] = encode(fixture[name])
    end
    topkeys[#topkeys + 1] = skey; topby[skey] = assemble(keys, by)
    H.equal("rrc-snapshot-1:" .. assemble(topkeys, topby), Snapshot.fingerprint(fixture), "sliced fingerprint")
end)

H.test("SL1 one-op slices equal whole snapshot", function()
    world()
    local flow = filled()
    local expected = Snapshot.of_sheet(flow)
    local sliced = Snapshot.begin_sheet(flow)
    while not Snapshot.step(sliced, {ops = 1}) do end
    H.deep_equal(sliced.selection, expected.selection, "selection")
    H.equal(sliced.fingerprint.input, expected.fingerprint.input, "fingerprint")
end)

H.test("SL2 large budget finishes and two ENTRY_OPS process two products", function()
    world()
    local flow = filled()
    local full = Snapshot.begin_sheet(flow)
    H.equal(Snapshot.step(full, {ops = 2000}), true, "large budget done")
    H.equal(full.fingerprint.input, Snapshot.of_sheet(flow).fingerprint.input, "large budget fingerprint")
    local sliced = Snapshot.begin_sheet(flow)
    --a selection larger than the budget spends its first call reading and sorting names (round 50 engine tuning)
    Snapshot.step(sliced, {ops = 2 * Snapshot.ENTRY_OPS})
    H.equal(Snapshot.progress(sliced), 0, "first call sorts names only")
    Snapshot.step(sliced, {ops = 2 * Snapshot.ENTRY_OPS})
    H.equal(Snapshot.progress(sliced), 2, "two product progress")
end)

H.test("SL5 build is plain data and SL7 progress advances", function()
    world()
    local snapshot = Snapshot.begin_sheet(filled())
    Snapshot.step(snapshot, {ops = 1}) --names only: the selection is larger than one op
    Snapshot.step(snapshot, {ops = 1})
    plain(snapshot.build)
    local done, total = Snapshot.progress(snapshot)
    H.equal(done, 1, "one product done"); H.equal(total, 5, "products plus tail")
    while snapshot.build do Snapshot.step(snapshot, {ops = 40}) end
    done, total = Snapshot.progress(snapshot)
    H.equal(done, 1, "done progress"); H.equal(total, 1, "done total")
end)

H.test("SL6 stepping done snapshot is idempotent", function()
    world()
    local snapshot = complete(Snapshot.begin_sheet(filled()), 2000)
    local budget = {ops = 17}
    H.equal(Snapshot.step(snapshot, budget), true, "already done")
    H.equal(budget.ops, 17, "budget unchanged")
end)

print("SL1 SL2 SL3 SL4 SL5 SL6 SL7")
H.done("test_snapshot_slices")

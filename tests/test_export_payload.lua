--The debug envelope is deterministic, plain-data, and decodes with the documented offline base64 plus zlib path.
local H = require "tests.harness"

local ExportPayload
local Snapshot

local function world_with(shape)
    local world = H.new_world(shape)
    ExportPayload = require "logic.export_payload"
    Snapshot = require "logic.snapshot"
    world.add_item("raw")
    world.add_item("gear")
    world.add_item("removed")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.add_player(2)
    world.init()
    return world
end

local function result_for(settings, status)
    return {
        status = status or "ok",
        columns = {{recipe_name = "gear", product_full_name = "item/gear", consumer = false,
            burner = nil, quality_loop = nil, net_amounts = {['item/gear'] = 1, ['item/raw'] = -1},
            binding_full_name = "item/gear", machine = {name = "assembler", quality = "normal"}}},
        recipe_rates = status == "ok" and {gear = 1.2345678901234567} or nil,
        solved_rates = status == "ok" and {['item/gear'] = 1.2345678901234567} or nil,
        unsolved_rates = status == "ok" and {['item/raw'] = -1.2345678901234567} or nil,
        reasons_by_column = status == "ok" and {} or {gear = "consumer_no_longer_consumes"},
        product_parts = {},
        feed_rounds = status == "ok" and 2 or nil,
        settings = settings,
    }
end

local function remember(sheet_flow, result, tick, player_index)
    player_index = player_index or 1
    local snapshot = Snapshot.of_sheet(sheet_flow)
    storage[player_index].last_calculation = {
        sheet_id = snapshot.sheet_id,
        result = result or result_for(snapshot),
        settings = snapshot,
        calculation_tick = tick or 17,
    }
    return snapshot
end

local function build(sheet_flow)
    local payload, state = ExportPayload.build(1, sheet_flow)
    H.equal(type(payload), "table", "build returns a payload")
    H.equal(type(state), "string", "build returns the state")
    return payload, state
end

local function walk_plain(value, path, seen)
    path = path or "payload"
    H.equal(type(value) ~= "userdata", true, path .. " has no LuaObject")
    H.equal(type(value) ~= "function", true, path .. " has no function")
    if type(value) ~= "table" then return end
    seen = seen or {}
    H.equal(seen[value], nil, path .. " has no cycle")
    seen[value] = true
    for key, child in pairs(value) do
        walk_plain(key, path .. ".<key>", seen)
        walk_plain(child, path .. "." .. tostring(key), seen)
    end
    seen[value] = nil
end

local function python_accepts(encoded)
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write(encoded)
    file:close()
    local command = "python3 -c 'import base64,json,zlib; p=json.loads(zlib.decompress(base64.b64decode(open(\""
        .. path .. "\",\"rb\").read()))); print(p[\"format\"]+\":\"+str(p[\"schema_version\"]))'"
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    pipe:close()
    os.remove(path)
    return output:gsub("%s+$", "")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " E1 envelope decodes and python accepts base64 plus zlib", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1.2345678901234567, unit = "/s"}}, 1)
        remember(sheet_flow)
        local payload, state = build(sheet_flow)
        H.equal(payload.format, "rrc-sheet-debug", "format")
        H.equal(payload.schema_version, 1, "schema version")
        H.equal(payload.encoding, "zlib+base64", "encoding")
        H.equal(state, "current", "matching result is current")
        local encoded = assert(ExportPayload.encode(payload))
        local decoded = assert(H.decode_export(encoded))
        H.equal(decoded.format, payload.format, "decoded format")
        H.equal(decoded.schema_version, payload.schema_version, "decoded schema version")
        H.equal(python_accepts(encoded), "rrc-sheet-debug:1", "documented offline decoder")
    end)

    H.test(shape .. " E2 targets keep UI order and full precision", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({
            {item = "gear", rate = 12.345678901234567, unit = "/s"},
            {item = "raw", rate = 3.25, unit = "/m"},
        }, 1)
        remember(sheet_flow)
        local payload = build(sheet_flow)
        H.equal(payload.sheet.targets[1].full_name, "item/gear", "first target order")
        H.equal(payload.sheet.targets[2].full_name, "item/raw", "second target order")
        H.near_relative(payload.sheet.targets[1].rate_per_second, 12.345678901234567, "target precision")
        H.near_relative(payload.sheet.targets[2].rate_per_second, 3.25 / 60, "per-minute target precision")
    end)

    H.test(shape .. " E3 failed calculation keeps reason keys and invents no rates", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = Snapshot.of_sheet(sheet_flow)
        remember(sheet_flow, result_for(snapshot, "infeasible"))
        local payload, state = build(sheet_flow)
        H.equal(state, "failed", "failed result is failed")
        H.equal(payload.calculation.status, "infeasible", "failed calculation status")
        H.equal(payload.calculation.reasons_by_column.gear, "consumer_no_longer_consumes", "reason key")
        H.equal(payload.calculation.recipe_rates, nil, "no invented recipe rates")
        H.equal(payload.calculation.solved_rates, nil, "no invented solved rates")
    end)

    H.test(shape .. " E4 an empty sheet still exports", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({}, 1)
        local payload, state = build(sheet_flow)
        H.equal(state, "not_computed", "empty sheet state")
        H.equal(#payload.sheet.targets, 0, "empty target list")
        H.equal(type(payload.calculation), "table", "empty calculation object")
        H.equal(ExportPayload.encode(payload) ~= nil, true, "empty payload encodes")
    end)

    H.test(shape .. " E5 stale result carries its own settings and is never current", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local old = remember(sheet_flow)
        sheet_flow.input_container.children[1].rate_textfield.text = "2"
        local payload, state = build(sheet_flow)
        H.equal(state, "stale", "old result is stale")
        H.equal(payload.state, "stale", "envelope says stale")
        H.equal(payload.settings.current.fingerprint ~= payload.settings.result.fingerprint, true, "fingerprints differ")
        H.near(payload.settings.result.targets[1].rate_per_second, old.targets[1].rate_per_second, "computed settings retained")
        H.near(payload.settings.current.targets[1].rate_per_second, 2, "current settings retained")
    end)

    H.test(shape .. " E6 unchanged export is deterministic", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        remember(sheet_flow)
        local first = build(sheet_flow)
        local second = build(sheet_flow)
        H.deep_equal(first, second, "same payload twice")
        H.equal(ExportPayload.encode(first), ExportPayload.encode(second), "same encoded string twice")
    end)

    H.test(shape .. " E7 a removed prototype is an identity plus explanation", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = remember(sheet_flow)
        prototypes.entity.assembler = nil
        local payload = build(sheet_flow)
        H.equal(#payload.diagnostics.missing_prototypes > 0, true, "missing prototype diagnostic")
        H.equal(payload.diagnostics.missing_prototypes[1].subject, "entity/assembler", "missing identity")
        H.equal(type(payload.diagnostics.missing_prototypes[1].detail), "string", "missing explanation")
        H.equal(payload.settings.result.fingerprint, snapshot.fingerprint.input, "old settings still readable")
    end)

    H.test(shape .. " E8 non-finite values are tagged and encode succeeds", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = remember(sheet_flow)
        local result = result_for(snapshot)
        result.diagnostics = {nan = 0 / 0, positive = math.huge, negative = -math.huge}
        storage[1].last_calculation.result = result
        local payload = build(sheet_flow)
        H.equal(payload.calculation.diagnostics.nan.rrc_non_finite, "nan", "NaN tag")
        H.equal(payload.calculation.diagnostics.positive.rrc_non_finite, "infinity", "infinity tag")
        H.equal(payload.calculation.diagnostics.negative.rrc_non_finite, "-infinity", "negative infinity tag")
        H.equal(ExportPayload.encode(payload) ~= nil, true, "tagged payload encodes")
    end)

    H.test(shape .. " E9 failed encoding returns nil and a reason", function()
        local world = world_with(shape)
        local _, sheet_flow = H.fill_sheet({}, 1)
        local payload = build(sheet_flow)
        local first = ExportPayload.encode(payload)
        H.equal(type(first), "string", "first encode succeeds")
        world.fail_next_encode()
        local encoded, reason = ExportPayload.encode(payload)
        H.equal(encoded, nil, "failed encode has no shortened string")
        H.equal(type(reason), "string", "failed encode reason")
        H.equal(ExportPayload.encode(payload) ~= nil, true, "failure is consumed once")
    end)

    H.test(shape .. " E10 payload has no userdata and never includes player two", function()
        world_with(shape)
        local _, first_sheet = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local _, second_sheet = H.fill_sheet({{item = "raw", rate = 9, unit = "/s"}}, 2)
        remember(first_sheet)
        remember(second_sheet, nil, nil, 2)
        local payload = build(first_sheet)
        walk_plain(payload)
        H.equal(payload.sheet.player_index, 1, "player one sheet")
        H.equal(payload.sheet.targets[1].full_name, "item/gear", "player one target")
        H.equal(payload.sheet.targets[1].full_name ~= "item/raw", true, "player two target absent")
    end)
end

H.done("test_export_payload")

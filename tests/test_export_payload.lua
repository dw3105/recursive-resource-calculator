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

local function real_attempt(world, pane, sheet, with_spacing)
    local Jobs = require "logic.jobs"
    local Generation = require "logic.bp.generation"
    local Search = require "logic.bp.search"
    local snapshot = Snapshot.of_sheet(sheet)
    storage[1].sheet_section = {sheet_pane = pane}
    storage[1].sheet_revision = {[snapshot.sheet_id] = snapshot.revisions.sheet}
    storage[1].config_revision = snapshot.revisions.config

    local original_begin, original_step = Search.begin, Search.step
    Search.begin = function(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}, input = input}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, false, "failed"
        state.errors = {{code = "BP_REJ_TEST_EXPORT"}}
        if with_spacing then
            state.grid_spacing = {resolved = 50, kind = "derived", source = "logistic_radius", source_value = 25,
                generation_job_id = state.input and state.input.generation_job_id}
        end
        state.progress = {phase = "failed", done_units = 1, total_units = 1}
    end

    local prepared = {
        schema_version = 1, snapshot = snapshot, solver_result = {schema_version = 1, status = "ok", columns = {}},
        catalog = {schema_version = 1, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
            module = {}, beacon = {}},
        settings = {input_edge = "left", output_edge = "top"}, options = {},
        revisions = {sheet = snapshot.revisions.sheet, config = snapshot.revisions.config},
        surface = "nauvis", force = "player", source_export = {name = "real-export-test"},
    }
    local job_id = Generation.start{player_index = 1, sheet_id = snapshot.sheet_id, prepared_input = prepared}
    local status
    for _ = 1, 20 do
        status = Generation.status(1, job_id)
        if status and status.state ~= "pending" then break end
        world.advance_tick(1)
        Jobs.on_tick({tick = world.tick})
    end
    Search.begin, Search.step = original_begin, original_step
    H.equal(status and status.state, "failure", "the real generation attempt reaches a terminal state")
    storage[1].generation_id = job_id
    return job_id
end

local function ordered_map(keys, values)
    local result = {}
    for _, key in ipairs(keys) do result[key] = values[key] end
    return result
end

local function sorted_copy(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    table.sort(result)
    return result
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

    H.test(shape .. " D5 delivery diagnostics are exported as plain fields", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({}, 1)
        storage[1].blueprint_delivery = {pending = true, entities = {{entity_number = 1}}}
        storage[1].blueprint_delivery_last_reason = "blueprint_delivery_failed"
        storage[1].blueprint_delivered_sequence = 7
        local payload = build(sheet_flow)
        H.equal(payload.delivery.pending, true, "pending delivery is reported")
        H.equal(payload.delivery.last_reason, "blueprint_delivery_failed", "last reason is reported")
        H.equal(payload.delivery.delivered_sequence, 7, "delivered sequence is reported")
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

    H.test(shape .. " E11 referenced prototype lists are sorted", function()
        local world = world_with(shape)
        world.add_machine({name = "a-entity", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "z-entity", categories = {"crafting"}, speed = 1})
        world.add_item("a-item")
        world.add_item("z-item")
        world.add_fluid("a-fluid")
        world.add_fluid("z-fluid")
        world.add_module("a-module", "speed", {speed = 0.1})
        world.add_module("z-module", "speed", {speed = 0.1})
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = Snapshot.of_sheet(sheet_flow)
        local result = result_for(snapshot)
        result.referenced = {
            entities = ordered_map({"z-entity", "a-entity"}, { ["a-entity"] = true, ["z-entity"] = true }),
            items = ordered_map({"z-item", "a-item"}, { ["a-item"] = true, ["z-item"] = true }),
            fluids = ordered_map({"z-fluid", "a-fluid"}, { ["a-fluid"] = true, ["z-fluid"] = true }),
            modules = ordered_map({"z-module", "a-module"}, { ["a-module"] = true, ["z-module"] = true }),
        }
        storage[1].last_calculation = {
            sheet_id = snapshot.sheet_id, result = result, settings = snapshot, calculation_tick = 17,
        }

        local Catalog = require "logic.catalog"
        local original_for_export = Catalog.for_export
        local requested
        Catalog.for_export = function(player_index, references)
            requested = references
            return original_for_export(player_index, references)
        end
        local ok, payload_or_error = pcall(build, sheet_flow)
        Catalog.for_export = original_for_export
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(type(payload.prototypes), "table", "prototype catalog exists")
        H.equal(requested ~= nil, true, "catalog references were captured")

        for _, kind in ipairs({"entities", "items", "fluids", "modules"}) do
            local values = requested[kind]
            H.equal(values ~= nil, true, kind .. " references exist before reading them")
            H.equal(type(values), "table", kind .. " references are a list")
            H.deep_equal(values, sorted_copy(values), kind .. " references are sorted")
            local known = "a-" .. (kind == "entities" and "entity" or kind == "items" and "item"
                or kind == "fluids" and "fluid" or "module")
            H.equal(values[1] ~= nil, true, kind .. " known member exists before reading it")
            H.equal(values[1], known, kind .. " known member is at sorted index")
        end
    end)

    H.test(shape .. " E12 differently ordered reference tables produce one payload string", function()
        world_with(shape)
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = Snapshot.of_sheet(sheet_flow)
        local names = {entities = {"assembler", "gear-machine"}, items = {"item/gear", "item/raw"},
            fluids = {"fluid/water", "fluid/steam"}, modules = {"speed-module", "efficiency-module"}}
        local function result_with(order, reverse_values)
            local result = result_for(snapshot)
            local references = {}
            for _, kind in ipairs(order) do
                local values = {}
                local first, second = names[kind][1], names[kind][2]
                local value_order = reverse_values and {second, first} or {first, second}
                for _, name in ipairs(value_order) do values[name] = true end
                references[kind] = values
            end
            result.referenced = references
            local map_order = reverse_values and {"item/raw", "item/gear"} or {"item/gear", "item/raw"}
            result.solved_rates = ordered_map(map_order, {['item/gear'] = 1, ['item/raw'] = -1})
            result.product_parts = ordered_map(map_order, {['item/gear'] = {}, ['item/raw'] = {}})
            return result
        end

        local first_result = result_with({"entities", "items", "fluids", "modules"}, false)
        storage[1].last_calculation = {
            sheet_id = snapshot.sheet_id, result = first_result, settings = snapshot, calculation_tick = 17,
        }
        local first = build(sheet_flow)

        local second_result = result_with({"modules", "fluids", "items", "entities"}, true)
        storage[1].last_calculation.result = second_result
        local second = build(sheet_flow)
        H.deep_equal(first, second, "same snapshot gives identical payload tables")
        H.equal(ExportPayload.encode(first), ExportPayload.encode(second), "same snapshot gives identical payload strings")
    end)

    H.test(shape .. " E13 targets and module slots keep their meaningful order", function()
        local world = world_with(shape)
        world.add_module("slot-a", "speed", {speed = 0.1})
        world.add_module("slot-b", "speed", {speed = 0.1})
        world.bind("item/gear", "gear")
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "normal"}
        storage[1].module_setups_by_recipe_name.gear = {
            modules = {{name = "slot-b"}, {name = "slot-a"}}, beacons = {},
        }
        local _, sheet_flow = H.fill_sheet({
            {item = "raw", rate = 2, unit = "/s"},
            {item = "gear", rate = 1, unit = "/s"},
        }, 1)
        local snapshot = remember(sheet_flow)
        local payload = build(sheet_flow)

        local targets = payload.sheet.targets
        H.equal(type(targets), "table", "target list exists")
        H.equal(targets[1] ~= nil, true, "first target exists before reading it")
        H.equal(targets[2] ~= nil, true, "second target exists before reading it")
        H.equal(targets[1].full_name, "item/raw", "first target stays in UI order")
        H.equal(targets[2].full_name, "item/gear", "second target stays in UI order")

        local selection = payload.selection
        H.equal(type(selection), "table", "selection exists")
        H.equal(selection[1] ~= nil, true, "selected recipe exists before reading it")
        local modules = selection[1].modules
        H.equal(type(modules), "table", "module slots exist")
        H.equal(modules[1] ~= nil, true, "first module slot exists before reading it")
        H.equal(modules[2] ~= nil, true, "second module slot exists before reading it")
        H.equal(modules[1].name, "slot-b", "first module slot stays first")
        H.equal(modules[2].name, "slot-a", "second module slot stays second")
    end)

    H.test(shape .. " E14 prepared capture keeps provenance and precision through the envelope", function()
        world_with(shape)
        local Registry = require "logic.registry"
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = Snapshot.of_sheet(sheet_flow)
        local prepared = {
            schema_version = 1,
            snapshot = {sheet_id = snapshot.sheet_id, nested = {rate = 1.2345678901234567}},
            solver_result = {residual = 0.00000000012345678},
            catalog = {entity = {assembler = {tile_w = 1}}},
            settings = {input_edge = "left"}, options = {round_up = true},
            revisions = {sheet = 7, config = 3}, surface = "nauvis", force = "player-force",
            source_export = "prepared-before-debug-export",
        }
        local previous_generation = Registry.generation
        local called_player, called_generation
        Registry.generation = {
            capture = function(player_index, generation_id)
                called_player, called_generation = player_index, generation_id
                return {
                    prepared_input = prepared,
                    source_kind = "runtime",
                    provenance = {candidate_sha = "candidate", terminal_outcome = "failure", stage = "search",
                        reason_codes = {"BP_FAIL_NO_LAYOUT_GRID_LIMIT"}},
                    source_export = "prepared-before-debug-export",
                }
            end,
        }
        storage[1].generation_id = "generation-14"
        local ok, payload_or_error = pcall(build, sheet_flow)
        Registry.generation = previous_generation
        storage[1].generation_id = nil
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(called_player, 1, "capture receives player index")
        H.equal(called_generation, "generation-14", "capture receives generation identity")
        H.equal(payload.source_kind, "runtime", "capture source kind")
        H.equal(payload.source_export, "prepared-before-debug-export", "capture source export is a name")
        H.equal(type(payload.prepared_input.source_export), "string", "prepared source export is a name")
        H.near_relative(payload.prepared_input.snapshot.nested.rate, 1.2345678901234567, "prepared number before encode")
        H.near_relative(payload.prepared_input.solver_result.residual, 0.00000000012345678, "prepared residual before encode")
        local encoded = assert(ExportPayload.encode(payload))
        local decoded = assert(H.decode_export(encoded))
        H.equal(decoded.source_kind, "runtime", "decoded capture source kind")
        H.equal(decoded.source_export, "prepared-before-debug-export", "decoded source export stays a name")
        H.equal(decoded.provenance.terminal_outcome, "failure", "decoded capture terminal outcome")
        H.equal(decoded.provenance.stage, "search", "decoded capture stage")
        H.near_relative(decoded.prepared_input.snapshot.nested.rate, 1.2345678901234567, "prepared number after round trip")
        H.near_relative(decoded.prepared_input.solver_result.residual, 0.00000000012345678, "prepared residual after round trip")
    end)

    H.test(shape .. " E25 the attempt spacing record survives the real export path unchanged", function()
        local world = world_with(shape)
        local pane, sheet = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        remember(sheet)
        local job_id = real_attempt(world, pane, sheet, true)
        local ok, payload_or_error = pcall(build, sheet)
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(payload.generation.grid_spacing.resolved, 50, "attempt spacing is in the payload")
        H.equal(payload.generation.grid_spacing.kind, "derived", "attempt spacing kind")
        H.equal(payload.generation.grid_spacing.source, "logistic_radius", "attempt spacing source")
        H.equal(payload.generation.grid_spacing.source_value, 25, "attempt spacing source value")
        H.equal(payload.generation.grid_spacing.generation_job_id, job_id, "attempt identity")
        local decoded = assert(H.decode_export(assert(ExportPayload.encode(payload))))
        H.equal(decoded.generation.grid_spacing.resolved, 50, "decoded attempt spacing")
        H.equal(decoded.generation.grid_spacing.kind, "derived", "decoded spacing kind")
        H.equal(decoded.generation.grid_spacing.source, "logistic_radius", "decoded spacing source")
        H.equal(decoded.generation.grid_spacing.source_value, 25, "decoded spacing source value")
        H.equal(decoded.generation.grid_spacing.generation_job_id, job_id, "decoded attempt identity")
    end)

    H.test(shape .. " E26 an attempt without spacing names the absence and invents no default", function()
        local world = world_with(shape)
        local pane, sheet = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        remember(sheet)
        real_attempt(world, pane, sheet, false)
        local ok, payload_or_error = pcall(build, sheet)
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(payload.generation.grid_spacing, nil, "an absent attempt does not invent spacing")
        H.equal(payload.generation.missing[1], "grid_spacing", "the attempt names missing spacing")
        local named = false
        for _, fact in ipairs(payload.diagnostics.missing_facts or {}) do
            if fact.fact == "generation.grid_spacing" then named = true end
        end
        H.equal(named, true, "the export diagnostics name missing spacing")
        local decoded = assert(H.decode_export(assert(ExportPayload.encode(payload))))
        H.equal(decoded.generation.grid_spacing, nil, "encoded export does not invent spacing")
        H.equal(decoded.generation.missing[1], "grid_spacing", "encoded export names missing spacing")
    end)

    H.test(shape .. " E27 a stored capture with empty inserter offsets is refused at export and replay", function()
        world_with(shape)
        local _, sheet = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = remember(sheet)
        local Registry = require "logic.registry"
        local previous_generation = Registry.generation
        storage[1].generation_id = "capture-with-empty-offsets"
        Registry.generation = {
            capture = function()
                return {
                    prepared_input = {schema_version = 1, snapshot = {sheet_id = snapshot.sheet_id},
                        catalog = {inserter = {name = "inserter", pickup_offset = {}, drop_offset = {}, drop_position = {}}}},
                    source_kind = "runtime", provenance = {terminal_outcome = "failure"}, source_export = "fixture",
                }
            end,
        }
        local ok, payload_or_error = pcall(build, sheet)
        Registry.generation = previous_generation
        storage[1].generation_id = nil
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(payload.capture.status, "incomplete", "empty geometry has an explicit capture refusal")
        H.equal(payload.capture.reason_codes[1], "BP_CAP_INCOMPLETE", "capture refusal code")
        H.equal(payload.prepared_input.catalog.inserter.pickup_offset, nil,
            "the export boundary does not publish an empty pickup vector")
        local decoded = assert(H.decode_export(assert(ExportPayload.encode(payload))))
        H.equal(decoded.capture.status, "incomplete", "decoded capture remains incomplete")
        H.equal(decoded.prepared_input.catalog.inserter.pickup_offset, nil,
            "replay does not turn the refused vector back into geometry")
    end)
    H.test(shape .. " E-long captured long inserter offsets survive export and replay", function()
        world_with(shape)
        local _, sheet = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = remember(sheet)
        local Registry = require "logic.registry"
        local previous_generation = Registry.generation
        storage[1].generation_id = "capture-long-inserter"
        Registry.generation = {
            capture = function()
                return {
                    prepared_input = {schema_version = 1, snapshot = {sheet_id = snapshot.sheet_id},
                        catalog = {long_inserter = {name = "long-handed-inserter", quality = "normal",
                            pickup_offset = {x = 0, y = 2}, drop_offset = {x = 0, y = -2}, drop_position = {x = 0, y = -2}}}},
                    source_kind = "runtime", provenance = {terminal_outcome = "failure"}, source_export = "fixture",
                }
            end,
        }
        local ok, payload_or_error = pcall(build, sheet)
        Registry.generation = previous_generation
        storage[1].generation_id = nil
        if not ok then error(payload_or_error, 0) end
        local payload = payload_or_error
        H.equal(payload.prepared_input.catalog.long_inserter.name, "long-handed-inserter", "long geometry is capturable")
        H.deep_equal(payload.prepared_input.catalog.long_inserter.pickup_offset, {x = 0, y = 2}, "export pickup fact")
        local decoded = assert(H.decode_export(assert(ExportPayload.encode(payload))))
        H.deep_equal(decoded.prepared_input.catalog.long_inserter.drop_offset, {x = 0, y = -2}, "replay drop fact")
    end)

    --The record contracts §19 freezes lives at storage[pi].calc_results[sheet_id]. 1.1.47 shipped an export that
    --never read it, so a calculated sheet exported as state "not_computed" with no columns at all.
    H.test(shape .. " E24 the export reads the published calculation record", function()
        world_with(shape)
        local Calculation = require "logic.calculation_result"
        local _, sheet_flow = H.fill_sheet({{item = "gear", rate = 1, unit = "/s"}}, 1)
        local snapshot = Snapshot.of_sheet(sheet_flow)
        H.equal(Calculation.publish({
            schema_version = 1, player_index = 1, sheet_id = snapshot.sheet_id,
            sheet_revision = snapshot.revisions.sheet, config_revision = snapshot.revisions.config,
            input_fingerprint = snapshot.fingerprint.input, result = result_for(snapshot), published_tick = 11,
        }), true, "the record publishes")

        local payload, state = build(sheet_flow)
        H.equal(state, "current", "a published record makes the sheet current")
        H.equal(payload.state, "current", "and the payload says so")
        H.equal(#payload.calculation.columns, 1, "the export carries the calculated columns")
        H.equal(payload.calculation.columns[1].recipe_name, "gear", "with the recipe of the step")
        H.equal(payload.calculation.columns[1].machine.name, "assembler", "and the machine it was computed with")
    end)

end

H.done("test_export_payload")

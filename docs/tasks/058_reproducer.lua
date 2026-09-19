--Reproduces the player's sheet shape: a multi-step chain, external item inputs, machine identifiers with no quality.
local H = require "tests.harness"

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " REPRO a three-step chain with external inputs reaches a terminal result", function()
        local world = H.new_world(shape)
        for _, item in ipairs({"ore", "plate", "cable", "circuit", "machine", "gear"}) do world.add_item(item) end
        world.add_fluid("molten-iron")
        world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1})
        world.add_machine({name = "plant", categories = {"crafting"}, speed = 1, module_slots = 2})
        world.add_machine({name = "foundry", categories = {"metallurgy"}, speed = 1})
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 4})
        world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
            products = {{name = "plate", amount = 1}}})
        world.add_recipe({name = "casting-iron", category = "metallurgy",
            ingredients = {{type = "fluid", name = "molten-iron", amount = 20}},
            products = {{name = "plate", amount = 4}}})
        world.add_recipe({name = "cable", category = "crafting", ingredients = {{name = "plate", amount = 1}},
            products = {{name = "cable", amount = 2}}})
        world.add_recipe({name = "circuit", category = "crafting",
            ingredients = {{name = "cable", amount = 3}, {name = "plate", amount = 1}},
            products = {{name = "circuit", amount = 1}}})
        world.add_recipe({name = "machine", category = "crafting",
            ingredients = {{name = "circuit", amount = 3}, {name = "gear", amount = 5}, {name = "plate", amount = 9}},
            products = {{name = "machine", amount = 1}}})
        world.add_module("prod", "productivity", {productivity = 0.25})
        world.add_module("speed", "speed", {speed = 0.5})
        world.add_beacon({name = "beacon", module_slots = 2, distribution = 1.5, supply_w = 9, supply_h = 9})
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()

        local Registry = require "logic.registry"
        local pane, sheet = H.fill_sheet({{item = "machine", rate = 1, unit = "/s"}}, 1)
        storage[1].sheet_section = {sheet_pane = pane}
        local sheet_id = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision = {[sheet_id] = 0}
        storage[1].config_revision = 0
        --exactly what the player's export shows: identifiers with a name and no quality
        local bind = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
        bind["plate"] = {name = "furnace"}
        bind["casting-iron"] = {name = "foundry"}
        bind["cable"] = {name = "plant"}
        bind["circuit"] = {name = "plant"}
        bind["machine"] = {name = "assembler", quality = "normal"}
        --the player's sheet: productivity modules in the machine, speed beacons around it
        local setups = storage[1].module_setups_by_recipe_name
        setups["casting-iron"] = {modules = {{name = "prod", quality = "normal"}, {name = "prod", quality = "normal"}},
            beacons = {{name = "beacon", quality = "normal", count = 3, sharing = 1,
                modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
        setups["circuit"] = {modules = {{name = "prod", quality = "normal"}},
            beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
                modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
        setups["cable"] = {modules = {{name = "prod", quality = "normal"}},
            beacons = {{name = "beacon", quality = "normal", count = 1, sharing = 1,
                modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"}}}}}
        Registry.generation_provenance = {candidate_sha = "repro", mod_version = "repro", factorio_branch = shape, packaged = false}

        local Sheet = require "gui.sheet"
        Sheet.calculate(Sheet.compute_button_of(sheet))
        local ticks = 0
        while storage[1].calc_jobs and storage[1].calc_jobs[sheet_id] do
            H.run_ticks(world, 1)
            ticks = ticks + 1
            H.equal(ticks < 900, true, "calculation finishes")
        end

        local Route = require "logic.bp.route"
        local route_begin, seen = Route.begin, 0
        Route.begin = function(input)
            local state = route_begin(input)
            if seen < 2 then
                seen = seen + 1
                print("PROBE grid=" .. tostring(input.grid and input.grid.w) .. "x" .. tostring(input.grid and input.grid.h)
                    .. " blocks=" .. tostring(#(input.blocks or {})) .. " flows=" .. tostring(#(input.flows or {})))
                for _, flow in ipairs(input.flows or {}) do
                    local p, c = {}, {}
                    for _, e in ipairs(flow.producers or {}) do p[#p+1] = tostring(e.step_id) end
                    for _, e in ipairs(flow.consumers or {}) do c[#c+1] = tostring(e.step_id) end
                    print("  flow " .. tostring(flow.flow_id) .. " prod=[" .. table.concat(p, ",") .. "] cons=[" .. table.concat(c, ",") .. "]")
                end
                for _, block in ipairs(input.blocks or {}) do
                    print("  block " .. tostring(block.block_id or block.id) .. " w=" .. tostring(block.w) .. " h=" .. tostring(block.h)
                        .. " ports=" .. tostring(#(block.ports or {})))
                    for _, port in ipairs(block.ports or {}) do
                        print("    port " .. tostring(port.port_id) .. " role=" .. tostring(port.role)
                            .. " flow=" .. tostring(port.flow_id) .. " step=" .. tostring(port.step_id))
                    end
                end
            end
            return state
        end
        local route_step = Route.step
        Route.step = function(state, budget)
            local out = route_step(state, budget)
            if out and out.done and out.ok == false and seen < 4 then
                seen = seen + 1
                print("PROBE route failed code=" .. tostring(out.errors and out.errors[1] and out.errors[1].code)
                    .. " detail=" .. tostring(out.errors and out.errors[1] and out.errors[1].detail)
                    .. " flow=" .. tostring(out.errors and out.errors[1] and out.errors[1].flow_id))
            end
            return out
        end
        local Generation = require "logic.bp.generation"
        local settings = require("logic.bp.settings").of_sheet(1, sheet_id)
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, settings = settings, deliver = true}
        local result = Generation.status(1, job_id)
        for _ = 1, 1200 do
            if result.state ~= "pending" then break end
            H.run_ticks(world, 1)
            result = Generation.status(1, job_id)
        end
        print("REPRO state=" .. tostring(result.state) .. " stage=" .. tostring(result.stage or result.phase)
            .. " codes=" .. table.concat(result.reason_codes or {}, ","))
        H.equal(result.state, "success", "the chain reaches a blueprint")
    end)
end

H.done("repro_chain")

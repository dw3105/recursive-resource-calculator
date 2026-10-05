--Player run probe P1 (plan 2026-10-05): headless controller, build_from_cursor and ghost revive on the cursor blueprint.
local S = require "tests.game.support"
local BlueprintDialog = require "gui.blueprint_dialog"
local Generation = require "logic.bp.generation"
local FIX = {
    ["player_red_science_1s"] = require "tests.game.fixtures.player_red_science_1s",
    ["player_red_science_1s_bulk"] = require "tests.game.fixtures.player_red_science_1s_bulk",
    ["player_red_science_1s_foundry"] = require "tests.game.fixtures.player_red_science_1s_foundry",
    ["player_am2_chain_repaired"] = require "tests.game.fixtures.player_am2_chain_repaired",
    ["player_blue_science_10s"] = require "tests.game.fixtures.player_blue_science_10s",
    ["player_green_science_1s"] = require "tests.game.fixtures.player_green_science_1s",
    ["player_inserter_10s"] = require "tests.game.fixtures.player_inserter_10s",
    ["player_inserter_10s_bulk"] = require "tests.game.fixtures.player_inserter_10s_bulk",
    ["player_inserter_10s_stack1"] = require "tests.game.fixtures.player_inserter_10s_stack1",
    ["player_red_green_science_10s"] = require "tests.game.fixtures.player_red_green_science_10s",
    ["player_red_science_10s"] = require "tests.game.fixtures.player_red_science_10s",
    ["player_red_science_10s_bulk"] = require "tests.game.fixtures.player_red_science_10s_bulk",
    ["player_red_science_10s_stack1"] = require "tests.game.fixtures.player_red_science_10s_stack1",
}

describe("playerrun probe", function()
    it("build_from_cursor then revive", function()
        local sheet = S.first_sheet()
        S.bind("item/automation-science-pack", "automation-science-pack")
        S.bind("item/iron-gear-wheel", "iron-gear-wheel")
        S.fill_row(sheet, 1, "automation-science-pack", 1, "/s")
        S.calculate(sheet)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            local dialog = assert(BlueprintDialog.open(1, sheet))
            local button = assert(S.find(dialog, "hxrrc_blueprint_generate_button"))
            event_handlers.on_gui_click[button.name]({element = button, player_index = 1})
            S.wait_until(function() return storage[1].blueprint_job == nil end, 36000, function()
                local player = S.player()
                local names = {}
                for k, v in pairs(defines.controllers) do names[v] = k end
                local cursor = player.cursor_stack
                local count = #cursor.get_blueprint_entities()
                local surface0 = player.surface
                surface0.request_to_generate_chunks({300, 300}, 4)
                surface0.force_generate_chunk_requests()
                local tp = player.teleport({300, 290})
                local info = {teleport = tp, pos = player.position, controller = names[player.controller_type], character = player.character ~= nil,
                    can_build = player.can_build_from_cursor{position = {300, 300}}, count = count}
                info.can_build_near = player.can_build_from_cursor{position = {300, 300}}
                info.can_build_normal = player.can_build_from_cursor{position = {300, 300}, build_mode = defines.build_mode.forced}
                local ok, err = pcall(function() player.build_from_cursor{position = {300, 300}, build_mode = defines.build_mode.forced} end)
                info.build_ok, info.build_err = ok, err
                local surface = player.surface
                local area = {{200, 200}, {400, 400}}
                local ghosts = surface.find_entities_filtered{area = area, type = "entity-ghost"}
                info.ghosts = #ghosts
                local real_before = #surface.find_entities_filtered{area = area, force = "player"} - #ghosts
                local revived, failed = 0, 0
                for _, g in ipairs(ghosts) do
                    if g.valid then
                        local _, ent = g.revive()
                        if ent then revived = revived + 1 else failed = failed + 1 end
                    end
                end
                info.real_before, info.revived, info.revive_failed = real_before, revived, failed
                info.left_ghosts = #surface.find_entities_filtered{area = area, type = "entity-ghost"}
                info.cursor_after = cursor.valid_for_read and cursor.name or "empty"
                error("PROBE " .. serpent.line(info))
            end, "blueprint delivery")
        end, "calculation report")
    end)
end)

describe("playerrun gen time", function()
    it("player-red-science-1s", function()
        local prepared = S.prepared_input(FIX["player_red_science_1s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-1s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-science-1s-bulk", function()
        local prepared = S.prepared_input(FIX["player_red_science_1s_bulk"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-1s-bulk state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-science-1s-foundry", function()
        local prepared = S.prepared_input(FIX["player_red_science_1s_foundry"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-1s-foundry state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-am2-chain-repaired", function()
        local prepared = S.prepared_input(FIX["player_am2_chain_repaired"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-am2-chain-repaired state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-blue-science-10s", function()
        local prepared = S.prepared_input(FIX["player_blue_science_10s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-blue-science-10s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-green-science-1s", function()
        local prepared = S.prepared_input(FIX["player_green_science_1s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-green-science-1s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-inserter-10s", function()
        local prepared = S.prepared_input(FIX["player_inserter_10s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-inserter-10s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-inserter-10s-bulk", function()
        local prepared = S.prepared_input(FIX["player_inserter_10s_bulk"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-inserter-10s-bulk state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-inserter-10s-stack1", function()
        local prepared = S.prepared_input(FIX["player_inserter_10s_stack1"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-inserter-10s-stack1 state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-green-science-10s", function()
        local prepared = S.prepared_input(FIX["player_red_green_science_10s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-green-science-10s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-science-10s", function()
        local prepared = S.prepared_input(FIX["player_red_science_10s"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-10s state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-science-10s-bulk", function()
        local prepared = S.prepared_input(FIX["player_red_science_10s_bulk"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-10s-bulk state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
    it("player-red-science-10s-stack1", function()
        local prepared = S.prepared_input(FIX["player_red_science_10s_stack1"])
        local t0 = game.tick
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()),
            prepared_input = prepared, settings = prepared.settings, options = prepared.options, deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 200000, function()
            local state = S.generation_state(job_id)
            log("GENTIME player-red-science-10s-stack1 state=" .. tostring(state) .. " ticks=" .. (game.tick - t0))
        end, "generation terminal")
    end)
end)

describe("playerrun modules", function()
    it("revive keeps modules", function()
        local player = S.player()
        local surface = player.surface
        surface.request_to_generate_chunks({500, 500}, 4)
        surface.force_generate_chunk_requests()
        player.teleport({500, 490})
        local src = surface.create_entity{name = "assembling-machine-3", position = {480.5, 480.5}, force = "player", recipe = "iron-gear-wheel"}
        src.get_module_inventory().insert{name = "speed-module", count = 2}
        src.get_module_inventory().insert{name = "productivity-module", count = 2}
        local b = surface.create_entity{name = "beacon", position = {484.5, 480.5}, force = "player"}
        b.get_module_inventory().insert{name = "speed-module", count = 2}
        player.clear_cursor()
        local cursor = player.cursor_stack
        cursor.set_stack{name = "blueprint"}
        cursor.create_blueprint{surface = surface, force = "player", area = {{478, 478}, {487, 483}}}
        local info = {bp_entities = #cursor.get_blueprint_entities()}
        player.build_from_cursor{position = {500, 500}, build_mode = defines.build_mode.forced}
        local area = {{490, 490}, {510, 510}}
        local ghosts = surface.find_entities_filtered{area = area, type = "entity-ghost"}
        info.ghosts = #ghosts
        local proxies_from_revive = 0
        for _, g in ipairs(ghosts) do
            local _, ent, proxy = g.revive{return_item_request_proxy = true}
            if proxy then proxies_from_revive = proxies_from_revive + 1 end
        end
        info.proxies_from_revive = proxies_from_revive
        local proxies = surface.find_entities_filtered{area = area, name = "item-request-proxy"}
        info.proxies = #proxies
        local inv = {}
        for _, e in ipairs(surface.find_entities_filtered{area = area, name = {"assembling-machine-3", "beacon"}}) do
            inv[e.name] = e.get_module_inventory().get_contents()
        end
        info.before = inv
        local plans = {}
        for _, p in ipairs(proxies) do
            local ok, plan = pcall(function() return p.insert_plan end)
            plans[#plans + 1] = ok and plan or ("no insert_plan: " .. tostring(plan))
        end
        info.plans = plans
        error("PROBE3 " .. serpent.line(info, {maxlevel = 8}))
    end)
end)

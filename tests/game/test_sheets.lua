--Round 48 D7, sheet sims: every delivered sheet built for real, powered, its ports fed full (both lanes, max belt
--stack, G10/G10d), run, and its output counted. Pass: every target >= 0.95 x rate over the window (G4), no foreign
--item at any sink, every entity placed, port belts full at every sample (else FEED_SHORT).
--Fixtures: tests/fixtures/sheets/<case>.bp.txt + <case>.ports.json (tools/sheet_ports.py), embedded by
--tools/game_stage.sh as tests.game.fixtures.sheets_index. A sheet runs only in its profile (player sheets need the
--player's mods: RRC_PROFILE=player).
local Lab = require "tests.game.lib.lab"
local ok_index, INDEX = pcall(require, "tests.game.fixtures.sheets_index")
local SHEETS = {}
if ok_index and type(INDEX) == "table" then
    for _, case in ipairs(INDEX) do
        SHEETS[#SHEETS + 1] = {case = case.case, profile = case.profile, data = require("tests.game.fixtures.sheet_" .. case.case:gsub("-", "_"))}
    end
end

local function player_profile() return script.active_mods["Moshine"] ~= nil end

local function slowest_cycle_ticks(built)
    local worst = 0
    for _, ent in pairs(built.entities) do
        if ent.valid and (ent.type == "assembling-machine" or ent.type == "furnace") then
            local recipe = ent.get_recipe()
            if recipe then
                local ticks = recipe.energy / math.max(ent.crafting_speed, 1e-6) * 60
                if ticks > worst then worst = ticks end
            end
        end
    end
    return worst
end

describe("sheets", function()
    for index, sheet in ipairs(SHEETS) do
        it(sheet.case, function()
            if RRC_OFFLINE then return end
            if (sheet.profile == "player") ~= player_profile() then return end
            local ports = helpers.json_to_table(sheet.data.ports)
            assert(#(ports.problems or {}) == 0, sheet.case .. ": ports.json problems " .. serpent.line(ports.problems))
            local force = game.forces.player
            local stack = Lab.research_stack(force)
            if ports.force then
                if ports.force.bulk_inserter_capacity_bonus then force.bulk_inserter_capacity_bonus = ports.force.bulk_inserter_capacity_bonus end
                if ports.force.inserter_stack_size_bonus then force.inserter_stack_size_bonus = ports.force.inserter_stack_size_bonus end
            end
            local surface = Lab.surface()
            local box = ports.bbox
            local origin = {index * 512, 0}
            Lab.prepare(surface, {{origin[1] + box[1] - 16, origin[2] + box[2] - 16}, {origin[1] + box[3] + 16, origin[2] + box[4] + 16}})
            local imported, code = Lab.import_ok(sheet.data.bp)
            assert(imported, sheet.case .. ": engine refused the blueprint string (" .. tostring(code) .. ")")
            local built = Lab.build(surface, force, sheet.data.bp, origin)
            assert(#built.refused == 0, sheet.case .. ": " .. #built.refused .. " entities do not place: " .. serpent.line(built.refused))
            assert(Lab.power(surface, force, built), sheet.case .. ": lab power could not reach a pole")
            local feeds, port_belts = {}, {}
            for _, f in ipairs(ports.feeds) do
                local ent = Lab.at(surface, built, f.tile[1], f.tile[2])
                assert(Lab.feed_shape_ok(ent, f.fluid), sheet.case .. ": FEED_PORT_SHAPE at " .. f.tile[1] .. "," .. f.tile[2])
                feeds[#feeds + 1] = {entity = ent, item = f.item, fluid = f.fluid}
                if f.item then port_belts[#port_belts + 1] = ent end
            end
            local sinks = {}
            for _, s in ipairs(ports.sinks) do
                sinks[#sinks + 1] = {entity = Lab.at(surface, built, s.tile[1], s.tile[2]), got = {}, items = s.items}
            end
            local speed = 0.03125
            for _, ent in pairs(built.entities) do
                if ent.valid and ent.type == "transport-belt" then speed = math.max(speed, ent.prototype.belt_speed) end
            end
            local warm = math.max(3600, math.ceil(((box[3] - box[1]) + (box[4] - box[2])) * 2 / speed) + 600)
            local window = math.max(7200, math.ceil(10 * slowest_cycle_ticks(built)))
            local short, samples = 0, 0
            local t0 = game.tick
            game.speed = 1000
            on_tick(function()
                local t = game.tick - t0
                Lab.feed_tick(feeds, stack)
                Lab.sink_tick(sinks, t >= warm)
                if t >= warm and t % 60 == 0 then
                    samples = samples + 1
                    for _, belt in ipairs(port_belts) do
                        for lane = 1, 2 do
                            local det = belt.get_transport_line(lane).get_detailed_contents()
                            local full = #det >= 4
                            for _, d in pairs(det) do if d.stack.count ~= stack then full = false end end
                            if not full then short = short + 1 end
                        end
                    end
                end
                if t < warm + window then return end
                game.speed = 1
                local problems = {}
                if short > 0 then problems[#problems + 1] = "FEED_SHORT " .. short .. " lane samples of " .. samples * 2 * #port_belts end
                local got = {}
                for _, s in ipairs(sinks) do
                    local allowed = {}
                    for _, n in ipairs(s.items) do allowed[n] = true end
                    for name, count in pairs(s.got) do
                        if not allowed[name] then problems[#problems + 1] = "foreign " .. name .. " at sink" end
                        got[name] = (got[name] or 0) + count
                    end
                end
                local lines = {}
                for full_name, rate in pairs(ports.targets) do
                    local name = full_name:gsub("^item/", "")
                    local per_s = (got[name] or 0) / (window / 60)
                    lines[#lines + 1] = string.format("%s %.3f/s of %.3f/s", name, per_s, rate)
                    if per_s < 0.95 * rate then problems[#problems + 1] = string.format("SHORT %s %.3f < 0.95 x %.3f", name, per_s, rate) end
                end
                if #problems > 0 then
                    local names = {}
                    for k, v in pairs(defines.entity_status) do names[v] = k end
                    local census = {}
                    for _, ent in pairs(built.entities) do
                        if ent.valid and ent.status then
                            local k = ent.type .. ":" .. (names[ent.status] or tostring(ent.status))
                            census[k] = (census[k] or 0) + 1
                        end
                    end
                    log("SHEET-STATUS " .. sheet.case .. " " .. serpent.line(census))
                    for _, ent in pairs(built.entities) do
                        if ent.valid and (ent.type == "furnace" or ent.type == "assembling-machine") then
                            local r = ent.get_recipe()
                            log(string.format("SHEET-MACHINE %s %s at %.1f,%.1f recipe=%s status=%s energy=%s in=%s out=%s fluids=%s",
                                sheet.case, ent.name, ent.position.x - origin[1], ent.position.y - origin[2], r and r.name or "-",
                                names[ent.status] or "?", tostring(ent.energy),
                                serpent.line(ent.get_inventory(defines.inventory.crafter_input) and ent.get_inventory(defines.inventory.crafter_input).get_contents() or {}),
                                serpent.line(ent.get_inventory(defines.inventory.crafter_output) and ent.get_inventory(defines.inventory.crafter_output).get_contents() or {}),
                                serpent.line(ent.get_fluid_contents())))
                        end
                    end
                end
                log("SHEET-SIM " .. sheet.case .. " stack=" .. stack .. " warm=" .. warm .. " window=" .. window .. " " .. table.concat(lines, "; "))
                assert(#problems == 0, sheet.case .. ": " .. table.concat(problems, "; ") .. " | " .. table.concat(lines, "; "))
                return false
            end)
        end)
    end
end)

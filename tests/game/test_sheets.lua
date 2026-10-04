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
        SHEETS[#SHEETS + 1] = {case = case.case, profile = case.profile, data = require("tests.game.fixtures.sheet_" .. (case.case:gsub("[-%.]", "_")))}
    end
end

local function player_profile() return script.active_mods["Moshine"] ~= nil end

--Sheets marked skipped (player 2026-10-04). Each stays registered so the report shows it as skipped, not gone.
local SKIPPED = {
    ["player-magenta-science-10s"] = "skipped 2026-10-04 (player): magenta builds too slowly; re-enable once generation performance is improved significantly",
}

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
    --Offline the embedded fixtures do not exist (tools/game_stage.sh writes them): check the sheets are there to stage.
    if not ok_index then
        it("sheet fixtures exist to stage", function()
            local pipe = io.popen("ls tests/fixtures/sheets/*.bp.txt | wc -l")
            local n = tonumber(pipe:read("*l")); pipe:close()
            assert.is_true(n and n > 0, "sheet fixtures under tests/fixtures/sheets")
        end)
    end
    for index, sheet in ipairs(SHEETS) do
        local register = SKIPPED[sheet.case] and it.skip or it
        register(sheet.case, function()
            if RRC_OFFLINE then return end
            if (sheet.profile == "player") ~= player_profile() then return end
            local only = sheet.case:match("^vanilla%-(%d+%.%d+)%-")
            if only and only ~= (script.active_mods.base or ""):match("^(%d+%.%d+)") then return end
            local ports = helpers.json_to_table(sheet.data.ports)
            assert(#(ports.problems or {}) == 0, sheet.case .. ": ports.json problems " .. serpent.line(ports.problems))
            local force = game.forces.player
            local stack = Lab.research_stack(force)
            if ports.force then
                if ports.force.bulk_inserter_capacity_bonus then force.bulk_inserter_capacity_bonus = ports.force.bulk_inserter_capacity_bonus end
                if ports.force.inserter_stack_size_bonus then force.inserter_stack_size_bonus = ports.force.inserter_stack_size_bonus end
                --The player's recipe productivity research (export environment.force.research): the real game has it.
                for recipe, bonus in pairs(ports.force.research or {}) do
                    if force.recipes[recipe] then force.recipes[recipe].productivity_bonus = bonus end
                end
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
            --Adaptive measuring (G4): after warm-up, 3600-tick windows. Pass as soon as one window reaches every target
            --x0.95; fail when two windows in a row change by < 2% (plateau) or at 60000 ticks. A long chain (green-1s
            --0.40/s at 3600 warm-up, 0.79/s at 18000) is judged on its steady state, not on its fill time.
            local WINDOW, LIMIT = 3600, 60000
            local window = WINDOW
            local short, samples = 0, 0
            local t0, window_start, history = game.tick, nil, {}
            local function rates_now()
                local got = {}
                for _, s in ipairs(sinks) do for name, count in pairs(s.got) do got[name] = (got[name] or 0) + count end end
                local out, worst = {}, math.huge
                for full_name, rate in pairs(ports.targets) do
                    local name = full_name:gsub("^item/", "")
                    local per_s = (got[name] or 0) / (WINDOW / 60)
                    out[name] = per_s
                    worst = math.min(worst, per_s / rate)
                end
                return out, worst
            end
            game.speed = 1000
            on_tick(function()
                local t = game.tick - t0
                Lab.feed_tick(feeds, stack)
                local measuring = t >= warm
                if measuring and not window_start then window_start = t end
                Lab.sink_tick(sinks, measuring)
                if measuring and t % 60 == 0 then
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
                if not window_start or t - window_start < WINDOW then return end
                local per, worst = rates_now()
                history[#history + 1] = worst
                log(string.format("SHEET-WINDOW %s t=%d worst=%.3f %s", sheet.case, t, worst, serpent.line(per)))
                local done = worst >= 0.95 or t >= LIMIT
                if #history >= 2 and math.abs(history[#history] - history[#history - 1]) < 0.02 * math.max(history[#history], 1e-9) then done = true end
                if not done then
                    for _, s in ipairs(sinks) do s.got = {} end
                    window_start = t
                    return
                end
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
                local per = rates_now()
                for full_name, rate in pairs(ports.targets) do
                    local name = full_name:gsub("^item/", "")
                    local per_s = per[name] or 0
                    lines[#lines + 1] = string.format("%s %.3f/s of %.3f/s", name, per_s, rate)
                    if per_s < 0.95 * rate then problems[#problems + 1] = string.format("SHORT %s %.3f < 0.95 x %.3f", name, per_s, rate) end
                end
                log("SHEET-SIM " .. sheet.case .. " stack=" .. stack .. " warm=" .. warm .. " window=" .. window .. " " .. table.concat(lines, "; "))
                assert(#problems == 0, sheet.case .. ": " .. table.concat(problems, "; ") .. " | " .. table.concat(lines, "; "))
                return false
            end)
        end)
    end
end)

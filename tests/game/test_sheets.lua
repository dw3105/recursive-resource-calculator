--Sheet sims use calculation refs and meter their feeds from tick 0 (Metered feed).
--Fixtures: tests/fixtures/sheets/<case>.bp.txt + <case>.ports.json (tools/sheet_ports.py), embedded by
--tools/game_stage.sh as tests.game.fixtures.sheets_index. A sheet runs only in its profile (player sheets need the
--player's mods: RRC_PROFILE=player).
local Lab = require "tests.game.lib.lab"
local ok_index, INDEX = pcall(require, "tests.game.fixtures.sheets_index")
local SHEETS = {}
if ok_index and type(INDEX) == "table" then
    for _, case in ipairs(INDEX) do
        local module = case.case:gsub("[-%.]", "_")
        local refs
        if case.case ~= "player-magenta-science-10s" then refs = require("tests.game.fixtures." .. module .. "_refs") end
        SHEETS[#SHEETS + 1] = {case = case.case, profile = case.profile,
            data = require("tests.game.fixtures.sheet_" .. module), refs = refs}
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
            --Staged refs are JSON text (tools/game_stage.sh), decoded here like ports.
            local refs = type(sheet.refs) == "string" and helpers.json_to_table(sheet.refs) or sheet.refs
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
            local feeds = {}
            for _, f in ipairs(ports.feeds) do
                local ent = Lab.at(surface, built, f.tile[1], f.tile[2])
                assert(Lab.feed_shape_ok(ent, f.fluid), sheet.case .. ": FEED_PORT_SHAPE at " .. f.tile[1] .. "," .. f.tile[2])
                feeds[#feeds + 1] = {entity = ent, item = f.item, fluid = f.fluid}
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
            --After warm-up, use 3600-tick windows and stop when every output changes by <2% between windows or at 60000 ticks.
            --Steady detection on short windows (every output > 0, two windows within 2%), then ONE judging window long
            --enough for 600 items of the slowest output: at 1/s a 3600-tick window holds 60 items and one item of
            --phase is 1.7% of the 2% band (red-1s read 0.967, 2026-10-05); zero output read as steady (R=0.000).
            local WINDOW, LIMIT = 3600, 60000
            local min_rate = math.huge
            for _, rate in pairs(refs.outputs) do min_rate = math.min(min_rate, rate) end
            local LONG = math.max(WINDOW, math.ceil(600 / min_rate) * 60)
            local window, phase = WINDOW, "detect"
            local t0, window_start, history, pool = game.tick, nil, {}, nil
            local function rates_now()
                local got = {}
                for _, s in ipairs(sinks) do for name, count in pairs(s.got) do got[name] = (got[name] or 0) + count end end
                local out, worst = {}, math.huge
                for full_name, rate in pairs(refs.outputs) do
                    local name = full_name:match("^[^/]+/(.*)$") or full_name
                    local per_s = (got[name] or 0) / (window / 60)
                    out[full_name] = per_s
                    worst = math.min(worst, per_s / rate)
                end
                return out, worst
            end
            --Warm-up plus steady windows can pass the FactorioTest 36000-tick default (green-1s, blue): own limit.
            async(warm + LIMIT + LONG + 3600)
            game.speed = 1000
            on_tick(function()
                local t = game.tick - t0
                local measuring = t >= warm
                --Metered from tick 0 (2026-10-05): a Port feed fill left full stacked belts that rounded-up machines
                --ate for minutes, so steady windows read R=1.05 on metered input (red-10s 10.5/s of 10.0).
                if not pool then pool = Lab.meter_new(refs.inputs) end
                Lab.meter_tick(pool, feeds, stack)
                if measuring and not window_start then window_start = t end
                Lab.sink_tick(sinks, measuring)
                if not window_start or t - window_start < window then return end
                local per, worst = rates_now()
                log(string.format("SHEET-WINDOW %s %s t=%d worst=%.3f %s", sheet.case, phase, t, worst, serpent.line(per)))
                if phase == "detect" then
                    history[#history + 1] = per
                    local steady = #history >= 2
                    for name, value in pairs(per) do
                        local previous = history[#history - 1] and history[#history - 1][name] or 0
                        if value <= 0 or math.abs(value - previous) >= 0.02 * value then steady = false; break end
                    end
                    if steady or t >= LIMIT then phase, window = "judge", LONG end
                    for _, s in ipairs(sinks) do s.got = {} end
                    window_start = t
                    return
                end
                game.speed = 1
                local problems = {}
                local got = {}
                for _, s in ipairs(sinks) do
                    local allowed = {}
                    for _, n in ipairs(s.items) do allowed[n] = true end
                    for name, count in pairs(s.got) do
                        if not allowed[name] then problems[#problems + 1] = "foreign " .. name .. " at sink" end
                        got[name] = (got[name] or 0) + count
                    end
                end
                local per = rates_now()
                local judged, judge_problems, lines = Lab.judge(per, refs.outputs)
                for _, problem in ipairs(judge_problems) do problems[#problems + 1] = problem end
                local backlog = Lab.meter_backlog(pool, feeds, stack)
                if #backlog > 0 then problems[#problems + 1] = "POOL_BACKLOG " .. table.concat(backlog, ",") end
                log("SHEET-SIM " .. sheet.case .. " stack=" .. stack .. " warm=" .. warm .. " window=" .. window .. " " .. table.concat(lines, "; "))
                assert(judged and #problems == 0, sheet.case .. ": " .. table.concat(problems, "; ") .. " | " .. table.concat(lines, "; "))
                done()
                return false
            end)
        end)
    end
end)

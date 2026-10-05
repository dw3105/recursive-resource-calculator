--Sheet sims use calculation refs: Port feed + Pre-fill (default) or Metered feed (RRC_FEED=metered), judged by Lab.settle / Lab.floor_pass.
--Fixtures: tests/fixtures/sheets/<case>.bp.txt + <case>.ports.json (tools/sheet_ports.py), embedded by
--tools/game_stage.sh as tests.game.fixtures.sheets_index. A sheet runs only in its profile (player sheets need the
--player's mods: RRC_PROFILE=player).
--Port feed + Pre-fill by default (player 2026-10-05: maximize input filling); RRC_FEED=metered (tools/game_test.sh) = Metered feed.
local ok_profile_map, PROFILE_MAP = pcall(require, "tests.game.profile_map")
local FULL_FEED = not (ok_profile_map and type(PROFILE_MAP) == "table" and PROFILE_MAP.feed == "metered")
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
            local feed_full = FULL_FEED
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
            --After warm-up, metered windows (Lab.window_ticks) until output stabilizes (Lab.settle); R = mean of the 3 stable windows.
            local window = Lab.window_ticks(refs.outputs)
            local t0, window_start, history, pool = game.tick, nil, {}, nil
            local warmed, warm_stock, prefilled = false, nil, false
            --Judged on production (Lab.made deltas over the window); the sink count is the cross-check.
            local made_start
            local function rates_now()
                local got = {}
                for _, s in ipairs(sinks) do for name, count in pairs(s.got) do got[name] = (got[name] or 0) + count end end
                local made_now = Lab.made(built.entities, refs.outputs)
                local out, sunk, worst = {}, {}, math.huge
                for full_name, rate in pairs(refs.outputs) do
                    local name = full_name:match("^[^/]+/(.*)$") or full_name
                    sunk[full_name] = (got[name] or 0) / (window / 60)
                    out[full_name] = ((made_now[full_name] or 0) - ((made_start or {})[full_name] or 0)) / (window / 60)
                    worst = math.min(worst, out[full_name] / rate)
                end
                made_start = made_now
                return out, worst, sunk
            end
            --Settling has no tick limit of its own (player Q14); the 120 s per-check cap ends a Case that never settles.
            async(10000000)
            game.speed = 1000
            on_tick(function()
                local t = game.tick - t0
                local measuring = warmed
                --Warm-up: full feed primes machines, pipes and inner belts (at least belt travel, then until inner stock stops
                --growing, Lab.warm_ready); at its end input-only belts are emptied (Lab.clear_input_belts), then Metered feed only.
                if not measuring then
                    Lab.feed_tick(feeds, stack)
                    if t >= warm and (t - warm) % Lab.WARM_STEP == 0 then
                        if feed_full and not prefilled then
                            prefilled = true
                            log(string.format("SHEET-PREFILL %s t=%d items=%d", sheet.case, t, Lab.prefill_inner(built.entities, refs.inputs, refs.outputs, stack)))
                        end
                        local stock = Lab.inner_stock(built.entities, refs.inputs, refs.outputs)
                        if Lab.warm_ready(warm_stock, stock, prefilled) or t - warm >= Lab.WARM_CAP then
                            warmed, warm = true, t
                            log(string.format("SHEET-WARM %s t=%d inner=%d window=%d", sheet.case, t, stock, window))
                        end
                        warm_stock = stock
                    end
                else
                    if not pool then
                        pool = Lab.meter_new(refs.inputs)
                        if not feed_full then log(string.format("SHEET-CLEAR %s t=%d items=%d", sheet.case, t, Lab.clear_input_belts(built.entities, refs.inputs))) end
                    end
                    if feed_full then Lab.feed_tick(feeds, stack) else Lab.meter_tick(pool, feeds, stack) end  --Port feed (default) or Metered feed
                end
                if measuring and not window_start then window_start = t; made_start = Lab.made(built.entities, refs.outputs) end
                Lab.sink_tick(sinks, measuring)
                --Every name a sink ever saw while measuring, for the foreign-item check (s.got resets per window).
                if measuring then for _, s in ipairs(sinks) do s.seen = s.seen or {}; for name in pairs(s.got) do s.seen[name] = true end end end
                if not window_start or t - window_start < window then return end
                local per, worst, sunk = rates_now()
                log(string.format("SHEET-WINDOW %s t=%d worst=%.3f made=%s sunk=%s inner=%d", sheet.case, t, worst, serpent.line(per), serpent.line(sunk),
                    Lab.inner_stock(built.entities, refs.inputs, refs.outputs)))
                for _, s in ipairs(sinks) do s.got = {} end
                window_start = t
                local stable, mean_per, mean_sunk, grew = Lab.settle(history, per, sunk, window / 60, Lab.inner_stock(built.entities, refs.inputs, refs.outputs))
                do local c = {} for name, m in pairs(pool) do c[name] = m.credit end history[#history].credit = c end
                if not stable then
                    stable, mean_per, mean_sunk = Lab.floor_pass(history, refs.outputs)
                    if not stable then return end
                    grew = false
                end
                per, sunk = mean_per, mean_sunk
                game.speed = 1
                local problems = {}
                for _, s in ipairs(sinks) do
                    local allowed = {}
                    for _, n in ipairs(s.items) do allowed[n] = true end
                    for name in pairs(s.seen or {}) do
                        if not allowed[name] then problems[#problems + 1] = "foreign " .. name .. " at sink" end
                    end
                end
                local judged, judge_problems, lines = Lab.judge(per, refs.outputs)
                --Stock still growing and short: buffers may still be filling; keep measuring (Lab.settle).
                if not judged and grew then game.speed = 1000; return end
                --Cross-check: what reached the sinks over the judged window is within 5% of what was made (hand loads in
                --flight at both window edges), else the output path loses items.
                for full_name, made in pairs(per) do
                    if made > 0 and math.abs((sunk[full_name] or 0) - made) > 0.05 * made then
                        problems[#problems + 1] = string.format("SINK_DIFF %s made %.3f/s sunk %.3f/s", full_name, made, sunk[full_name] or 0)
                    end
                end
                for _, problem in ipairs(judge_problems) do problems[#problems + 1] = problem end
                local backlog = Lab.meter_backlog(pool, feeds, stack, (history[#history - Lab.SETTLE_WINDOWS] or {}).credit)
                if #backlog > 0 then problems[#problems + 1] = "POOL_BACKLOG " .. table.concat(backlog, ",") end
                log("SHEET-SIM " .. sheet.case .. " stack=" .. stack .. " warm=" .. warm .. " settled_t=" .. t .. " " .. table.concat(lines, "; "))
                assert(judged and #problems == 0, sheet.case .. ": " .. table.concat(problems, "; ") .. " | " .. table.concat(lines, "; "))
                done()
                return false
            end)
        end)
    end
end)

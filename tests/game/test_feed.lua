--Round 48 G10d, proven 2.0.77 + 2.1.20 (2026-09-29): the lab feeder (insert_at_back on both lines every tick) keeps a
--straight belt of every tier at its exact lane max, every stack at max size, no gap. Sheet sims rely on it (D7).
--Warmup must exceed belt travel time: 600 ticks read yellow at 62% because items had not crossed 40 tiles yet.
local TIERS = {"transport-belt", "fast-transport-belt", "express-transport-belt", "turbo-transport-belt"}
local LEN, WARM, WINDOW = 40, 2000, 1800

local function lab()
    local s = game.surfaces["rrc-feed-lab"]
    if s then return s end
    s = game.create_surface("rrc-feed-lab", {width = 256, height = 256})
    s.generate_with_lab_tiles = true
    s.request_to_generate_chunks({0, 0}, 3)
    s.force_generate_chunk_requests()
    return s
end

local function research_stack(force)
    local names = {}
    for name, tech in pairs(force.technologies) do
        for _, e in pairs(tech.prototype.effects or {}) do
            if e.type == "belt-stack-size-bonus" then tech.researched = true; names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

describe("feed", function()
    it("feeder fills both lanes at max stack", function()
        if RRC_OFFLINE then return end
        game.speed = 64
        local force = game.forces.player
        local techs = research_stack(force)
        local stack = 1 + force.belt_stack_size_bonus
        local s = lab()
        local rows, report = {}, {techs = techs, bonus = force.belt_stack_size_bonus, stack = stack}
        for i0, tier_st in ipairs({{"transport-belt",1},{"transport-belt",0},{"fast-transport-belt",1},{"fast-transport-belt",0},{"express-transport-belt",1},{"express-transport-belt",0},{"turbo-transport-belt",1},{"turbo-transport-belt",0}}) do
            local i, tier, st = i0, tier_st[1], (tier_st[2] == 0 and stack or 1)
            if prototypes.entity[tier] then
                local belts = {}
                for x = -4, -1 do  --turbo feeder segment ahead of the port belt
                    assert(s.create_entity{name = "turbo-transport-belt", position = {x + 0.5, i * 4 + 0.5},
                        direction = defines.direction.east, force = force}, "place feeder")
                end
                local feeder = s.find_entity("turbo-transport-belt", {-3.5, i * 4 + 0.5})
                for x = 0, LEN - 1 do
                    belts[#belts + 1] = assert(s.create_entity{name = tier, position = {x + 0.5, i * 4 + 0.5},
                        direction = defines.direction.east, force = force}, "place " .. tier)
                end
                rows[#rows + 1] = {st = st, feeder = feeder, tier = tier, belts = belts, speed = prototypes.entity[tier].belt_speed,
                    got = {0, 0}, ins_fail = 0, ins_ok = 0, bad_stack = 0, gaps = 0, samples = 0, stack_seen = {}}
            end
        end
        local tick0 = game.tick
        local api_err
        on_tick(function()
            local t = game.tick - tick0
            for _, r in ipairs(rows) do
                local head, tail = r.belts[1], r.belts[LEN]
                for lane = 1, 2 do
                    local line = head.get_transport_line(lane)
                    local ok, res = pcall(line.insert_at_back, {name = "iron-plate", count = r.st}, r.st)
                    if not ok then api_err = api_err or res elseif res then r.ins_ok = r.ins_ok + 1 else r.ins_fail = r.ins_fail + 1 end
                    local tl = tail.get_transport_line(lane)
                    if t >= WARM then
                        for _, c in pairs(tl.get_contents()) do r.got[lane] = r.got[lane] + c.count end
                    end
                    tl.clear()
                end
                if t >= WARM and t % 60 == 0 then
                    r.samples = r.samples + 1
                    for b = 1, LEN - 1 do
                        for lane = 1, 2 do
                            local det = r.belts[b].get_transport_line(lane).get_detailed_contents()
                            if #det < 4 then r.gaps = r.gaps + 1 end
                            for _, d in pairs(det) do
                                r.stack_seen[d.stack.count] = (r.stack_seen[d.stack.count] or 0) + 1
                                if d.stack.count ~= r.st then r.bad_stack = r.bad_stack + 1 end
                            end
                        end
                    end
                end
            end
            if t >= WARM + WINDOW then
                for _, r in ipairs(rows) do
                    local secs = WINDOW / 60
                    local max_lane = r.speed * 60 * 8 / 2 * r.st  -- belt_speed tiles/tick; 4 stacks per lane per tile
                    assert.is_true(math.abs(r.got[1] / secs - max_lane) <= 0.01 * max_lane and math.abs(r.got[2] / secs - max_lane) <= 0.01 * max_lane,
                        string.format("%s st=%d lanes %.2f/%.2f of %.2f", r.tier, r.st, r.got[1] / secs, r.got[2] / secs, max_lane))
                    assert.are_equal(0, r.bad_stack, r.tier .. " stacks below max")
                    assert.are_equal(0, r.gaps, r.tier .. " gaps on the belt")
                    assert.is_nil(api_err, tostring(api_err))
                    report[#report + 1] = string.format("%s st=%d lane1=%.2f/s lane2=%.2f/s max=%.2f/s ins_ok=%d ins_fail=%d bad_stack=%d gaps=%d samples=%d seen=%s",
                        r.tier, r.st, r.got[1] / secs, r.got[2] / secs, max_lane, r.ins_ok, r.ins_fail, r.bad_stack, r.gaps, r.samples, serpent.line(r.stack_seen))
                end
                log("FEED " .. serpent.line(report))
                game.speed = 1
                return false
            end
        end)
    end)
end)

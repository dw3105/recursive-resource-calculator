--Round 54 engine fact: which lane an inserter drops on, by where it stands relative to the belt's heading.
--The validator's lane walk and tools/lane_sim.py both seed lanes from this. Line 1 is the belt's left lane, line 2
--its right lane (defines.transport_line). Sixteen stands: four belt headings x hand behind / ahead / left / right.
local DIRS = {
    {name = "north", d = defines.direction.north, v = {0, -1}}, {name = "east", d = defines.direction.east, v = {1, 0}},
    {name = "south", d = defines.direction.south, v = {0, 1}}, {name = "west", d = defines.direction.west, v = {-1, 0}},
}
local function dir_of(v)
    for _, entry in ipairs(DIRS) do if entry.v[1] == v[1] and entry.v[2] == v[2] then return entry.d end end
end

describe("drop lane", function()
    it("inserter drop lane by stand", function()
        if RRC_OFFLINE then return end
        game.speed = 64
        local force = game.forces.player
        local s = game.surfaces["rrc-drop-lane"] or game.create_surface("rrc-drop-lane", {width = 256, height = 256})
        s.generate_with_lab_tiles = true
        s.request_to_generate_chunks({0, 0}, 4)
        s.force_generate_chunk_requests()
        local rows = {}
        for i, belt_dir in ipairs(DIRS) do
            local v = belt_dir.v
            --right of the heading (screen y grows south): (x, y) -> (-y, x)
            local stands = {behind = {-v[1], -v[2]}, ahead = {v[1], v[2]}, right = {-v[2], v[1]}, left = {v[2], -v[1]}}
            local j = 0
            for _, stand in ipairs({"behind", "ahead", "left", "right"}) do
                j = j + 1
                local o = stands[stand]
                local bx, by = i * 10 - 30 + 0.5, j * 10 - 30 + 0.5
                local belt = assert(s.create_entity{name = "transport-belt", position = {bx, by}, direction = belt_dir.d, force = force}, "belt")
                --An inserter's direction points at its pickup: the chest sits two tiles from the belt, past the hand.
                local hand = assert(s.create_entity{name = "burner-inserter", position = {bx + o[1], by + o[2]}, direction = dir_of(o), force = force}, "hand")
                local chest = assert(s.create_entity{name = "wooden-chest", position = {bx + 2 * o[1], by + 2 * o[2]}, force = force}, "chest")
                chest.insert({name = "iron-plate", count = 40})
                local fuel = hand.get_fuel_inventory()
                if fuel then fuel.insert({name = "coal", count = 5}) end
                rows[#rows + 1] = {belt = belt, heading = belt_dir.name, stand = stand}
            end
        end
        local tick0 = game.tick
        on_tick(function()
            if game.tick - tick0 < 900 then return end
            local out, wrong = {}, {}
            for _, r in ipairs(rows) do
                local left, right = r.belt.get_transport_line(1).get_item_count(), r.belt.get_transport_line(2).get_item_count()
                out[#out + 1] = string.format("%s/%s L=%d R=%d", r.heading, r.stand, left, right)
                --Proven 2.0.77 + 2.1.20 (2026-10-01): a hand on the belt's right drops on the left lane (its far lane);
                --a hand on the left, behind or ahead drops on the right lane.
                local want_left = r.stand == "right"
                if (want_left and (left == 0 or right ~= 0)) or (not want_left and (right == 0 or left ~= 0)) then
                    wrong[#wrong + 1] = out[#out]
                end
            end
            log("DROPLANE " .. table.concat(out, "; "))
            game.speed = 1
            assert.are_equal(0, #wrong, "drop lane differs: " .. table.concat(wrong, "; "))
            return false
        end)
    end)
end)

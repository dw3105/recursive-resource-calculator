--Tile occupancy, rectangle algebra, rotation, placement and infrastructure geometry
local H = require "tests.harness"
local Grid = require "logic.bp.grid"

local function key(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function sorted_cells(rect)
    local cells = {}
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            cells[#cells + 1] = key(x, y)
        end
    end
    table.sort(cells)
    return cells
end

local function rotate_relative_member(member, block_w, block_h)
    local x, y, w, h = member.x, member.y, member.w, member.h
    local frame_w, frame_h = block_w, block_h
    for _ = 1, 4 do
        x, y, w, h = Grid.rotate_rect(x, y, w, h, frame_w, frame_h, Grid.EAST)
        frame_w, frame_h = frame_h, frame_w
    end
    return {x = x, y = y, w = w, h = h}
end

local function rotate_relative_port(port, block_w, block_h)
    local x, y = port.attach_dx, port.attach_dy
    local frame_w, frame_h = block_w, block_h
    local dir = port.normal_dir
    for _ = 1, 4 do
        x, y = Grid.rotate_rect(x, y, 1, 1, frame_w, frame_h, Grid.EAST)
        frame_w, frame_h = frame_h, frame_w
        dir = Grid.rotate_dir(dir, Grid.EAST)
    end
    return {x = x, y = y, dir = dir}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " G1 a central obstacle leaves a tall MaxRects alternative", function()
        local regions = Grid.free_regions(Grid.rect(0, 0, 10, 10), {Grid.rect(4, 4, 2, 2)})
        local found = false
        for _, region in ipairs(regions) do
            if region.w >= 3 and region.h >= 8 then found = true end
        end
        H.equal(found, true, "a 3 by 8 block still has a fitting free region")
    end)

    H.test(shape .. " G2 subtract keeps overlapping alternatives", function()
        local pieces = Grid.subtract(Grid.rect(0, 0, 10, 10), Grid.rect(4, 4, 2, 2))
        H.equal(#pieces, 4, "an interior cut has four alternatives")
        local total = 0
        for _, piece in ipairs(pieces) do total = total + piece.w * piece.h end
        H.equal(total > 10 * 10 - 2 * 2, true, "alternative areas are not a partition sum")
        local overlaps = false
        for i = 1, #pieces do
            for j = i + 1, #pieces do
                if Grid.intersects(pieces[i], pieces[j]) then overlaps = true end
            end
        end
        H.equal(overlaps, true, "alternatives overlap")
    end)

    H.test(shape .. " G3 prune drops contained rectangles and reports it", function()
        local kept, dropped = Grid.prune({Grid.rect(0, 0, 10, 10), Grid.rect(2, 2, 3, 3), Grid.rect(20, 20, 1, 1)})
        H.deep_equal(kept, {Grid.rect(0, 0, 10, 10), Grid.rect(20, 20, 1, 1)}, "stable survivors")
        H.equal(dropped, 1, "one rectangle was dropped")
    end)

    H.test(shape .. " G4 every direction places a member at independently enumerated cells", function()
        local block = {w = 8, h = 6}
        local member = {x = 1, y = 1, w = 3, h = 2, dir = Grid.NORTH}
        local expected = {
            [Grid.NORTH] = {"1,1", "1,2", "2,1", "2,2", "3,1", "3,2"},
            [Grid.EAST] = {"3,1", "3,2", "3,3", "4,1", "4,2", "4,3"},
            [Grid.SOUTH] = {"4,3", "4,4", "5,3", "5,4", "6,3", "6,4"},
            [Grid.WEST] = {"1,4", "1,5", "1,6", "2,4", "2,5", "2,6"},
        }
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Grid.place_member(block, {x = 0, y = 0, dir = dir}, member)
            H.deep_equal(sorted_cells(placed), expected[dir], "occupied cells for direction " .. tostring(dir))
        end
    end)

    H.test(shape .. " G5 four rotations restore every member and port exactly", function()
        local member = {x = 1, y = 1, w = 3, h = 2, dir = Grid.WEST}
        local member_back = rotate_relative_member(member, 8, 6)
        H.deep_equal(member_back, {x = 1, y = 1, w = 3, h = 2}, "member rectangle after four turns")
        H.equal(Grid.rotate_dir(member.dir, Grid.EAST * 4), member.dir, "member direction after four turns")

        local port = {attach_dx = -1, attach_dy = 2, normal_dir = Grid.EAST}
        local port_back = rotate_relative_port(port, 8, 6)
        H.deep_equal(port_back, {x = -1, y = 2, dir = Grid.EAST}, "port after four turns")
    end)

    H.test(shape .. " G6 an adjacent port remains adjacent after every rotation", function()
        local block = {w = 8, h = 6}
        local ports = {
            {attach_dx = -1, attach_dy = 2, normal_dir = Grid.WEST},
            {attach_dx = 8, attach_dy = 2, normal_dir = Grid.EAST},
            {attach_dx = 3, attach_dy = -1, normal_dir = Grid.NORTH},
            {attach_dx = 3, attach_dy = 6, normal_dir = Grid.SOUTH},
        }
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local oriented_w, oriented_h = Grid.rotate_size(block.w, block.h, dir)
            for _, port in ipairs(ports) do
                local placed = Grid.place_port(block, {x = 50, y = 70, dir = dir}, port)
                local dx, dy = placed.x - 50, placed.y - 70
                local adjacent = (dx == -1 or dx == oriented_w) and dy >= 0 and dy < oriented_h
                    or (dy == -1 or dy == oriented_h) and dx >= 0 and dx < oriented_w
                H.equal(adjacent, true, "port remains adjacent in direction " .. tostring(dir))
            end
        end
    end)

    H.test(shape .. " G7 rotating a vector never adds a tile shift", function()
        local vx, vy = Grid.rotate_vector(5, -2, Grid.EAST)
        H.deep_equal({x = vx, y = vy}, {x = 2, y = 5}, "east vector rotation")
        local rx, ry = 5, -2
        for _ = 1, 4 do rx, ry = Grid.rotate_vector(rx, ry, Grid.EAST) end
        H.deep_equal({x = rx, y = ry}, {x = 5, y = -2}, "four vector rotations")
    end)

    H.test(shape .. " G8 odd and even entities derive half and whole centres", function()
        H.deep_equal(Grid.centre(Grid.rect(10, 20, 3, 5)), {x = 11.5, y = 22.5}, "odd footprint centre")
        H.deep_equal(Grid.centre(Grid.rect(10, 20, 4, 6)), {x = 12, y = 23}, "even footprint centre")
    end)

    H.test(shape .. " G9 can_place refuses overlap but accepts an allowed owner", function()
        local grid = Grid.new(6, 6)
        Grid.fill(grid, Grid.rect(2, 2, 2, 2), 7)
        local ok, owner = Grid.can_place(grid, Grid.rect(3, 3, 2, 2))
        H.equal(ok, false, "overlap is refused")
        H.equal(owner, 7, "the blocking owner is returned")
        local allowed, allowed_owner = Grid.can_place(grid, Grid.rect(3, 3, 2, 2), {[7] = true})
        H.equal(allowed, true, "an explicitly allowed owner overlaps")
        H.equal(allowed_owner, nil, "allowed overlap has no blocker")
        H.equal(Grid.get(grid, -1, 0), nil, "outside reads are nil")
    end)

    H.test(shape .. " G10 a beacon area is not occupancy", function()
        local grid = Grid.new(20, 20)
        local area = Grid.beacon_area(Grid.rect(8, 8, 3, 3), 4, 4)
        H.equal(Grid.get(grid, area.x, area.y), nil, "beacon bounds do not fill cells")
        H.equal(Grid.get(grid, 9, 9), nil, "the beacon footprint is not implicitly filled")
    end)

    H.test(shape .. " G11 roboports use the supplied connection distance", function()
        local robo = Grid.robo_grid({cols = 2, rows = 2, tile_w = 4, tile_h = 4, max_connection_distance = 11})
        H.equal(robo.spacing_x, 11, "horizontal spacing comes from the argument")
        H.equal(robo.spacing_y, 11, "vertical spacing comes from the argument")
        H.deep_equal(robo.roboports[1], {x = 0, y = 0, w = 4, h = 4}, "first roboport")
        H.deep_equal(robo.roboports[4], {x = 11, y = 11, w = 4, h = 4}, "last roboport")
        H.deep_equal({w = robo.w, h = robo.h}, {w = 15, h = 15}, "envelope contains footprints")
    end)

    H.test(shape .. " G12 edge slots start at the origin and face outward", function()
        local envelope = Grid.rect(10, 20, 8, 5)
        H.deep_equal(Grid.edge_slots(envelope, "top", 3), {
            {x = 10, y = 19, dir = Grid.NORTH}, {x = 13, y = 19, dir = Grid.NORTH},
            {x = 16, y = 19, dir = Grid.NORTH},
        }, "top slots")
        H.deep_equal(Grid.edge_slots(envelope, "right", 2), {
            {x = 18, y = 20, dir = Grid.EAST}, {x = 18, y = 22, dir = Grid.EAST},
            {x = 18, y = 24, dir = Grid.EAST},
        }, "right slots")
    end)

    H.test(shape .. " G13 can_place refuses a right overhang but accepts the flush edge", function()
        local grid = Grid.new(6, 6)
        local flush = Grid.can_place(grid, Grid.rect(4, 2, 2, 2))
        H.equal(flush, true, "right-flush rectangle is accepted")
        local overhang = Grid.can_place(grid, Grid.rect(5, 2, 2, 2))
        H.equal(overhang, false, "right overhang is refused")
    end)

    H.test(shape .. " G14 can_place refuses a bottom overhang but accepts the flush edge", function()
        local grid = Grid.new(6, 6)
        local flush = Grid.can_place(grid, Grid.rect(2, 4, 2, 2))
        H.equal(flush, true, "bottom-flush rectangle is accepted")
        local overhang = Grid.can_place(grid, Grid.rect(2, 5, 2, 2))
        H.equal(overhang, false, "bottom overhang is refused")
    end)

    H.test(shape .. " G15 can_place refuses a left overhang but accepts the flush edge", function()
        local grid = Grid.new(6, 6)
        local flush = Grid.can_place(grid, Grid.rect(0, 2, 2, 2))
        H.equal(flush, true, "left-flush rectangle is accepted")
        local overhang = Grid.can_place(grid, Grid.rect(-1, 2, 2, 2))
        H.equal(overhang, false, "left overhang is refused")
    end)

    H.test(shape .. " G16 can_place refuses a top overhang but accepts the flush edge", function()
        local grid = Grid.new(6, 6)
        local flush = Grid.can_place(grid, Grid.rect(2, 0, 2, 2))
        H.equal(flush, true, "top-flush rectangle is accepted")
        local overhang = Grid.can_place(grid, Grid.rect(2, -1, 2, 2))
        H.equal(overhang, false, "top overhang is refused")
    end)

    H.test(shape .. " G17 can_place refuses rectangles wider or taller than the grid", function()
        local grid = Grid.new(6, 6)
        local wider = Grid.can_place(grid, Grid.rect(0, 0, 7, 1))
        H.equal(wider, false, "rectangle wider than the grid is refused")
        local taller = Grid.can_place(grid, Grid.rect(0, 0, 1, 7))
        H.equal(taller, false, "rectangle taller than the grid is refused")
    end)

    H.test(shape .. " G18 can_place refuses a rectangle at negative coordinates", function()
        local grid = Grid.new(6, 6)
        local negative_x = Grid.can_place(grid, Grid.rect(-1, 0, 1, 1))
        H.equal(negative_x, false, "negative x coordinate is refused")
        local negative_y = Grid.can_place(grid, Grid.rect(0, -1, 1, 1))
        H.equal(negative_y, false, "negative y coordinate is refused")
    end)
end

H.done("test_grid")

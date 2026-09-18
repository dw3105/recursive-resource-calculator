--Tile algebra, and the only place in the mod where a rotation is computed.
--
--Owned by lane W1-grid. Four lanes stand on this file, so every one of them must get the same answer for the
--same question. Rotation exists here and nowhere else; a grep test refuses direction arithmetic elsewhere.
--
--Coordinates: one integer tile lattice, origin (0, 0) at the top-left of the roboport grid envelope. A TileRect
--{x, y, w, h} covers tiles x .. x+w-1. An entity centre is derived, never stored: x + w/2, so a 3-wide machine
--sits on a .5 centre and a 4-wide roboport on a whole number, which is what the game's own blueprints show.
--
--Four rotations, four frames, because they are genuinely different operations (east, dir 4, clockwise, y down):
--  rotate_cell(dx, dy, w, h, 4)          -> (h - 1 - dy, dx)          one tile index inside a w x h frame
--  rotate_rect(dx, dy, a, b, w, h, 4)    -> (h - dy - b, dx, b, a)    a sub-rect: its min corner moves by its own size
--  rotate_point(px, py, w, h, 4)         -> (h - py, px)              a continuous point in the block frame
--  rotate_vector(vx, vy, 4)              -> (-vy, vx)                 an entity-relative offset, no translation
--Using the cell formula on a multi-tile rectangle's corner is the classic off-by-one: an 8x6 block whose member
--is x=1, y=1, w=3, h=2 rotates east to x=3, y=1, w=2, h=3, not x=4.
local Grid = {}

--Reserved owners, written into the occupancy cells as negative values; a positive cell is a placed entity ordinal
Grid.RESERVED = {roboport = -1, port = -2, corridor = -3}

Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST = 0, 4, 8, 12

function Grid.rect(x, y, w, h) return {x = x, y = y, w = w, h = h} end
function Grid.new(w, h) return {w = w, h = h, cells = {}} end
function Grid.index(grid, x, y) return nil end
function Grid.get(grid, x, y) return nil end
--allow: a set of owners this placement may overlap (the router may use a reserved corridor; a machine may not)
function Grid.can_place(grid, rect, allow) return false, nil end
function Grid.fill(grid, rect, owner) return grid end
function Grid.clear(grid, rect, owner) return grid end

function Grid.intersects(a, b) return false end
function Grid.contains(a, b) return false end
--The free space left of one rect after a cut: up to four pieces, which may overlap each other. Overlapping free
--regions are the point of MaxRects; their areas can never be added up to mean available space.
function Grid.subtract(free, cut) return {} end
function Grid.prune(rects, limit) return {}, 0 end
function Grid.free_regions(area, obstacles) return {} end

function Grid.rotate_size(w, h, dir) return w, h end
function Grid.rotate_cell(dx, dy, w, h, dir) return dx, dy end
function Grid.rotate_rect(dx, dy, a, b, w, h, dir) return dx, dy, a, b end
function Grid.rotate_point(px, py, w, h, dir) return px, py end
function Grid.rotate_vector(vx, vy, dir) return vx, vy end
function Grid.rotate_dir(d, dir) return d end
function Grid.dir_vector(dir) return 0, 0 end
function Grid.dir_opposite(dir) return dir end
function Grid.dir_from_vector(dx, dy) return nil end

function Grid.centre(rect) return {x = 0, y = 0} end
--The only rotation authority for a block's contents; every other module calls these two rather than doing its own
function Grid.place_member(block, placement, member) return {x = 0, y = 0, w = 0, h = 0, dir = Grid.NORTH} end
function Grid.place_port(block, placement, port) return {x = 0, y = 0, dir = Grid.NORTH} end

--A beacon's influence as a rect, for the packer's bound only. Influence is never written into the occupancy
--cells: beacon areas may overlap each other and cross block boundaries, unlike the entities themselves.
--The exact "does this machine receive this beacon" question belongs to the validator, from collision boxes.
function Grid.beacon_area(rect, supply_w, supply_h) return Grid.rect(0, 0, 0, 0) end

--The roboport grid: cols x rows ports at the widest spacing that still connects, and the envelope around them
function Grid.robo_grid(spec) return {w = 0, h = 0, spacing_x = 0, spacing_y = 0, roboports = {}} end
--Attachment slots along one edge of the envelope, ordered from the origin corner, facing outward
function Grid.edge_slots(envelope, edge, pitch) return {} end

return Grid

--The buffer zone: an empty ring around every producing machine, so belts and inserters always have room.
--The player's rule, 2026-09-23 (screenshots ~/share/RRC/Screenshot 2026-09-23 155116.png and 155945.png):
--  * ring width by ingredient count: 1-2 -> 2 cells, 3 -> 3 cells, 4 or more -> 4 cells;
--  * no other machine or roboport may stand in a machine's ring; belts, undergrounds, splitters, inserters, poles,
--    pipes and beacons may;
--  * two machines of the same name and recipe may share ring space, but only in the same row (equal top y)
--    or the same column (equal left x).
--This module is the whole rule.  Grouping, packing and the validator all call it, so they cannot disagree.
local Buffer = {}

Buffer.MIN_RING, Buffer.MAX_RING = 2, 4

--Ring width for a recipe name, read from the catalog the generator already carries.  A recipe the catalog does
--not know gets the minimum ring.
function Buffer.ring(catalog, recipe)
    local recipes = type(catalog) == "table" and (catalog.recipe or catalog.recipes) or nil
    local entry = type(recipes) == "table" and recipe ~= nil and recipes[recipe] or nil
    local count = type(entry) == "table" and type(entry.ingredients) == "table" and #entry.ingredients or 0
    return math.max(Buffer.MIN_RING, math.min(Buffer.MAX_RING, count))
end

function Buffer.key(name, recipe)
    return tostring(name) .. "|" .. tostring(recipe)
end

--`rect` is the machine footprint {x, y, w, h} in tiles; the zone is that rectangle grown by `ring` on every side.
function Buffer.zone(rect, ring)
    return {x = rect.x - ring, y = rect.y - ring, w = rect.w + 2 * ring, h = rect.h + 2 * ring}
end

local function intersects(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

--A zone record is {rect = machine footprint, ring = width, key = Buffer.key(...)}.  Two records conflict when
--their zones intersect, unless both machines share name and recipe and stand in one row or one column.
function Buffer.conflict(a, b)
    if not intersects(Buffer.zone(a.rect, a.ring), Buffer.zone(b.rect, b.ring)) then return false end
    if a.key == b.key and (a.rect.x == b.rect.x or a.rect.y == b.rect.y) then return false end
    return true
end

return Buffer

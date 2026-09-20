--One world-space box, shared by everyone who asks "does this thing overlap that area".
--
--Why this module exists. The planner and the validator each answered that question their own way, and the two
--answers disagreed. The validator resolved a prototype collision box and rotated it; the planner used tile
--dimensions and compared centres. A machine could therefore be grouped as covered and then rejected as
--uncovered, or the reverse, with nothing in between to notice. Rounds 1-10 shipped that disagreement.
--
--So the conversion lives here once. Both callers use it; neither owns it.
--
--Conventions, stated rather than inferred:
--
--  * A tile rectangle is {x, y, w, h} with x..x+w-1 occupied, matching logic/bp/grid.lua.
--  * A world box is {left, top, right, bottom} in absolute tiles, already rotated.
--  * A supply area is measured as a DISTANCE from the supplying entity's centre, on each axis, exactly as
--    LuaEntityPrototype::get_supply_area_distance reports it. It is never half of a width.
--  * Engine rule: an entity is supplied when its COLLISION BOX OVERLAPS the supply area. Never when its centre
--    sits inside. A 3x3 machine beside a pole overlaps that area while its centre stays outside.
--  * A prototype with no collision box falls back to its tile footprint, centred. That fallback is explicit,
--    so a caller can tell a real box from a substituted one.
--  * Two overlap rules, on purpose, matching what the validator already does:
--      collision overlap is strict  - touching edges do not collide;
--      supply overlap is tolerant by EPSILON - an entity exactly on the boundary is supplied.
local Geometry = {}

local Grid = require "logic.bp.grid"

local EPSILON = 1e-9
local INF = math.huge

Geometry.EPSILON = EPSILON

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= INF and value ~= -INF then return value end
    return fallback
end

--Absolute tolerance scaled to the magnitude being compared, so a coordinate far from the origin is not held to
--a tighter bound than one near it.
function Geometry.tolerance(value)
    return math.max(EPSILON, math.abs(finite(value, 0)) * EPSILON)
end

--A prototype collision box is local, in {left_top = {x, y}, right_bottom = {x, y}} form, and may be asymmetric.
--Rotating it by a quarter turn moves all four corners, so the rotated extent is taken from the corners rather
--than by swapping w and h: an asymmetric box does not survive a naive swap.
--Returns nil when there is no usable box, so the caller can choose the fallback knowingly.
function Geometry.local_box(box, dir)
    if type(box) ~= "table" or type(box.left_top) ~= "table" or type(box.right_bottom) ~= "table" then return nil end
    local left, top = finite(box.left_top.x), finite(box.left_top.y)
    local right, bottom = finite(box.right_bottom.x), finite(box.right_bottom.y)
    if not left or not top or not right or not bottom then return nil end
    local corners = {{x = left, y = top}, {x = left, y = bottom}, {x = right, y = top}, {x = right, y = bottom}}
    local min_x, min_y, max_x, max_y = INF, INF, -INF, -INF
    for _, corner in ipairs(corners) do
        local x, y = Grid.rotate_vector(corner.x, corner.y, dir or Grid.NORTH)
        min_x, min_y = math.min(min_x, x), math.min(min_y, y)
        max_x, max_y = math.max(max_x, x), math.max(max_y, y)
    end
    return {left = min_x, top = min_y, right = max_x, bottom = max_y}
end

--The local box a member falls back to when no prototype box is available: its tile footprint about its centre.
function Geometry.tile_box(w, h)
    local width, height = finite(w, 1), finite(h, 1)
    return {left = -width / 2, top = -height / 2, right = width / 2, bottom = height / 2}
end

--Centre of a member in world tiles. A placed entity may carry an engine-style position; a planner member
--carries a tile rectangle instead. Both are accepted, position first.
function Geometry.center(member, spec)
    if type(member) == "table" and type(member.position) == "table" then
        local x, y = finite(member.position.x), finite(member.position.y)
        if x and y then return x, y end
    end
    local w = finite(member.w, spec and spec.tile_w or 1)
    local h = finite(member.h, spec and spec.tile_h or 1)
    return finite(member.x, 0) + w / 2, finite(member.y, 0) + h / 2
end

--The world box of a member, plus how it was obtained.
--
--  member : {x, y, w, h} or {position = {x, y}}, optionally {dir|direction}, optionally {collision_box}
--  spec   : the catalog entry for that member, optionally {collision_box, tile_w, tile_h}
--
--Returns box, source where source is "collision_box" or "tile_fallback". Callers that must not silently accept
--a substituted footprint can check the second value.
function Geometry.world_box(member, spec)
    member = type(member) == "table" and member or {}
    spec = type(spec) == "table" and spec or {}
    local cx, cy = Geometry.center(member, spec)
    local dir = finite(member.dir or member.direction, Grid.NORTH)
    local source = "collision_box"
    local box = Geometry.local_box(spec.collision_box or member.collision_box, dir)
    if not box then
        source = "tile_fallback"
        box = Geometry.tile_box(finite(member.w, spec.tile_w or 1), finite(member.h, spec.tile_h or 1))
    end
    return {left = cx + box.left, top = cy + box.top, right = cx + box.right, bottom = cy + box.bottom}, source
end

--The supply area of a supplying entity, as a world box. reach_w and reach_h are DISTANCES from its centre.
--The supplier's own footprint is not added: the engine measures the area from the centre, and expanding by
--half a footprint here would hide a one-tile gap.
function Geometry.supply_box(centre_x, centre_y, reach_w, reach_h)
    local rw = finite(reach_w, 0)
    local rh = finite(reach_h, rw)
    return {left = centre_x - rw, top = centre_y - rh, right = centre_x + rw, bottom = centre_y + rh}
end

--COLLISION overlap: strict, no tolerance. Two boxes that merely touch do not collide, because Factorio places
--entities edge to edge all day. This is the rule the validator's collision pass already uses.
function Geometry.boxes_overlap(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end

--SUPPLY overlap: tolerant by EPSILON, so an entity sitting exactly on the boundary of a supply area is
--supplied rather than excluded by float noise. Deliberately a different rule from collision above, and the
--same rule the validator's power pass already applies to poles.
function Geometry.box_overlaps_supply(box, supply)
    if type(box) ~= "table" or type(supply) ~= "table" then return false end
    return box.left < supply.right + EPSILON and supply.left - EPSILON < box.right
        and box.top < supply.bottom + EPSILON and supply.top - EPSILON < box.bottom
end

--The whole question in one call: is this member supplied by an area of the given reach around that centre?
function Geometry.box_in_supply(member, spec, centre_x, centre_y, reach_w, reach_h)
    return Geometry.box_overlaps_supply(Geometry.world_box(member, spec),
        Geometry.supply_box(centre_x, centre_y, reach_w, reach_h))
end

--Convenience for a supplier described by its own tile rectangle rather than a centre.
function Geometry.supply_box_of(supplier, reach_w, reach_h)
    local cx, cy = Geometry.center(supplier)
    return Geometry.supply_box(cx, cy, reach_w, reach_h)
end

return Geometry

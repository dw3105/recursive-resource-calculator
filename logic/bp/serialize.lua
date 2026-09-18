--The blueprint the game will read, and the canonical form the tests compare.
--
--Owned by lane W3-serial. Entity numbers are assigned here and nowhere else, by sorting (y, x, id), so the three
--modules that produce entities can each name theirs with a string id and never collide. Cross references
--(underground partners, ports, wire endpoints) are remapped in one pass afterwards.
--
--Canonical form (GOLD-04) is what a golden compares, never the compressed string: equal factories can compress to
--different bytes. Rules, fixed so an in-game capture and an offline run agree:
--  keys sorted; arrays in their own defined order; entity numbers remapped by (y, x, id); MapPositions written as
--  {x = , y = } objects even where the game accepts a pair; numbers formatted %.17g with integers written whole;
--  volatile metadata dropped; anything that changes layout, connectivity or throughput kept.
local Serialize = {}

Serialize.CANONICAL_VERSION = 1

function Serialize.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "serializing", done_units = 0}}
end

function Serialize.step(state, budget)
    return state
end

--(y, x, id): the order entity numbers are handed out in
function Serialize.entity_order(entities)
    return {}
end

--The comparable form of a blueprint table, plus the version of these rules it was produced under
function Serialize.canonical(blueprint)
    return {}, Serialize.CANONICAL_VERSION
end

return Serialize

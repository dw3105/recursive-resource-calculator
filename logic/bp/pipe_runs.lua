--Round 41: a straight run of plain pipes is buried as one pipe-to-ground pair at publication (the player's hand fix
--of red + green science 10/s: 28 pipes + 18 pipe-to-ground where we laid 54 plain pipes). Stub: lane 234 fills it.
--`work` is route's work table; `h` carries route's own helpers: key(x, y), coordinate_from_key(key),
--next_segment_id(work), next_entity_id(work), entity_position(x, y), infrastructure(work, kind), finite(v, fallback).
local PipeRuns = {}

--Rewrite work.segments / work.entities / work.segments_by_cell / work.bindings in place. Returns pairs laid.
function PipeRuns.bury(work, h)
    return 0
end

return PipeRuns

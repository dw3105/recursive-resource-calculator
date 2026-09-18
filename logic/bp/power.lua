--Poles that cover everything electric, and the wires that actually join them.
--
--Owned by lane W3-power. It receives an opaque list of rects to cover and returns poles plus the wire edges it
--chose; it never learns what any of those rects is.
--
--  Power.begin{grid_w, grid_h, occupied = {{rect, owner}}, consumers = {{id, rect}}, pole = <catalog pole>,
--              limits = {max_poles}} -> state
--  state.result = {entities = {PlacedEntity},              -- kind "pole", ids prefixed "p:"
--                  wires = {{a_id, a_connector, b_id, b_connector}},
--                  pole_count, components, uncovered = {id}}
--
--A wire edge is a physical claim, so it carries its connectors: power runs on copper (defines.wire_connector_id
--.pole_copper), and a graph joined through a circuit connector is not an electric network. Reach is the smaller
--of the two poles' own get_max_wire_distance at their own quality. Roboports are excluded from coverage by
--design; they are powered separately or not at all.
local Power = {}

function Power.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "power", done_units = 0}}
end

function Power.step(state, budget)
    return state
end

return Power

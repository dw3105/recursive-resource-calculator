--Prototype facts as plain data, read once, so everything downstream can be pure.
--
--Owned by lane W1-catalog. Only this module and logic/bp/plan.lua touch prototypes; every geometry, routing,
--power and serialization module takes a catalog and returns plain data, which is what lets those lanes be
--written and tested with no game at all.
--
--Two geometry models live here, and they are not the same thing:
--  tile_w/tile_h      the north footprint, integer. A conservative bound the packer uses.
--  collision_box      the exact box in tiles relative to the entity centre, with its mask. What the validator
--                     uses. A packer and a validator sharing one model cannot catch each other's mistake.
--
--Quality is never assumed: reach, supply area, crafting speed and module slots are read at the selected quality
--through the prototype's own accessors, never from a normal-quality constant.
--
--  entity[name] = {name, etype, tile_w, tile_h, collision_box = {left_top = {x, y}, right_bottom = {x, y}},
--                  collision_mask, module_slots, energy_usage_w, pollution_per_min, needs_power,
--                  fluid_boxes = {{index, production_type, filter, connections = {
--                      {positions = {4 x {x, y}}, direction, connection_type, flow_direction, max_underground_distance}}}},
--                  beacon = {supply_w, supply_h, distribution_effectivity, profile, counter} | nil}
--  belt = {belt, underground, splitter, quality, items_per_second, lane_items_per_second, underground_max_distance}
--  pipe = {pipe, underground, quality, underground_max_distance, throughput_per_second}
--  inserter = {name, quality, items_per_second, pickup_offset, drop_offset, drop_position}
--  pole = {name, quality, tile_w, tile_h, supply_w, supply_h, wire_reach}
--  robo = {name, quality, tile_w, tile_h, logistic_radius, construction_radius, connection_distance}
--
--An identity that no longer resolves is reported, never guessed and never crashed on.
local Catalog = {}

Catalog.SCHEMA_VERSION = 1

--Builds the projection for one generation request. Returns catalog, diagnostics (a list of {code, subject, detail}).
function Catalog.build(player_index, options)
    return {schema_version = Catalog.SCHEMA_VERSION, entity = {}, item = {}, quality_level = {}}, {}
end

--The subset the debug export carries: only prototypes the calculation actually referenced, never every prototype
function Catalog.for_export(player_index, referenced)
    return {}, {}
end

return Catalog

--The second opinion: everything a finished candidate claims, checked again from the exact prototype geometry.
--
--Owned by lane W3-validate.  This module deliberately does not call any producer.  The candidate is already
--finished; this pass uses the catalog and the candidate's provenance to independently check it.
--
--  state.result = {score = {beacon_count, production_area, cell_envelope_area, transport_cost,
--                           transport_entities, pole_count, coord_key},
--                  metrics = {beacon_effects_by_entity_id, peak_power_w, pollution_per_min, achieved_rate_by_port_id}}
--  state.errors = {{code = "BP_V_...", ids = {string}, detail = table}}
local Validate = {}

local Grid = require "logic.bp.grid"
--The world-box conversion is shared with the planner, so the two can never drift apart again.
local Geometry = require "logic.bp.geometry"
local Flags = require "logic.bp.flags"
local Buffer = require "logic.bp.buffer"
local Belt = require "logic.bp.belt"

local EPSILON = 1e-9
local INF = math.huge
local declared_cache = setmetatable({}, {__mode = "k"})
-- Per-work tile indexes preserve infos order and avoid the measured 1.5-2.1 s scans (legalcopilot-dev, 2026-09-28).
local tile_cache = setmetatable({}, {__mode = "k"})
local build_tile_cache

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= INF and value ~= -INF then return value end
    return fallback
end

local function tolerance(value)
    return math.max(EPSILON, math.abs(finite(value, 0)) * EPSILON)
end

local function near(a, b)
    return math.abs(a - b) <= tolerance(math.max(math.abs(a), math.abs(b)))
end

local function id_of(value, fallback)
    if type(value) ~= "table" then return value or fallback end
    return value.id or value.entity_id or value.member_id or value.block_id or value.step_id or fallback
end

local function name_of(entity)
    if type(entity) ~= "table" then return nil end
    local name = entity.name or entity.entity or entity.prototype
    if type(name) == "table" then return name.name or name.id end
    return name
end

local function kind_of(entity, spec)
    local kind = entity and (entity.kind or entity.type)
    if kind == "assembling-machine" or kind == "furnace" or kind == "rocket-silo" or kind == "lab"
        or kind == "mining-drill" then kind = "machine" end
    if kind == "transport-belt" or kind == "underground-belt" or kind == "splitter" then kind = "belt" end
    if kind == "pipe" or kind == "pipe-to-ground" then kind = "pipe" end
    if kind then return kind end
    if spec and spec.etype == "beacon" then return "beacon" end
    if spec and spec.etype == "electric-pole" then return "pole" end
    if spec and spec.etype == "roboport" then return "roboport" end
    if spec and spec.etype == "inserter" then return "inserter" end
    if spec and (spec.etype == "assembling-machine" or spec.etype == "furnace" or spec.etype == "lab"
        or spec.etype == "rocket-silo" or spec.etype == "mining-drill") then return "machine" end
    return nil
end

local function etype_of(info_or_entity, catalog)
    local info = info_or_entity
    local entity = info and info.entity or info or {}
    local spec = info and info.spec or {}
    return spec.etype or entity.etype or entity.entity_type
end

local function quality_of(value)
    if type(value) == "table" then value = value.name or value.id end
    return type(value) == "string" and value ~= "" and value or "normal"
end

local function prototype_name(value)
    if type(value) == "table" then return value.name or value.prototype or value.id end
    return value
end

local function sorted_keys(map)
    local result = {}
    for key, _ in pairs(map or {}) do result[#result + 1] = key end
    table.sort(result, function(a, b) return tostring(a) < tostring(b) end)
    return result
end

local function copy_table(value)
    local result = {}
    for key, child in pairs(value or {}) do result[key] = child end
    return result
end

local function list_from(source)
    if type(source) ~= "table" then return {} end
    if #source > 0 then return source end
    local result = {}
    for _, key in ipairs(sorted_keys(source)) do
        if type(source[key]) == "table" then
            local child = copy_table(source[key])
            child.id = child.id or key
            result[#result + 1] = child
        end
    end
    return result
end

local function map_by_id(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[id_of(value, tostring(index))] = value end
    return result
end

--Ports are addressed by port_id throughout the pipeline, and id_of never reads that field. A port carrying a
--member, block or step id was therefore indexed under that id, so a binding naming the port's own port_id found
--nothing and every such binding was reported as a wrong port edge. Index by port_id first, keep the generic id
--as an alias so a candidate that only carries id still resolves.
local function port_index(ports)
    local result = {}
    for index, port in ipairs(ports or {}) do
        local primary = port.port_id or id_of(port, tostring(index))
        if primary ~= nil then result[primary] = result[primary] or {}; result[primary][#result[primary] + 1] = port end
    end
    for index, port in ipairs(ports or {}) do
        local alias = id_of(port, tostring(index))
        if alias ~= nil then
            local found = false
            for _, existing in ipairs(result[alias] or {}) do if existing == port then found = true; break end end
            if not found then result[alias] = result[alias] or {}; result[alias][#result[alias] + 1] = port end
        end
    end
    return result
end

local function resolve_port(index, id, binding, half)
    local candidates = index[id] or {}
    local owner = binding[half .. "_step_id"] or binding[half .. "_block_id"]
        or binding.step_id or binding.block_id
    if owner ~= nil then
        for _, port in ipairs(candidates) do
            if (port.step_id or port.block_id) == owner then return port end
        end
    end
    return candidates[1]
end

local function placement_map(source)
    local result = {}
    if type(source) ~= "table" then return result end
    if #source > 0 then
        for _, placement in ipairs(source) do
            local id = placement.block_id or placement.id
            if id ~= nil then result[id] = placement end
        end
    else
        for id, placement in pairs(source) do result[id] = placement end
    end
    return result
end

local function catalog_entity(catalog, entity)
    local name = name_of(entity)
    local quality = entity and entity.quality or "normal"
    local by_name = catalog and catalog.entity
    if type(by_name) ~= "table" or not name then return nil end
    return by_name[name] or by_name[name .. ":" .. tostring(quality)]
        or by_name[name .. "@" .. tostring(quality)]
end

local function module_effect(catalog, module)
    local name = type(module) == "table" and (module.name or module.id) or module
    local item = catalog and catalog.module and catalog.module[name]
    if item and item.effects then return item.effects end
    item = catalog and catalog.item and catalog.item[name]
    return item and item.module_effects or {}
end

local function expand_modules(modules)
    local result = {}
    for _, module in ipairs(modules or {}) do
        local count = math.max(1, math.floor(finite(type(module) == "table" and module.count, 1)))
        for _ = 1, count do
            result[#result + 1] = {
                name = type(module) == "table" and (module.name or module.id) or module,
                quality = type(module) == "table" and (module.quality or "normal") or "normal",
            }
        end
    end
    return result
end

local function module_key(module)
    return tostring(module.name) .. "\0" .. tostring(module.quality or "normal")
end

local function module_lists_equal(a, b)
    a, b = expand_modules(a), expand_modules(b)
    if #a ~= #b then return false end
    for index = 1, #a do if module_key(a[index]) ~= module_key(b[index]) then return false end end
    return true
end

local function collision_mask_set(mask)
    if type(mask) ~= "table" then return nil end
    local result = {}
    for key, value in pairs(mask) do
        if type(key) == "number" then
            if type(value) == "string" or type(value) == "number" then result[tostring(value)] = true end
        elseif value then result[tostring(key)] = true end
    end
    return result
end

local function masks_collide(a, b)
    local left, right = collision_mask_set(a), collision_mask_set(b)
    -- Catalog projections normally contain both masks.  A missing hand-written mask is conservative, so a fixture
    -- that supplies only exact boxes still proves physical overlap.
    if not left or not right then return true end
    for layer, _ in pairs(left) do if right[layer] then return true end end
    return false
end

local function collision_sets_collide(left, right)
    if not left or not right then return true end
    for layer, _ in pairs(left) do if right[layer] then return true end end
    return false
end

--Shared with logic/bp/groups.lua through logic/bp/geometry.lua. Rotation is by corners, so an asymmetric
--collision box survives a quarter turn.
local function corners_box(box, dir)
    return Geometry.local_box(box, dir)
end

local function entity_center(entity, spec)
    return Geometry.center(entity, spec)
end

local function physical_info(entity, catalog, ordinal)
    local spec = catalog_entity(catalog, entity) or {}
    local cx, cy = entity_center(entity, spec)
    local dir = finite(entity.dir or entity.direction, Grid.NORTH)
    local box = corners_box(spec.collision_box or entity.collision_box, dir)
    if not box then
        box = Geometry.tile_box(finite(entity.w, spec.tile_w or 1), finite(entity.h, spec.tile_h or 1))
    end
    return {
        entity = entity, id = id_of(entity, tostring(ordinal)), name = name_of(entity), spec = spec,
        kind = kind_of(entity, spec), quality = entity.quality or spec.quality or "normal",
        cx = cx, cy = cy, box = box, mask = spec.collision_mask or entity.collision_mask,
    }
end

local function box_world(info)
    return {
        left = info.cx + info.box.left, top = info.cy + info.box.top,
        right = info.cx + info.box.right, bottom = info.cy + info.box.bottom,
    }
end

--Collision: strict. Touching edges are legal placements, not collisions.
local function boxes_overlap(a, b)
    return Geometry.boxes_overlap(a, b)
end

--Engine rule: an entity is supplied when its collision box overlaps the supply area, not when its centre sits
--inside it. A 3x3 machine beside a pole overlaps that area while its centre stays outside, so the centre test
--rejected layouts the game powers, and it disagreed with the planner, which already places poles by overlap.
--Supply: tolerant, so an entity exactly on the boundary is supplied. Deliberately a different rule from
--collision above. Beacons use this too now, not the centre test that used to sit beside it.
local function box_in_area(info, centre_x, centre_y, supply_w, supply_h)
    return Geometry.box_overlaps_supply(box_world(info),
        Geometry.supply_box(centre_x, centre_y, supply_w, supply_h))
end

local function rect_of_entity(entity, spec)
    local cx, cy = entity_center(entity, spec)
    local w, h = finite(entity.w, spec and spec.tile_w or 1), finite(entity.h, spec and spec.tile_h or 1)
    return {x = cx - w / 2, y = cy - h / 2, w = w, h = h}
end

local function step_map(plan)
    local result = {}
    for _, step in ipairs(list_from(plan and plan.steps)) do if step.step_id ~= nil then result[step.step_id] = step end end
    return result
end

local function flow_id_of(flow)
    return flow and (flow.flow_id or flow.full_name or flow.id)
end

--A hand or transport entity normally carries one `flow_id`.  The shared-hand route carries the same
--declaration as a set instead (`flow_ids`, `flow_set`, or `flows`) while older candidates keep the scalar
--form.  Keep the validator tolerant of all of those boundary spellings, but never treat an explicitly empty
--set as a wildcard when a flow is being witnessed.
local function declared_flow_ids(value)
    local entity = type(value) == "table" and (value.entity or value) or nil
    local result, seen = {}, {}
    local function add(flow_id)
        if type(flow_id) == "table" then flow_id = flow_id.flow_id or flow_id.full_name or flow_id.id or flow_id.name end
        if type(flow_id) == "string" and flow_id ~= "" and not seen[flow_id] then
            seen[flow_id] = true; result[#result + 1] = flow_id
        end
    end
    local function add_collection(collection)
        if type(collection) ~= "table" then
            add(collection)
            return
        end
        if #collection > 0 then
            for _, item in ipairs(collection) do add(item) end
        else
            for key, item in pairs(collection) do
                local before = #result
                add(item)
                if #result == before then add(key) end
            end
        end
    end
    if entity then
        add_collection(entity.flow_ids or entity.flow_set or entity.flows or entity.flow_shares)
        add(entity.flow_id or entity.full_name)
    end
    table.sort(result)
    return result
end

local function declares_flow(value, wanted_flow)
    if wanted_flow == nil then return false end
    for _, flow_id in ipairs(declared_flow_ids(value)) do
        if flow_id == wanted_flow then return true end
    end
    return false
end

local function flow_compatible(value, wanted_flow)
    if wanted_flow == nil then return true end
    return #declared_flow_ids(value) == 0 or declares_flow(value, wanted_flow)
end

--Unannotated transport is retained as a compatibility fallback for the old hand-written fixtures.  Once a
--belt publishes a flow set, however, membership is exact: a belt carrying another flow is not a path for this
--one.  Inserter declarations use `declares_flow` below and therefore fail closed when they are absent.
local function transport_accepts_flow(info, wanted_flow)
    if wanted_flow == nil then return true end
    local declared = declared_cache[info]
    if not declared then declared = declared_flow_ids(info); declared_cache[info] = declared end
    if #declared == 0 then return true end
    for _, flow_id in ipairs(declared) do if flow_id == wanted_flow then return true end end
    return false
end

local function flow_detail_id(value)
    local ids = declared_flow_ids(value)
    return ids[1] or "undeclared"
end

local function flow_list(source)
    local result = {}
    if type(source) ~= "table" then return result end
    if #source > 0 then return source end
    for _, key in ipairs(sorted_keys(source)) do
        if type(source[key]) == "table" then
            local flow = copy_table(source[key]); flow.flow_id = flow.flow_id or key; result[#result + 1] = flow
        end
    end
    table.sort(result, function(a, b) return tostring(flow_id_of(a)) < tostring(flow_id_of(b)) end)
    return result
end

local function add_unique_entity(result, seen, entity)
    if type(entity) ~= "table" then return end
    local id = id_of(entity, tostring(#result + 1))
    if seen[id] then return end
    seen[id] = true; result[#result + 1] = entity
end

local function collect_entities(root, catalog)
    local result, seen = {}, {}
    local function add_list(source)
        for _, entity in ipairs(list_from(source)) do add_unique_entity(result, seen, entity) end
    end
    add_list(root.entities or root.placed_entities)
    if root.route then add_list(root.route.entities) end
    if root.power then add_list(root.power.entities) end
    add_list(root.roboports); add_list(root.poles)
    local placements = placement_map(root.placements)
    for _, block in ipairs(list_from(root.blocks)) do
        local direct = block.placed_entities or block.entities
        if direct then add_list(direct) end
        if not direct and type(block.members) == "table" then
            local placement = placements[block.block_id or block.id] or block.placement or {x = 0, y = 0, dir = Grid.NORTH}
            for _, member in ipairs(block.members) do
                local placed = copy_table(member)
                local geometry = Grid.place_member(block, placement, member)
                placed.id = placed.id or member.id
                placed.x, placed.y, placed.w, placed.h, placed.dir = geometry.x, geometry.y, geometry.w, geometry.h, geometry.dir
                placed.position = {x = geometry.x + geometry.w / 2, y = geometry.y + geometry.h / 2}
                add_unique_entity(result, seen, placed)
            end
        end
    end
    table.sort(result, function(a, b) return tostring(id_of(a)) < tostring(id_of(b)) end)
    local infos = {}
    for index, entity in ipairs(result) do infos[index] = physical_info(entity, catalog, index) end
    return result, infos
end

local function collect_ports(root)
    local result, seen = {}, {}
    local function add(port, fallback)
        if type(port) ~= "table" then return end
        local id = port.port_id or port.id or fallback
        if id == nil then return end
        local key = table.concat({tostring(id), tostring(port.step_id or port.block_id), tostring(port.member_id)}, "\0")
        if seen[key] then return end
        seen[key] = true; local copy = copy_table(port); copy.port_id = id; result[#result + 1] = copy
    end
    for _, port in ipairs(list_from(root.ports or root.block_ports)) do add(port) end
    for _, port in ipairs(list_from(root.perimeter_ports or root.external_ports)) do add(port) end
    for _, port in ipairs(list_from(root.plan and root.plan.ports)) do add(port) end
    for _, block in ipairs(list_from(root.blocks)) do for _, port in ipairs(list_from(block.ports or block.block_ports)) do add(port) end end
    return result
end

local function collect_bindings(root)
    local source = root.port_bindings or root.bindings or (root.route and (root.route.port_bindings or root.route.bindings))
    return list_from(source)
end

local function collect_segments(root)
    return list_from(root.segments or (root.route and root.route.segments))
end

--pole_copper is 5. The player's own 2.0.77 blueprint writes 5 on both ends of all twelve of its pole-to-pole
--copper wires (measured from its bytes, 2026-09-21). This default and logic/bp/power.lua's fallback have to
--agree: while power.lua emitted 5 and this table still said 0, `connector_role` classified every delivered
--wire as non-copper and 55 BP_V_WIRE_ILLEGAL records appeared on the player's sheet out of nowhere.
local function connector_ids(input)
    local ids = {pole_copper = 5, power_switch_left_copper = 1, power_switch_right_copper = 2, circuit_red = 3, circuit_green = 4}
    local supplied = input and (input.wire_connector_ids or input.connector_ids)
    if type(supplied) == "table" then for key, value in pairs(supplied) do ids[key] = value end end
    return ids
end

local function connector_role(info, connector, ids)
    if type(connector) == "string" then
        local lower = connector:lower()
        if lower:find("circuit", 1, true) or lower:find("red", 1, true) or lower:find("green", 1, true) then return "circuit" end
        if lower:find("copper", 1, true) then return "copper" end
    end
    local entity = info and info.entity or {}
    if type(entity.copper_connectors) == "table" then for _, value in pairs(entity.copper_connectors) do if value == connector then return "copper" end end end
    if entity.copper_connector == connector then return "copper" end
    if connector == ids.circuit_red or connector == ids.circuit_green then return "circuit" end
    if connector == ids.pole_copper or connector == ids.power_switch_left_copper or connector == ids.power_switch_right_copper then return "copper" end
    return nil
end

local function endpoint_id(edge, side)
    return edge[side .. "_id"] or edge[side] or edge[side == "a" and "from_id" or "to_id"]
end

local function connector_of(edge, side)
    return edge[side .. "_connector"] or edge[side .. "_connector_id"]
end

local function spec_for_pole(info, catalog)
    local entity = info.entity
    return info.spec.supply_w and info.spec or entity.supply_w and entity or catalog and catalog.pole or {}
end

local function wire_reach(info, catalog)
    local entity = info.entity
    return finite(entity.wire_reach, finite(info.spec.wire_reach, catalog and catalog.pole and catalog.pole.wire_reach))
end

local function supply_size(info, catalog)
    local spec = spec_for_pole(info, catalog)
    return finite(info.entity.supply_w, finite(spec.supply_w, 0)), finite(info.entity.supply_h, finite(spec.supply_h, 0))
end

local function is_machine(info) return info.kind == "machine" or info.kind == "assembler" or info.kind == "furnace" end
local function is_pole(info) return info.kind == "pole" or info.kind == "electric-pole" or info.kind == "power-pole" end
local function is_power_switch(info) return info.kind == "power-switch" or info.kind == "power_switch" end
local function is_beacon(info) return info.kind == "beacon" end
local function is_robo(info) return info.kind == "roboport" or info.kind == "robo" end
local function is_inserter(info) return info.kind == "inserter" end

--Routing entities are deliberately identified from the candidate itself, not from Route's occupancy tables.  The
--validator is a second opinion at the boundary, so a fixture may carry only a prototype name and a flow id.
--Contract 28.1 and 28.3: one hand may serve two item flows that ride one belt, using both belt lanes, which
--is how the player's own factory gets 22 inserters where ours plans 26.  The switch is OFF here and stays off
--for every lane: three lanes build three halves of one feature behind it -- groups pairs the hands, route shares the belt, validate witnesses per flow -- and integration
--flips all three together, because that is the only point where the halves meet.  Golden tests therefore keep
--passing at default configuration while the halves are being built.
local multi_flow_hands = Flags.multi_flow_hands

--The underscored input is a test-only seam: lane tests exercise this half without changing the default or
--the frozen generator path.  It is TRI-STATE, and that is load-bearing.  `nil` means "use the production
--switch", `true` forces the feature on, `false` forces it OFF.
--Written as `multi_flow_hands or forced`, this could only ever force the switch ON: once the production flag
--was on, a row asking for "switch off" silently read the global instead.  Measured 2026-09-22 on
--legalcopilot-dev with the flag forced on, that cost WI5 in tests/test_physical_witness.lua, which demands
--`off.ok == false` and got `true`, plus HE1 in tests/test_hand_economy.lua through the same defect in
--groups.lua.  A seam that answers only one of its two questions is worse than no seam, because the rows that
--use it keep passing while proving nothing.
local function multi_flow_hands_enabled(work)
    local forced = work and work.input and work.input._force_multi_flow_hands
    if forced ~= nil then return forced == true end
    return multi_flow_hands
end

local function transport_kind(info)
    if not info then return nil end
    if info.kind == "belt" then return "belt" end
    if info.kind == "pipe" then return "pipe" end
    local entity, spec = info.entity or {}, info.spec or {}
    local kind = entity.kind or entity.type or spec.etype
    if kind == "transport-belt" or kind == "underground-belt" or kind == "splitter" then return "belt" end
    if kind == "pipe" or kind == "pipe-to-ground" then return "pipe" end
    local name = tostring(name_of(entity) or ""):lower()
    if name:find("underground-belt", 1, true) or name:find("transport-belt", 1, true) or name:find("splitter", 1, true) then return "belt" end
    if name == "belt" or name == "underground" or name:find("belt", 1, true) then return "belt" end
    if name == "pipe" or name == "pipe-to-ground" or name:find("pipe", 1, true) then return "pipe" end
    return nil
end

local function transport_flow(info)
    return info and info.entity and (info.entity.flow_id or info.entity.full_name)
end

local function entity_direction(info)
    return info and info.entity and (info.entity.direction or info.entity.dir)
end

local function point_key(x, y)
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))
end

local function entity_tile_rect(info)
    local entity = info.entity or {}
    --A player's captured catalog lists machines only (green science sheet, 2026-09-24: no `splitter` spec), so a
    --splitter fell back to one tile and its second output was never walked. A splitter is two tiles wide.
    local fallback_w = tostring(entity.name or ""):find("splitter", 1, true) and 2 or 1
    local width = math.max(1, math.floor(finite(entity.w, finite(info.spec.tile_w, fallback_w))))
    local height = math.max(1, math.floor(finite(entity.h, finite(info.spec.tile_h, 1))))
    --A catalog footprint is the NORTH one, so a body facing east or west is a quarter turn round and its tile
    --extents SWAP.  The splitter spec is `tile_w = 2, tile_h = 1` (logic/catalog.lua:8) and a routed splitter
    --publishes no `w`/`h` of its own, so without this every east or west splitter was registered on the wrong
    --pair of tiles: a real hole in `transport_by_cell` plus a phantom occupancy beside it.
    --Measured 2026-09-22 on legalcopilot-dev, the player's own sheet: `r:343` at `(17.5, 41)` facing WEST
    --covers `(17,40)` and `(17,41)`; unrotated it registered `(16,40)` and `(17,40)`, so the walk arriving at
    --`(17,41)` found nothing and the whole branch behind it read as discontinuous.
    --A member that publishes its own `w`/`h` is already in world terms, so it is never turned here.
    --`corners_box` has always rotated, which is why collision never saw this and the transport grid did.
    if entity.w == nil and entity.h == nil then
        local direction = entity.direction or entity.dir
        if direction == Grid.EAST or direction == Grid.WEST then width, height = height, width end
    end
    local x = finite(entity.x, info.cx - width / 2)
    local y = finite(entity.y, info.cy - height / 2)
    return math.floor(x + EPSILON), math.floor(y + EPSILON), width, height
end

local function transport_tile(info)
    local x, y = entity_tile_rect(info)
    return x, y
end

local function flow_is_fluid(flow_id, entry, work)
    if type(entry) == "table" and (entry.is_fluid == true or entry.kind == "fluid") then return true end
    local wanted = flow_id or (type(entry) == "table" and (entry.flow_id or entry.full_name))
    if type(wanted) == "string" and wanted:sub(1, 6) == "fluid/" then return true end
    for _, flow in ipairs(work and work.flows or {}) do
        if flow_id_of(flow) == wanted and (flow.is_fluid == true or flow.kind == "fluid") then return true end
    end
    return false
end

local function transport_cells(work)
    local by_key = {}
    for _, info in ipairs(work.infos or {}) do
        if transport_kind(info) then
            local x, y, width, height = entity_tile_rect(info)
            for dy = 0, height - 1 do
                for dx = 0, width - 1 do
                    local key = point_key(x + dx, y + dy)
                    by_key[key] = by_key[key] or {}
                    by_key[key][#by_key[key] + 1] = info
                end
            end
        end
    end
    return by_key
end

local function transport_at(work, x, y, wanted_flow, wanted_kind)
    local entries = work.transport_by_cell and work.transport_by_cell[point_key(x, y)] or {}
    for _, info in ipairs(entries) do
        local kind = transport_kind(info)
        if (not wanted_kind or kind == wanted_kind) and transport_accepts_flow(info, wanted_flow) then
            return info
        end
    end
    return nil
end

local function transport_neighbors(work, info, wanted_flow)
    local result, seen = {}, {}
    local kind = transport_kind(info)
    local function add_at(x, y)
        for _, next_info in ipairs(work.transport_by_cell and work.transport_by_cell[point_key(x, y)] or {}) do
            local next_entity = next_info.entity or {}
            local next_kind = transport_kind(next_info)
            local next_name = tostring(name_of(next_entity) or ""):lower()
            local is_splitter = next_entity.type == "splitter" or next_entity.kind == "splitter"
                or next_name:find("splitter", 1, true) ~= nil
            local current_direction = entity_direction(info)
            local next_direction = entity_direction(next_info)
            local opposed = current_direction ~= nil and next_direction ~= nil
                and next_direction == Grid.dir_opposite(current_direction)
            if next_info ~= info and transport_accepts_flow(next_info, wanted_flow)
                and (kind == "pipe" or (not is_splitter or current_direction == next_direction))
                and (kind == "pipe" or next_kind ~= "belt" or not opposed)
                and not seen[next_info.id] then
                seen[next_info.id] = true
                result[#result + 1] = next_info
            end
        end
    end
    local entity = info.entity or {}
    local pair_id = entity.ug_pair_id or entity.underground_pair_id
    local pair = pair_id and work.info_by_id[pair_id]
    if pair and transport_accepts_flow(pair, wanted_flow) then
        seen[pair.id] = true
        result[#result + 1] = pair
    end
    if kind == "pipe" then
        local x, y = transport_tile(info)
        local function is_pipe_to_ground(candidate)
            local candidate_entity = candidate.entity or {}
            local candidate_name = tostring(name_of(candidate_entity) or ""):lower()
            return candidate_name:find("pipe-to-ground", 1, true) ~= nil or candidate_entity.type == "pipe-to-ground"
        end
        local function opens_toward(candidate, tx, ty)
            if not is_pipe_to_ground(candidate) then return true end
            local cx, cy = transport_tile(candidate)
            local dx, dy = Grid.dir_vector(entity_direction(candidate) or Grid.NORTH)
            return cx + dx == tx and cy + dy == ty
        end
        for _, delta in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, ny = x + delta[1], y + delta[2]
            if opens_toward(info, nx, ny) then
                local before = #result
                add_at(nx, ny)
                for k = #result, before + 1, -1 do
                    if not opens_toward(result[k], x, y) then
                        seen[result[k].id] = nil
                        table.remove(result, k)
                    end
                end
            end
        end
    else
        local direction = entity_direction(info)
        local dx, dy = Grid.dir_vector(direction or Grid.NORTH)
        if dx ~= nil then
            --A body wider than one tile has an output in front of EVERY tile it covers.  A splitter is the only
            --one today: two tiles, two outputs.  Leaving only by the anchor's output silently deleted one whole
            --branch of every fork, so a walk that took the other branch died at its far end and the entire run
            --behind it was then reported as waste.
            --logic/bp/route.lua:1214-1227 learned this on 2026-09-22 and the validator was never mirrored.
            --Measured the same day on the player's sheet: 20 BP_V_ROUTE_DISCONTINUOUS and 257 cascading
            --BP_V_TRANSPORT_UNUSED on the first candidate, every break at the far end of a splitter spur.
            --The old code added `rotate_dir(direction, EAST)` from the anchor, which is the splitter's OWN
            --second tile, registered under the SAME `info`, and `add_at` rejects that by `next_info ~= info`.
            --It was a dead branch that could never fire.
            local x, y, w, h = entity_tile_rect(info)
            for ox = 0, w - 1 do
                for oy = 0, h - 1 do
                    add_at(x + ox + dx, y + oy + dy)
                end
            end
        end
    end
    return result
end

local function transport_path(work, start_x, start_y, target_x, target_y, wanted_flow, wanted_kind)
    if start_x == nil or start_y == nil or target_x == nil or target_y == nil then return nil end
    if math.floor(start_x) == math.floor(target_x) and math.floor(start_y) == math.floor(target_y) then
        local same = transport_at(work, target_x, target_y, wanted_flow, wanted_kind)
        return same and {same} or nil
    end
    local start = transport_at(work, start_x, start_y, wanted_flow, wanted_kind)
    local target = transport_at(work, target_x, target_y, wanted_flow, wanted_kind)
    if not start or not target then return nil end
    local queue, head, visited = {start}, 1, {[start.id] = true}
    local previous = {}
    while queue[head] do
        local current = queue[head]; head = head + 1
        if current == target then
            local path = {}
            while current do
                path[#path + 1] = current
                current = previous[current.id]
            end
            for first = 1, math.floor(#path / 2) do
                local last = #path - first + 1
                path[first], path[last] = path[last], path[first]
            end
            return path
        end
        for _, next_info in ipairs(transport_neighbors(work, current, wanted_flow)) do
            if not visited[next_info.id] then
                visited[next_info.id] = true
                previous[next_info.id] = current
                queue[#queue + 1] = next_info
            end
        end
    end
    return nil
end

local function transport_reachable(work, start_x, start_y, target_x, target_y, wanted_flow, wanted_kind)
    return transport_path(work, start_x, start_y, target_x, target_y, wanted_flow, wanted_kind) ~= nil
end

local function transport_failure_step(work, start_x, start_y, target_x, target_y, wanted_flow, wanted_kind)
    local start = transport_at(work, start_x, start_y, wanted_flow, wanted_kind)
    local target = transport_at(work, target_x, target_y, wanted_flow, wanted_kind)
    if not start then return "cell:" .. tostring(math.floor(start_x or 0)) .. ":" .. tostring(math.floor(start_y or 0)) end
    if start == target then return tostring(start.id) end
    local queue, head, visited = {start}, 1, {[start.id] = true}
    local last = start
    while queue[head] do
        local current = queue[head]; head = head + 1
        last = current
        local next_items = transport_neighbors(work, current, wanted_flow)
        if #next_items == 0 then return tostring(current.id) end
        for _, next_info in ipairs(next_items) do
            if not visited[next_info.id] then
                visited[next_info.id] = true
                queue[#queue + 1] = next_info
            end
        end
    end
    return tostring(last.id)
end

local function tile_of(info)
    return math.floor(info.cx + EPSILON), math.floor(info.cy + EPSILON)
end

local function tile_key(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function endpoint_type(info)
    local entity = info and info.entity or {}
    local role = entity.ug_role
    local kind = entity.type
    if role ~= nil and role ~= "input" and role ~= "output" then return nil end
    if kind ~= nil and kind ~= "input" and kind ~= "output" then kind = nil end
    if role ~= nil and kind ~= nil and role ~= kind then return nil end
    return role or kind
end

local function is_external_port(port)
    return port.perimeter == true or (port.member_id == nil and port.block_id == nil and port.step_id == nil)
end

local function needs_power(info)
    if info.entity.needs_power ~= nil then return info.entity.needs_power end
    if info.spec.needs_power ~= nil then return info.spec.needs_power end
    return is_machine(info) or is_beacon(info) or is_robo(info) or is_inserter(info)
end

local function beacon_projection(info, catalog)
    local beacon = info.spec.beacon or (catalog and catalog.beacon and catalog.beacon[info.name]) or {}
    local entity = info.entity
    return {supply_w = finite(entity.supply_w, finite(beacon.supply_w, 0)),
        supply_h = finite(entity.supply_h, finite(beacon.supply_h, finite(beacon.supply_w, 0))),
        effectivity = finite(entity.distribution_effectivity, finite(beacon.distribution_effectivity, 1)),
        profile = entity.profile or beacon.profile, counter = entity.counter or beacon.counter}
end

local function beacon_modules(info) return expand_modules(info.entity.modules or info.entity.module_loadout or {}) end

local function has_speed_module(info, catalog)
    if info.entity.has_speed_module then return true end
    for _, module in ipairs(beacon_modules(info)) do if finite(module_effect(catalog, module).speed, 0) > 0 then return true end end
    return false
end

local function beacon_group_matches(beacon, group)
    if group.signature and beacon.entity.signature and group.signature == beacon.entity.signature then return true end
    if group.name and group.name ~= beacon.name then return false end
    if group.quality and group.quality ~= beacon.quality then return false end
    if group.modules and #group.modules > 0 and not module_lists_equal(group.modules, beacon.entity.modules or {}) then return false end
    return true
end

local function error_record(errors, code, ids, detail)
    local record = {code = code}; if ids and #ids > 0 then record.ids = ids end; if detail then record.detail = detail end
    errors[#errors + 1] = record
end

local function block_port_geometry(errors, root, placements)
    for _, block in ipairs(list_from(root.blocks)) do
        local width, height = finite(block.w), finite(block.h)
        if width and height then
            for _, port in ipairs(list_from(block.ports or block.block_ports)) do
                --attach_dx/attach_dy are in the block's own frame; a rotated placement's envelope is not.
                local width, height = finite(port._block_w, width), finite(port._block_h, height)
                local dx, dy = finite(port.attach_dx), finite(port.attach_dy)
                local bounded = dx and dy and (((dx == -1 or dx == width) and dy >= 0 and dy < height)
                    or ((dy == -1 or dy == height) and dx >= 0 and dx < width))
                local id = port.port_id or port.id
                --A row's second head feed side-loads from inside the envelope, beside the head (docs/contracts/
                --row_block.md); its tile is free ground, so the boundary rule does not apply to it.
                local interior_row_feed = port.row_port and port.role == "in" and not bounded
                --A hand hop (round 31) moves a single machine's hand to another face: its port is the belt tile next
                --to that hand, anywhere around the machine, not on the grouping's boundary ring.
                if port.hopped then bounded, interior_row_feed = true, true end
                if port.interior_free then bounded, interior_row_feed = true, true end
                --A fluid port is the pipe tile in front of its machine's fluid box, often in the gap row between
                --a beacon row and the machine. The fluid-connection check proves that tile; the ring does not apply.
                if port.fluid_pinned or port.kind == "fluid" or port.is_fluid == true then bounded, interior_row_feed = true, true end
                if not bounded and not interior_row_feed then error_record(errors, "BP_V_PORT_EDGE_WRONG", {tostring(id)}, {reason = "attachment is not on the block boundary"}) end
                local nx, ny = Grid.dir_vector(port.normal_dir or Grid.NORTH)
                local inward = interior_row_feed or (bounded and ((dx == -1 and nx == 1) or (dx == width and nx == -1) or (dy == -1 and ny == 1) or (dy == height and ny == -1)))
                if not inward then error_record(errors, "BP_V_PORT_EDGE_WRONG", {tostring(id)}, {reason = "normal does not point into the block"}) end
                local placement = placements[block.block_id or block.id]
                if placement and port.x ~= nil and port.y ~= nil then
                    local expected = Grid.place_port(block, placement, port)
                    if not near(finite(port.x, expected.x), expected.x) or not near(finite(port.y, expected.y), expected.y)
                        or (port.normal_dir and port.normal_dir ~= expected.dir) then
                        error_record(errors, "BP_V_PORT_EDGE_WRONG", {tostring(id)}, {reason = "placed port differs from block geometry"})
                    end
                end
            end
        end
    end
end

local coordinate_key, make_score

local function make_work(input)
    input = type(input) == "table" and input or {}
    local root = input.candidate or input.result or input
    local plan = input.plan or root.plan
    local catalog = input.catalog or root.catalog or {}
    local entities, infos = collect_entities(root, catalog)
    local info_by_id = {}; for _, info in ipairs(infos) do info_by_id[info.id] = info end
    local grid = root.grid or input.grid or {}
    local grid_w = finite(root.grid_w, finite(input.grid_w, finite(grid.w, finite(root.width, input.width))))
    local grid_h = finite(root.grid_h, finite(input.grid_h, finite(grid.h, finite(root.height, input.height))))
    local wires = list_from(root.wires or (root.power and root.power.wires))
    local flows = flow_list(root.flows or (root.route and root.route.flows) or (plan and plan.flows))
    local blocks = list_from(root.blocks); local ports = collect_ports(root); local port_by_id = port_index(ports)
    --Port roles are classified from the port itself; perimeter and block ids are disjoint.
    --The perimeter marker is authoritative now that port ids are disjoint.
    local segments = collect_segments(root); local segment_by_id = map_by_id(segments)
    local bindings = collect_bindings(root); local steps = step_map(plan); local placements = placement_map(root.placements)
    local machines, beacons, poles, power_nodes, roboports, inserters, consumers = {}, {}, {}, {}, {}, {}, {}
    for _, info in ipairs(infos) do
        if is_machine(info) then machines[#machines + 1] = info end
        if is_beacon(info) then beacons[#beacons + 1] = info end
        if is_pole(info) then poles[#poles + 1] = info; power_nodes[#power_nodes + 1] = info end
        if is_power_switch(info) then power_nodes[#power_nodes + 1] = info end
        if is_robo(info) then roboports[#roboports + 1] = info end
        if is_inserter(info) then inserters[#inserters + 1] = info end
        if needs_power(info) and not is_pole(info) and not is_power_switch(info) and not is_robo(info) then consumers[#consumers + 1] = info end
    end
    local work = {input = input, root = root, plan = plan, catalog = catalog, blocks = blocks, entities = entities, infos = infos, info_by_id = info_by_id,
        grid_w = grid_w, grid_h = grid_h, wires = wires, flows = flows, ports = ports, port_by_id = port_by_id,
        segments = segments, segment_by_id = segment_by_id, bindings = bindings, steps = steps, placements = placements,
        machines = machines, beacons = beacons, poles = poles, power_nodes = power_nodes, roboports = roboports, inserters = inserters,
        consumers = consumers, ids = connector_ids(input), errors = {}, legal_wires = {}, power_parent = {},
        metrics = {beacon_effects_by_entity_id = {}, beacon_effects_by_instance = {}, available_capacity_by_entity_id = {},
            power_by_entity_id = {}, transport_demand_by_entity_id = {}, achieved_rate_by_port_id = {},
            connection_witnesses = {}, transfer_witnesses = {},
            peak_power_w = 0, pollution_per_min = 0},
    }
    work.geometry_world, work.geometry_masks = {}, {}
    for index, info in ipairs(infos) do
        work.geometry_world[index] = box_world(info)
        work.geometry_masks[index] = collision_mask_set(info.mask)
    end
    work.coordinate_key = coordinate_key(work)
    work.transport_by_cell = transport_cells(work)
    work.initial_score = make_score(work)
    return work
end

local function disjoint_union(work, a, b)
    local parent = work.power_parent
    local function find(value)
        parent[value] = parent[value] or value
        if parent[value] ~= value then parent[value] = find(parent[value]) end
        return parent[value]
    end
    local ra, rb = find(a), find(b); if ra ~= rb then parent[rb] = ra end
end

local function power_components(work)
    local roots = {}
    local function find(value)
        local parent = work.power_parent; parent[value] = parent[value] or value
        if parent[value] ~= value then parent[value] = find(parent[value]) end
        return parent[value]
    end
    for _, info in ipairs(work.power_nodes) do roots[find(info.id)] = true end
    local count = 0; for _, _ in pairs(roots) do count = count + 1 end
    return count
end

local function flow_share(entry)
    return math.max(0, finite(type(entry) == "table" and (entry.share_per_second or entry.rate_per_second or entry.rate) or entry, 0))
end

local function step_id_of(value) return type(value) == "table" and (value.step_id or value.id or value.block_id) or value end

local function sink_key(entry, flow, ports, role)
    local step = step_id_of(entry)
    if step == "$external" then
        local wanted = type(entry) == "table" and (entry.port_id or entry.port) or nil
        if wanted then return "port:" .. tostring(wanted) end
        for _, port in ipairs(ports) do
            if declares_flow(port, flow_id_of(flow)) and (port.role == role or port.direction == role) then return "port:" .. tostring(port.port_id) end
        end
        return nil
    end
    return step and "step:" .. tostring(step) or nil
end

local function segment_capacity(work, segment, kind, flow)
    if segment.capacity_per_second ~= nil then return finite(segment.capacity_per_second, 0) end
    if kind == "pipe" then return finite(work.catalog.pipe and work.catalog.pipe.throughput_per_second, INF) end
    if kind == "inserter" then return finite(work.catalog.inserter and work.catalog.inserter.items_per_second, INF) end
    local capacity = Belt.capacity(work.catalog, flow, kind == "lane" and "lane" or "belt")
    return finite(capacity, INF)
end

local function module_effect_total(catalog, modules)
    local total = {speed = 0, consumption = 0, pollution = 0, quality = 0}
    for _, module in ipairs(expand_modules(modules)) do
        local effect = module_effect(catalog, module)
        for _, key in ipairs({"speed", "consumption", "pollution", "quality"}) do total[key] = total[key] + finite(effect[key], 0) end
    end
    return total
end

local function configured_groups(info, work)
    local step = work.steps[info.entity.step_id]
    return (step and step.beacon_groups) or info.entity.beacon_groups or {}
end

local function check_geometry(work, index)
    local info = work.infos[index]; if not info then return true end
    local world = box_world(info)
    if work.grid_w and (world.left < -EPSILON or world.right > work.grid_w + EPSILON or world.top < -EPSILON or world.bottom > work.grid_h + EPSILON) then
        error_record(work.errors, "BP_V_OUT_OF_GRID", {tostring(info.id)}, {box = world, grid_w = work.grid_w, grid_h = work.grid_h})
    end
    for other_index = index + 1, #work.infos do
        local other = work.infos[other_index]
        if masks_collide(info.mask, other.mask) and boxes_overlap(world, box_world(other)) then
            error_record(work.errors, "BP_V_COLLISION", {tostring(info.id), tostring(other.id)}, {box_a = world, box_b = box_world(other)})
        end
    end
    return index >= #work.infos
end

-- One geometry op is one entity-pair comparison.  Keeping the two indices in the
-- validation cursor prevents a large blueprint from doing its quadratic collision
-- scan in a single game tick.
local function check_geometry_pair(work, index, other_index)
    local info, other = work.infos[index], work.infos[other_index]
    if not info or not other then return end
    local world = work.geometry_world[index] or box_world(info)
    local other_world = work.geometry_world[other_index] or box_world(other)
    if collision_sets_collide(work.geometry_masks[index], work.geometry_masks[other_index])
        and boxes_overlap(world, other_world) then
        error_record(work.errors, "BP_V_COLLISION", {tostring(info.id), tostring(other.id)}, {box_a = world, box_b = other_world})
    end
end

--The buffer rule is independent of collision geometry: it is checked once, after the
--incremental geometry pass, using the shared rule module and a stable entity order.
local function check_buffer_zones(work)
    local machines = {}
    for _, info in ipairs(work.machines) do machines[#machines + 1] = info end
    table.sort(machines, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local records = {}
    for _, machine in ipairs(machines) do
        local entity = machine.entity or {}
        local step = work.steps[entity.step_id]
        local recipe = (step and step.recipe) or entity.recipe
        local x, y, w, h = entity_tile_rect(machine)
        local bump = math.max(0, math.min(2, math.floor(finite(work.input.ring_bump, 0))))
        records[#records + 1] = {id = tostring(machine.id), rect = {x = x, y = y, w = w, h = h},
            ring = Buffer.ring(work.catalog, recipe) + bump, key = Buffer.key(machine.name, recipe)}
    end
    for i = 1, #records do
        for j = i + 1, #records do
            local a, b = records[i], records[j]
            if Buffer.conflict(a, b) then
                error_record(work.errors, "BP_V_BUFFER_ZONE", {a.id, b.id}, {rect_a = a.rect, rect_b = b.rect})
            end
        end
    end
    for _, record in ipairs(records) do
        local zone = Buffer.zone(record.rect, record.ring)
        for _, roboport in ipairs(work.roboports or {}) do
            local x, y, w, h = entity_tile_rect(roboport)
            local rect = {x = x, y = y, w = w, h = h}
            if zone.x < rect.x + rect.w and rect.x < zone.x + zone.w
                and zone.y < rect.y + rect.h and rect.y < zone.y + zone.h then
                error_record(work.errors, "BP_V_BUFFER_ROBOPORT", {record.id, tostring(roboport.id)},
                    {machine_id = record.id, roboport_id = tostring(roboport.id), zone = zone, rect = rect})
            end
        end
    end
    return true
end

--A plain-data connection_distance is a compatibility override for fixtures and callers. The engine fact for a
--roboport is logistic_radius, so the normal path derives the shared reach from that radius just as the planner does.
local function robo_reach(info, catalog)
    local entity, spec = info.entity, info.spec
    local robo = catalog and (catalog.robo or catalog.roboport) or {}
    local explicit = finite(entity.connection_distance,
        finite(spec.connection_distance, finite(robo.connection_distance, nil)))
    if explicit ~= nil then return explicit end
    local logistic_radius = finite(entity.logistic_radius,
        finite(spec.logistic_radius, finite(robo.logistic_radius, nil)))
    return logistic_radius and logistic_radius * 2 or nil
end

local function check_robo(work)
    if #work.roboports <= 1 then return true end
    local parent = {}
    local function find(value)
        parent[value] = parent[value] or value; if parent[value] ~= value then parent[value] = find(parent[value]) end; return parent[value]
    end
    local function join(a, b) a, b = find(a), find(b); if a ~= b then parent[b] = a end end
    for _, a in ipairs(work.roboports) do parent[a.id] = a.id end
    for first = 1, #work.roboports do
        for second = first + 1, #work.roboports do
            local a, b = work.roboports[first], work.roboports[second]
            local reach_a, reach_b = robo_reach(a, work.catalog), robo_reach(b, work.catalog)
            if reach_a ~= nil and reach_b ~= nil then
                local reach_limit = math.min(reach_a, reach_b)
                local dx, dy = a.cx - b.cx, a.cy - b.cy
                if math.sqrt(dx * dx + dy * dy) <= reach_limit + tolerance(reach_limit) then join(a.id, b.id) end
            end
        end
    end
    local root = find(work.roboports[1].id); local disconnected = {}
    for _, robo in ipairs(work.roboports) do if find(robo.id) ~= root then disconnected[#disconnected + 1] = tostring(robo.id) end end
    if #disconnected > 0 then error_record(work.errors, "BP_V_ROBO_DISCONNECTED", disconnected) end
    return true
end

local function check_beacons(work)
    local influence_by_machine, groups_by_machine = {}, {}
    for _, machine in ipairs(work.machines) do
        local influencing, effects = {}, {speed = 0, consumption = 0, pollution = 0, quality = 0}
        for _, beacon in ipairs(work.beacons) do
            local projection = beacon_projection(beacon, work.catalog)
            --Engine: a beacon's supply_area_distance counts from its EDGE (vanilla 3x3, distance 3 -> 9x9); a pole's
            --counts from its centre. Add the half footprint here only.
            local half_w, half_h = finite(beacon.w, 3) / 2, finite(beacon.h, finite(beacon.w, 3)) / 2
            if box_in_area(machine, beacon.cx, beacon.cy, projection.supply_w + half_w, projection.supply_h + half_h) then
                influencing[#influencing + 1] = beacon
                if machine.entity.forbids_speed_beacon or machine.entity.has_quality_module
                    or (work.steps[machine.entity.step_id] and (work.steps[machine.entity.step_id].forbids_speed_beacon
                        or work.steps[machine.entity.step_id].has_quality_module)) then
                    if has_speed_module(beacon, work.catalog) then error_record(work.errors, "BP_V_SPEED_BEACON_ON_QUALITY", {tostring(beacon.id), tostring(machine.id)}) end
                end
            end
        end
        influence_by_machine[machine.id] = influencing
        groups_by_machine[machine.id] = configured_groups(machine, work)
        for _, group in ipairs(configured_groups(machine, work)) do
            local required = finite(group.count_per_machine, finite(group.count, 0))
            if required > 0 then
                local got = 0; for _, beacon in ipairs(influencing) do if beacon_group_matches(beacon, group) then got = got + 1 end end
                if got + tolerance(got) < required then error_record(work.errors, "BP_V_BEACON_COVERAGE_SHORT", {tostring(machine.id)}, {group = group.signature or group.name, required = required, got = got}) end
            end
        end
        local total = #influencing
        for _, beacon in ipairs(influencing) do
            local projection = beacon_projection(beacon, work.catalog); local count = total
            if projection.counter == "same_type" then count = 0; for _, peer in ipairs(influencing) do if peer.name == beacon.name then count = count + 1 end end end
            local sample = 1
            if type(projection.profile) == "table" and #projection.profile > 0 then sample = finite(projection.profile[math.max(1, math.min(#projection.profile, count))], 1) end
            local weight = projection.effectivity * sample; local module_effects = module_effect_total(work.catalog, beacon.entity.modules)
            for _, key in ipairs({"speed", "consumption", "pollution", "quality"}) do effects[key] = effects[key] + weight * module_effects[key] end
        end
        --A step can have several physical machines.  The effect belongs to the machine box that was actually
        --covered, not to the step label (which would let the last machine overwrite the earlier ones).
        work.metrics.beacon_effects_by_entity_id[machine.id] = effects
        work.metrics.beacon_effects_by_instance[machine.id] = effects
    end
    --A beacon which is not part of any configured group is pure waste: removing it cannot lower a configured
    --minimum on any machine.  Matching-group beacons remain legal when influence is above the configured count;
    --the configured group is the independent obligation that makes that influence intentional.
    for _, beacon in ipairs(work.beacons) do
        local load_bearing = false
        local exact_remove_test = beacon.entity.required_for ~= nil or beacon.entity.covered_members ~= nil
        if exact_remove_test then
            for _, machine in ipairs(work.machines) do
                local influencing = influence_by_machine[machine.id] or {}
                local groups = groups_by_machine[machine.id] or {}
                for _, group in ipairs(groups) do
                    local required = finite(group.count_per_machine, finite(group.count, 0))
                    if required > 0 then
                        local got, removes = 0, false
                        for _, candidate in ipairs(influencing) do
                            if beacon_group_matches(candidate, group) then
                                got = got + 1
                                if candidate.id == beacon.id then removes = true end
                            end
                        end
                        if removes and got - 1 + tolerance(got) < required then load_bearing = true; break end
                    end
                end
                if load_bearing then break end
            end
        else
        for _, machine in ipairs(work.machines) do
            local influencing = influence_by_machine[machine.id] or {}
            local groups = groups_by_machine[machine.id] or {}
            for _, candidate in ipairs(influencing) do
                if candidate.id == beacon.id then
                    for _, group in ipairs(groups) do
                        if finite(group.count_per_machine, finite(group.count, 0)) > 0 and beacon_group_matches(beacon, group) then
                            load_bearing = true
                            break
                        end
                    end
                end
                if load_bearing then break end
            end
            if load_bearing then break end
        end
        end
        if not load_bearing then
            error_record(work.errors, "BP_V_BEACON_REDUNDANT", {tostring(beacon.id)},
                {reason = "removing beacon leaves every configured beacon count satisfied"})
        end
    end
    return true
end

local function check_power_coverage(work)
    for _, consumer in ipairs(work.consumers) do
        local covered = false
        for _, pole in ipairs(work.poles) do
            local supply_w, supply_h = supply_size(pole, work.catalog)
            if box_in_area(consumer, pole.cx, pole.cy, supply_w, supply_h) then covered = true; break end
        end
        if not covered then error_record(work.errors, "BP_V_POWER_UNCOVERED", {tostring(consumer.id)}) end
        local effects = work.metrics.beacon_effects_by_entity_id[consumer.id] or {}
        local base_power = finite(consumer.entity.power_w, finite(consumer.spec.energy_usage_w, 0))
        local power_multiplier = math.max(0, 1 + finite(effects.consumption, 0))
        local power = base_power * power_multiplier
        work.metrics.power_by_entity_id[consumer.id] = power
        work.metrics.peak_power_w = work.metrics.peak_power_w + power
        work.metrics.pollution_per_min = work.metrics.pollution_per_min
            + finite(consumer.spec.pollution_per_min, 0) * math.max(0, 1 + finite(effects.pollution, 0))
        if is_machine(consumer) then
            local speed = math.max(0, 1 + finite(effects.speed, 0))
            local base_capacity = finite(consumer.entity.capacity_per_second,
                finite(consumer.spec.crafting_speed, finite(consumer.spec.speed, 0)))
            work.metrics.available_capacity_by_entity_id[consumer.id] = base_capacity * speed
        end
    end
    for _, beacon in ipairs(work.beacons) do work.metrics.peak_power_w = work.metrics.peak_power_w + finite(beacon.entity.power_w, finite(beacon.spec.energy_usage_w, 0)) end
    return true
end

local function check_wire_legality(work)
    for _, edge in ipairs(work.wires) do
        local a_id, b_id = endpoint_id(edge, "a"), endpoint_id(edge, "b"); local a, b = work.info_by_id[a_id], work.info_by_id[b_id]; local reason
        if not a or not b then reason = "endpoint missing" end
        local a_connector, b_connector = connector_of(edge, "a"), connector_of(edge, "b")
        if not reason and (connector_role(a, a_connector, work.ids) ~= "copper" or connector_role(b, b_connector, work.ids) ~= "copper") then reason = "non-copper connector" end
        if not reason and ((not is_pole(a) and not is_power_switch(a)) or (not is_pole(b) and not is_power_switch(b))) then reason = "endpoint is not power infrastructure" end
        local reach = reason and nil or math.min(wire_reach(a, work.catalog) or 0, wire_reach(b, work.catalog) or 0)
        if not reason then
            local dx, dy = a.cx - b.cx, a.cy - b.cy; local distance = math.sqrt(dx * dx + dy * dy)
            if distance > reach + tolerance(reach) then reason = "over range" end
        end
        if reason then error_record(work.errors, "BP_V_WIRE_ILLEGAL", {tostring(a_id), tostring(b_id)}, {reason = reason})
        else work.legal_wires[#work.legal_wires + 1] = {a = a, b = b}; disjoint_union(work, a.id, b.id) end
    end
    return true
end

local function check_wire_connectivity(work)
    if #work.power_nodes <= 1 then return true end
    local components = power_components(work)
    if components > 1 then
        local ids = {}; for _, node in ipairs(work.power_nodes) do ids[#ids + 1] = tostring(node.id) end
        error_record(work.errors, "BP_V_WIRE_DISCONNECTED", ids, {components = components})
    end
    return true
end

local function check_segments(work)
    local allocation_by_flow_sink, segments_by_flow = {}, {}
    local flow_map = {}; for _, flow in ipairs(work.flows or {}) do flow_map[flow_id_of(flow)] = flow end
    for _, segment in ipairs(work.segments) do
        local kind = segment.kind or "belt"; local total = 0; local flows_on_segment = {}
        if segment.flow_id ~= nil then flows_on_segment[segment.flow_id] = true end
        for _, allocation in ipairs(segment.allocations or {}) do
            local amount = flow_share(allocation); total = total + amount; local flow_id = allocation.flow_id or segment.flow_id
            if flow_id ~= nil then
                flows_on_segment[flow_id] = true; allocation_by_flow_sink[flow_id] = allocation_by_flow_sink[flow_id] or {}
                if allocation.sink ~= nil then allocation_by_flow_sink[flow_id][allocation.sink] = (allocation_by_flow_sink[flow_id][allocation.sink] or 0) + amount end
            end
        end
        local stacked_flow
        for flow_id in pairs(flows_on_segment) do if Belt.is_external_item(flow_map[flow_id]) then stacked_flow=flow_map[flow_id]; break end end
        local capacity = segment_capacity(work, segment, kind, stacked_flow)
        local code = kind == "inserter" and "BP_V_INSERTER_CAPACITY" or "BP_V_TRANSFER_CAPACITY"
        if total > capacity + tolerance(capacity) then error_record(work.errors, code, {tostring(segment.segment_id)}, {capacity = capacity, allocated = total}) end
        local flow_count = 0; for _, _ in pairs(flows_on_segment) do flow_count = flow_count + 1 end
        if kind == "pipe" and flow_count > 1 then
            error_record(work.errors, "BP_V_FLUID_MIXING", {tostring(segment.segment_id)})
        end
        for flow_id, _ in pairs(flows_on_segment) do segments_by_flow[flow_id] = (segments_by_flow[flow_id] or 0) + 1 end
    end
    for _, flow in ipairs(work.flows) do
        local flow_id = flow_id_of(flow)
        if flow_id then
            local produced, consumed = finite(flow.supplied, 0), finite(flow.removed, 0)
            for _, entry in ipairs(flow.producers or {}) do produced = produced + flow_share(entry) end
            for _, entry in ipairs(flow.consumers or {}) do consumed = consumed + flow_share(entry) end
            if not near(produced, consumed) then error_record(work.errors, "BP_V_FLOW_IMBALANCE", {tostring(flow_id)}, {produced = produced, consumed = consumed}) end
            if math.max(produced, consumed) > tolerance(math.max(produced, consumed)) and not segments_by_flow[flow_id] then error_record(work.errors, "BP_V_ROUTE_MISSING", {tostring(flow_id)}) end
            local sinks = allocation_by_flow_sink[flow_id] or {}
            for _, entry in ipairs(flow.consumers or {}) do
                local required = flow_share(entry)
                if required > tolerance(required) then
                    local sink = sink_key(entry, flow, work.ports, "out"); local reached = sink and finite(sinks[sink], 0) or 0
                    if reached + tolerance(required) < required then
                        error_record(work.errors, "BP_V_TARGET_SHORTFALL", {tostring(flow_id), tostring(step_id_of(entry))},
                            {required = required, reached = reached, sink = sink, step_id = step_id_of(entry)})
                    end
                end
            end
            for _, segment in ipairs(work.segments) do
                local count, total = 0, 0
                for _, allocation in ipairs(segment.allocations or {}) do if (allocation.flow_id or segment.flow_id) == flow_id then count = count + 1; total = total + flow_share(allocation) end end
                if count > 1 and total > segment_capacity(work, segment, segment.kind or "belt") + tolerance(total) then error_record(work.errors, "BP_V_TARGET_SHORTFALL", {tostring(flow_id), tostring(segment.segment_id)}, {reason = "simultaneous consumers exceed segment capacity"}) end
            end
        end
    end
    return true
end

local function connection_for(info) return info.entity.connection or info.entity.underground_connection or info.entity.pipe_connection end

local function check_underground(work)
    local underground = {}
    for _, info in ipairs(work.infos) do
        if info.entity.ug_pair_id or info.entity.ug_role or info.entity.underground_pair_id then underground[#underground + 1] = info end
    end
    local checked = {}
    local function pair_key(a, b)
        local left, right = tostring(a.id), tostring(b and b.id or "")
        if left > right then left, right = right, left end
        return left .. "\0" .. right
    end
    local function middle_segment(source, sink)
        local sx, sy = tile_of(source); local tx, ty = tile_of(sink)
        local horizontal, vertical = sy == ty and sx ~= tx, sx == tx and sy ~= ty
        if not horizontal and not vertical then return nil end
        local min_x, max_x, min_y, max_y = math.min(sx, tx), math.max(sx, tx), math.min(sy, ty), math.max(sy, ty)
        local function between(x, y)
            return (horizontal and y == sy and x > min_x and x < max_x)
                or (vertical and x == sx and y > min_y and y < max_y)
        end
        --Only a run PARALLEL to the span is a second path for this flow.  A run crossing it at a right angle is
        --the very thing an underground is for, and the engine places it: contract 26.5 names the hazard as "an
        --intervening ENDPOINT that steals the pairing", never a surface belt, and logic/bp/route.lua:1672
        --already refuses an intervening endpoint for exactly that reason.
        --Measured 2026-09-22 on legalcopilot-dev, first record on the player's sheet: pair r:1481 to r:1482 ran
        --(11,26) to (8,26) facing WEST, and the flagged middle r:1372 at (10,26) faced NORTH, carrying the same
        --item/iron-gear-wheel on a genuine right-angle crossing.  Flow equality alone flagged 7 such crossings.
        --A direction this validator cannot read stays flagged, because an unknown run may well be parallel.
        local function parallel_to_span(direction)
            if direction == nil then return true end
            if horizontal then return direction == Grid.EAST or direction == Grid.WEST end
            return direction == Grid.NORTH or direction == Grid.SOUTH
        end
        -- Same-fluid surface pipes do not interact with a pipe-to-ground span (legalcopilot-dev, 2026-09-28).
        if transport_kind(source) == "pipe" or transport_kind(sink) == "pipe" then return nil end
        local source_flow = source.entity.flow_id
        --Walk only the tiles strictly inside the span through the per-work tile index, and keep the match that comes
        --first in work.infos / work.segments order, so the answer equals the old whole-list scan. The scan per pair
        --made one 0.99 s tick on the gray + magenta sheet (legalcopilot-dev, 2026-09-28).
        local cache = tile_cache[work]
        if not cache then cache = build_tile_cache(work); tile_cache[work] = cache end
        local span = {}
        if horizontal then for x = min_x + 1, max_x - 1 do span[#span + 1] = tile_key(x, sy) end
        elseif vertical then for y = min_y + 1, max_y - 1 do span[#span + 1] = tile_key(sx, y) end end
        local best, best_at, best_index
        for _, key in ipairs(span) do
            for _, candidate in ipairs(cache.infos[key] or {}) do
                if candidate ~= source and candidate ~= sink and transport_kind(candidate)
                    and source_flow ~= nil and candidate.entity.flow_id == source_flow
                    and parallel_to_span(entity_direction(candidate)) then
                    local x, y = tile_of(candidate)
                    local index = cache.info_order[candidate]
                    if between(x, y) and (best_index == nil or index < best_index) then
                        best, best_at, best_index = candidate, {x = x, y = y}, index
                    end
                end
            end
        end
        if best then return best, best_at end
        local seg_best, seg_at, seg_index
        for _, key in ipairs(span) do
            for _, segment in ipairs(cache.segments[key] or {}) do
                local index = cache.segment_order[segment]
                if seg_index == nil or index < seg_index then
                    local found, at = (function()
            local same_flow = segment.flow_id == source_flow
            if not same_flow then
                for _, allocation in ipairs(segment.allocations or {}) do
                    if allocation.flow_id == source_flow then same_flow = true; break end
                end
            end
            if same_flow and parallel_to_span(segment.direction) then
                local points = segment.cells or segment.tiles or segment.path or segment.positions
                for _, point in ipairs(list_from(points)) do
                    local x, y
                    if type(point) == "table" then
                        x, y = finite(point.x), finite(point.y)
                        if x == nil or y == nil then x, y = finite(point[1]), finite(point[2]) end
                    end
                    if x ~= nil and y ~= nil and between(math.floor(x), math.floor(y)) then
                        return segment, {x = math.floor(x), y = math.floor(y)}
                    end
                end
            end
            return nil end)()
                    if found then seg_best, seg_at, seg_index = found, at, index end
                end
            end
        end
        if seg_best then return seg_best, seg_at end
        return nil
    end
    for _, info in ipairs(underground) do
        local pair_id = info.entity.ug_pair_id or info.entity.underground_pair_id
        local pair = work.info_by_id[pair_id]
        if pair and (pair.entity.ug_pair_id or pair.entity.underground_pair_id) ~= info.id then pair = nil end
        local already_checked = pair and checked[pair_key(info, pair)]
        if pair and not already_checked then
            checked[pair_key(info, pair)] = true
        end
        if already_checked then
            -- The reciprocal endpoint is checked with the first endpoint only.
        elseif not pair then
            error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair_id)})
        elseif pair and pair.entity.flow_id and info.entity.flow_id and pair.entity.flow_id ~= info.entity.flow_id then
            error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "flow differs"})
        else
            local first_type, second_type = endpoint_type(info), endpoint_type(pair)
            if not first_type or not second_type or first_type == second_type then
                error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "endpoints must be one input and one output"})
            end
            local source, sink = first_type == "input" and info or pair, first_type == "input" and pair or info
            local sx, sy = tile_of(source); local tx, ty = tile_of(sink)
            local dx, dy = tx - sx, ty - sy
            local expected = Grid.dir_from_vector(dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1))
            if not expected or (dx ~= 0 and dy ~= 0) or (dx == 0 and dy == 0) then
                error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "endpoints are not cardinally aligned"})
            end
            local source_direction, sink_direction = entity_direction(source), entity_direction(sink)
            --A pipe-to-ground faces its exposed connection: the entry looks back along the span, the exit on.
            local pipe_pair = transport_kind(info) == "pipe" or transport_kind(pair) == "pipe"
            local expected_source = (expected and pipe_pair) and Grid.dir_opposite(expected) or expected
            if expected and ((source_direction ~= nil and source_direction ~= expected_source)
                or (sink_direction ~= nil and sink_direction ~= expected)) then
                error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "endpoints do not carry transport direction"})
            end
            local distance = math.abs(info.cx - pair.cx) + math.abs(info.cy - pair.cy)
            local first, second = connection_for(source), connection_for(sink)
            local kind = (transport_kind(info) == "pipe" or transport_kind(pair) == "pipe") and "pipe" or "belt"
            local family = kind == "pipe" and work.catalog.pipe or work.catalog.belt
            local first_max = finite(first and first.max_underground_distance, finite(family and family.underground_max_distance, INF))
            local second_max = finite(second and second.max_underground_distance, finite(family and family.underground_max_distance, INF))
            if distance > first_max + tolerance(first_max) or distance > second_max + tolerance(second_max) then
                error_record(work.errors, "BP_V_UNDERGROUND_RANGE", {tostring(info.id), tostring(pair.id)}, {distance = distance, first_max = first_max, second_max = second_max})
            end
            if first and second and first.direction and second.direction then
                if expected and (first.direction ~= expected or second.direction ~= Grid.dir_opposite(expected)) then
                    error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "connections do not face each other"})
                end
            elseif (first and first.direction and expected and first.direction ~= expected)
                or (second and second.direction and expected and second.direction ~= Grid.dir_opposite(expected)) then
                error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "connection does not face its partner"})
            end
            local middle, point = middle_segment(source, sink)
            if middle then
                error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id), tostring(middle.id or middle.segment_id)},
                    {reason = "middle tile carries the underground flow", point = point})
            end
        end
    end
    return true
end


local function port_owner(work, port)
    local wanted = port.block_id
    local owner
    for _, block in ipairs(work.blocks or {}) do
        local block_id = block.block_id or block.id
        if wanted == nil then
            for _, candidate in ipairs(list_from(block.ports or block.block_ports)) do
                if (candidate.port_id or candidate.id) == port.port_id then owner = block; break end
            end
        elseif block_id == wanted then
            owner = block
        end
        if owner then break end
    end
    if not owner then return nil end
    local block_id = owner.block_id or owner.id
    local placement = work.placements[block_id] or owner.placement or owner
    return owner, {x = finite(placement.x, 0), y = finite(placement.y, 0), dir = finite(placement.dir, Grid.NORTH)}
end

local function port_position(work, port)
    local x, y = finite(port.x), finite(port.y)
    if x ~= nil and y ~= nil then return x, y end
    local owner, placement = port_owner(work, port)
    if not owner then return nil end
    --An external perimeter port carries a rate and a flow but no block attachment: it is the sheet's own
    --input or output, not a tile on a block edge. Deriving a position for it is impossible, and the caller
    --at check_port_approaches already skips a port whose position is nil, exactly as it skips one with no
    --owner. Without this guard Grid.place_port does arithmetic on a nil attach_dx and the whole validation
    --stage dies -- which no run reached while grouping still failed earlier.
    if port.attach_dx == nil or port.attach_dy == nil then return nil end
    local frame = {w = finite(port._block_w, finite(owner.w, 1)), h = finite(port._block_h, finite(owner.h, 1))}
    local placed = Grid.place_port(frame, placement, port)
    return placed.x, placed.y
end

--A block port's travel direction is written in the block's own frame, and the block may be placed rotated. The
--placed approach tile follows the rotated direction, exactly as the placed position follows the rotated
--attachment. Reading the raw direction aimed the approach at a neighbouring port's tile, so a belt legally
--serving that neighbour was reported as this port's wrong edge.
local function port_travel_direction(work, port)
    local direction = port.travel_dir or port.dir or port.normal_dir
    if direction == nil then return nil end
    if port.x ~= nil or port.y ~= nil then return direction end
    local owner, placement = port_owner(work, port)
    if not owner then return direction end
    return Grid.rotate_dir(direction, placement.dir)
end

local function entry_flow_id(entry)
    return type(entry) == "table" and (entry.flow_id or entry.full_name or entry.name or entry.item_name) or entry
end

local function plan_entries(step, field)
    return type(step) == "table" and list_from(step[field]) or {}
end

local function cell_inside_machine(machine, x, y)
    local left, top, width, height = entity_tile_rect(machine)
    return x >= left and x < left + width and y >= top and y < top + height
end

local function transfer_cells(info, work)
    local entity = info.entity or {}
    local inserter = info.spec or {}
    local catalog = work and work.catalog or {}
    local family = catalog.inserter or {}
    if catalog.long_inserter and entity.name == catalog.long_inserter.name then family = catalog.long_inserter
    elseif not catalog.long_inserter and (entity.long == true or entity.name == "long-handed-inserter") then
        --No captured long-hand facts (an older capture): the long hand reaches twice as far as the plain one, the
        --same fallback groups.lua uses (docs/contracts/row_block.md §Far belt).
        local function doubled(offset)
            return offset and {x = (finite(offset.x) or 0) * 2, y = (finite(offset.y) or 0) * 2} or nil
        end
        family = {pickup_offset = doubled(family.pickup_offset),
            drop_offset = doubled(family.drop_offset or family.drop_position)}
    end
    local pickup_offset = inserter.pickup_offset or family.pickup_offset
    local drop_offset = inserter.drop_offset or inserter.drop_position or family.drop_offset or family.drop_position
    local pickup_x, pickup_y, drop_x, drop_y
    if pickup_offset and drop_offset then
        local pickup_local_x, pickup_local_y = finite(pickup_offset.x), finite(pickup_offset.y)
        local drop_local_x, drop_local_y = finite(drop_offset.x), finite(drop_offset.y)
        local pickup_dx, pickup_dy, drop_dx, drop_dy
        if pickup_local_x ~= nil and pickup_local_y ~= nil and drop_local_x ~= nil and drop_local_y ~= nil then
            pickup_dx, pickup_dy = Grid.rotate_vector(pickup_local_x, pickup_local_y,
                entity_direction(info) or Grid.NORTH)
            drop_dx, drop_dy = Grid.rotate_vector(drop_local_x, drop_local_y,
                entity_direction(info) or Grid.NORTH)
        end
        if pickup_dx ~= nil and pickup_dy ~= nil and drop_dx ~= nil and drop_dy ~= nil then
            pickup_x, pickup_y = math.floor(info.cx + pickup_dx + EPSILON), math.floor(info.cy + pickup_dy + EPSILON)
            drop_x, drop_y = math.floor(info.cx + drop_dx + EPSILON), math.floor(info.cy + drop_dy + EPSILON)
        end
    end
    return pickup_x, pickup_y, drop_x, drop_y
end

--Transport shape guards, judged on the candidate's own tile geometry.  Round 21, legalcopilot-dev 2026-09-23.
--
--A belt has two lanes, named relative to travel: L and R.  Items enter at inserter DROP tiles -- far lane seen
--from the inserter, the belt's R lane when the belt runs straight away from or toward it -- and travel on:
--straight feeds, curves, underground pairs and splitters keep the lane; a side-load onto a belt that already
--has a feed from behind moves everything to the NEAR lane.  A side-load into an underground INPUT is the
--case the player saw stall in game at (14,4) -> (13,4): the inlet's hood is its front half, so the feeder
--lane on the side the inlet FACES is blocked.  A side-load is legal (the player's rule: a last resort); it is
--a violation only when the blocked lane actually carries items.  An untraced lane is never read as empty:
--the walk starts at every drop tile and follows every hop, so a lane that carries nothing is one no item
--can reach.
local function transport_tiles(work)
    local tiles = {}
    for _, info in ipairs(work.infos) do
        if transport_kind(info) == "belt" then
            local entity = info.entity or {}
            local d = entity_direction(info) or Grid.NORTH
            local name = tostring(name_of(entity) or ""):lower()
            if entity.splitter or name:find("splitter", 1, true) then
                local ax, ay, bx, by
                if d == Grid.NORTH or d == Grid.SOUTH then
                    ax, ay = math.floor(info.cx - 0.5 + EPSILON), math.floor(info.cy + EPSILON); bx, by = ax + 1, ay
                else
                    ax, ay = math.floor(info.cx + EPSILON), math.floor(info.cy - 0.5 + EPSILON); bx, by = ax, ay + 1
                end
                tiles[tile_key(ax, ay)] = {info = info, kind = "splitter", d = d, x = ax, y = ay, other = tile_key(bx, by)}
                tiles[tile_key(bx, by)] = {info = info, kind = "splitter", d = d, x = bx, y = by, other = tile_key(ax, ay)}
            else
                local x, y = tile_of(info)
                local ug = endpoint_type(info)
                tiles[tile_key(x, y)] = {info = info, kind = ug and "underground" or "belt", ug = ug, d = d, x = x, y = y}
            end
        end
    end
    return tiles
end

local function check_transport_shapes(work)
    local tiles = transport_tiles(work)
    local function right_of(d) local dx, dy = Grid.dir_vector(d); return -dy, dx end
    local pair_of = {}
    for key, tile in pairs(tiles) do
        if tile.ug == "input" then
            local partner = work.info_by_id[tile.info.entity.ug_pair_id or tile.info.entity.underground_pair_id]
            if partner then local px, py = tile_of(partner); pair_of[key] = tile_key(px, py) end
        end
    end
    local function outputs(key)
        local tile = tiles[key]
        if tile.ug == "input" then return {pair_of[key]} end
        local dx, dy = Grid.dir_vector(tile.d)
        if dx == nil then return {} end
        return {tile_key(tile.x + dx, tile.y + dy)}
    end
    local function fed_from_behind(key)
        local tile = tiles[key]
        local dx, dy = Grid.dir_vector(tile.d)
        local behind = dx and tiles[tile_key(tile.x - dx, tile.y - dy)]
        if not behind or behind.ug == "input" then return false end
        return behind.d == tile.d
    end
    local lanes, witnesses, queue, head = {}, {}, {}, 1
    local function add(key, lane, flow_id)
        if tiles[key] == nil then return end
        lanes[key] = lanes[key] or {}
        if not lanes[key][lane] then lanes[key][lane] = true end
        if flow_id then
            witnesses[key] = witnesses[key] or {L = {}, R = {}}
            if not witnesses[key][lane][flow_id] then witnesses[key][lane][flow_id] = true; queue[#queue + 1] = {key, lane, flow_id} end
        elseif not lanes[key][lane .. "_walked"] then
            lanes[key][lane .. "_walked"] = true; queue[#queue + 1] = {key, lane, false}
        end
    end
    for _, hand in ipairs(work.inserters or {}) do
        local _, _, drop_x, drop_y = transfer_cells(hand, work)
        if drop_x == nil then
            --No catalog offsets: the internal frame's own rule, dir points at the drop tile.
            local hx, hy = tile_of(hand)
            local dx, dy = Grid.dir_vector(entity_direction(hand) or Grid.NORTH)
            if dx then drop_x, drop_y = hx + dx, hy + dy end
        end
        local tile = drop_x and tiles[tile_key(drop_x, drop_y)]
        if tile then
            local rx, ry = right_of(tile.d)
            local hx, hy = tile_of(hand)
            local dot = (hx - drop_x) * rx + (hy - drop_y) * ry
            local lane, ids = dot > 0 and "L" or "R", declared_flow_ids(hand)
            if #ids == 0 then add(tile_key(drop_x, drop_y), lane)
            else for _, flow_id in ipairs(ids) do add(tile_key(drop_x, drop_y), lane, flow_id) end end
        end
    end
    --A belt chain's first tile (no transport tile feeds it) carries its declared flows on both lanes; every
    --other tile learns its flows only from what reaches it, so a side-load puts a flow on its near lane alone.
    local fed = {}
    for key, _ in pairs(tiles) do
        for _, next_key in ipairs(outputs(key)) do if next_key then fed[next_key] = true end end
    end
    --A chain start that declares two or more flows is a mixed supply whose lanes this candidate never shows;
    --its flows are witnessed as present with lane unknown ("?" suffix), which proves presence but never a mix.
    for key, tile in pairs(tiles) do
        if tile.kind == "belt" and not fed[key] then
            local declared = declared_flow_ids(tile.info)
            local hand_fed = false
            for _, hand in ipairs(work.inserters or {}) do
                local _, _, dx, dy = transfer_cells(hand, work)
                if dx == tile.x and dy == tile.y then hand_fed = true; break end
            end
            if not hand_fed then
                local edge = tile.x == 0 or tile.y == 0 or tile.x == (work.grid_w or 0)-1 or tile.y == (work.grid_h or 0)-1
                if not edge then
                    error_record(work.errors, "BP_V_BELT_NO_SOURCE", {tostring(tile.info.id)}, {x=tile.x,y=tile.y})
                end
                for _, flow_id in ipairs(declared) do
                    local tag = #declared > 1 and (tostring(flow_id) .. "?") or flow_id
                    add(key, "L", tag); add(key, "R", tag)
                end
            end
        end
    end
    --A splitter fed on both of its input halves by the two outputs of one splitter is redundant.
    local checked = {}
    for _, tile in pairs(tiles) do
        if tile.kind == "splitter" and not checked[tile.info.id] then
            checked[tile.info.id] = true
            local input_sources, input_counts = {}, {}
            for source_key in pairs(tiles) do
                for _, dest in ipairs(outputs(source_key)) do
                    if dest == tile_key(tile.x, tile.y) or dest == tile.other then
                        local source = tiles[source_key]
                        input_counts[dest] = (input_counts[dest] or 0) + 1
                        if source and source.kind == "splitter" then
                            input_sources[tile.info.id .. ":" .. dest] = {id=source.info.id, key=source_key}
                        end
                    end
                end
            end
            local a=input_sources[tile.info.id .. ":" .. tile_key(tile.x,tile.y)]
            local b=input_sources[tile.info.id .. ":" .. tile.other]
            local same_flow = false
            if a and b and a.id==b.id then
                local upstream = tiles[a.key]
                local left, right = declared_flow_ids(tile.info), declared_flow_ids(upstream.info)
                for _, flow_id in ipairs(left) do for _, source_flow in ipairs(right) do if flow_id==source_flow then same_flow=true end end end
            end
            if a and b and input_counts[tile_key(tile.x,tile.y)]==1 and input_counts[tile.other]==1
                and a.id==b.id and a.key~=b.key and same_flow
                and #declared_flow_ids(tile.info)==1 and #declared_flow_ids(tiles[a.key].info)==1 then
                error_record(work.errors,"BP_V_SPLITTER_CHAIN",{tostring(tile.info.id),tostring(a.id)})
            end
        end
    end
    --A side entry puts every item of the feeding belt on the near lane, so a lane-unknown witness becomes known.
    local function known(flow_id)
        if type(flow_id) == "string" and flow_id:sub(-1) == "?" then return flow_id:sub(1, -2) end
        return flow_id
    end
    local blocked = {}
    while head <= #queue do
        local key, lane, flow_id = queue[head][1], queue[head][2], queue[head][3]
        head = head + 1
        local from = tiles[key]
        for _, next_key in ipairs(outputs(key)) do
            local to = next_key and tiles[next_key]
            --An underground exit takes items only from its own entrance, never from a surface belt behind it.
            if to and to.ug == "output" and from.ug ~= "input" then to = nil end
            if to then
                if from.ug == "input" or from.d == to.d then
                    add(next_key, lane, flow_id)
                    if to.kind == "splitter" then add(to.other, lane, flow_id) end
                elseif from.d ~= Grid.dir_opposite(to.d) then
                    local rx, ry = right_of(to.d)
                    local near = ((from.x - to.x) * rx + (from.y - to.y) * ry) > 0 and "R" or "L"
                    if to.ug == "input" then
                        local frx, fry = right_of(from.d)
                        local side_x, side_y = frx, fry
                        if lane == "L" then side_x, side_y = -frx, -fry end
                        local ix, iy = Grid.dir_vector(to.d)
                        if side_x == ix and side_y == iy then
                            local mark = key .. ">" .. next_key
                            if not blocked[mark] then
                                blocked[mark] = true
                                error_record(work.errors, "BP_V_UNDERGROUND_SIDELOAD_BLOCKED",
                                    {tostring(from.info.id), tostring(to.info.id)},
                                    {feeder = {x = from.x, y = from.y}, underground_input = {x = to.x, y = to.y}, lane = lane})
                            end
                        else
                            add(next_key, near, known(flow_id))
                        end
                    elseif to.kind == "belt" and not fed_from_behind(next_key) then
                        add(next_key, lane)
                        -- A side-fed head places its entering item on the lane nearest the feed side.
                        add(next_key, near, known(flow_id))
                    else
                        add(next_key, near, known(flow_id))
                        if to.kind == "splitter" then add(to.other, near, known(flow_id)) end
                    end
                end
            end
        end
    end
    --The player placed green v2 on 2026-09-24 and boxed two "belt bleeding" spots: a flow's last belt pointed
    --into another flow's belt, so its items ran on (circuits onto the science belt, gears onto the foundry's
    --iron stub).  A tile that declares its flows may carry only those: any other flow reaching it leaked in.
    local bled = {}
    for _, key in ipairs(sorted_keys(witnesses)) do
        local declared = declared_flow_ids(tiles[key].info)
        if #declared > 0 then
            local set = {}
            for _, flow_id in ipairs(declared) do set[flow_id] = true end
            for _, lane in ipairs({"L", "R"}) do
                for _, flow_id in ipairs(sorted_keys(witnesses[key][lane] or {})) do
                    local leaked = known(flow_id)
                    if not set[leaked] and not bled[leaked .. ">" .. tostring(tiles[key].info.id)] then
                        bled[leaked .. ">" .. tostring(tiles[key].info.id)] = true
                        error_record(work.errors, "BP_V_BELT_BLEED", {tostring(tiles[key].info.id)},
                            {tile = {x = tiles[key].x, y = tiles[key].y}, lane = lane, flow = leaked, declared = declared})
                    end
                end
            end
        end
    end
    for _, hand in ipairs(work.inserters or {}) do
        local entity = hand.entity or hand
        local ids = declared_flow_ids(hand)
        if entity.role == "input" and #ids == 2 then
            local px, py = transfer_cells(hand, work)
            local found = px and witnesses[tile_key(px, py)] or {L = {}, R = {}}
            local left, right, valid = {}, {}, true
            for flow_id in pairs(found.L or {}) do left[#left + 1] = flow_id end
            for flow_id in pairs(found.R or {}) do right[#right + 1] = flow_id end
            table.sort(left); table.sort(right)
            for _, flow_id in ipairs(ids) do
                local unknown = tostring(flow_id) .. "?"
                if not found.L[flow_id] and not found.R[flow_id] and not found.L[unknown] and not found.R[unknown] then
                    valid = false
                end
            end
            for _, a in ipairs(ids) do for _, b in ipairs(ids) do
                if a ~= b and ((found.L[a] and found.L[b]) or (found.R[a] and found.R[b])) then valid = false end
            end end
            if not valid then error_record(work.errors, "BP_V_LANE_MIX", {tostring(hand.id)},
                {hand_id = tostring(hand.id), tile = {x = px, y = py}, flows = {L = left, R = right}}) end
        end
    end
    for key, tile in pairs(tiles) do
        if tile.ug == "output" then
            local dx, dy = Grid.dir_vector(tile.d)
            local next_key = dx and tile_key(tile.x + dx, tile.y + dy)
            local next_tile = next_key and tiles[next_key]
            if next_tile and next_tile.ug == "input" and next_tile.d == tile.d then
                local origin = work.info_by_id[tile.info.entity.ug_pair_id or tile.info.entity.underground_pair_id]
                local finish = work.info_by_id[next_tile.info.entity.ug_pair_id or next_tile.info.entity.underground_pair_id]
                if origin and finish then
                    local nm = tostring(name_of(tile.info.entity) or "")
                    local family_reach = nm:find("turbo%-") and 11 or nm:find("express%-") and 9 or nm:find("fast%-") and 7 or 5
                    local reach = finite(tile.info.entity.max_underground_distance,
                        finite(work.catalog.belt and work.catalog.belt.underground_max_distance, family_reach))
                    local span = math.abs(origin.cx - finish.cx) + math.abs(origin.cy - finish.cy)
                    if span <= reach then
                        error_record(work.errors, "BP_V_UNDERGROUND_BACK_TO_BACK",
                            {tostring(tile.info.id), tostring(next_tile.info.id)}, {span = span, reach = reach})
                    end
                end
            end
        end
    end
    --A directed cycle over every hop, splitter tiles included: colour walk, iterative so a long run never
    --overflows the Lua stack.
    local colour = {}
    local keys = {}
    for key in pairs(tiles) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, start in ipairs(keys) do
        if colour[start] == nil then
            local stack = {{start, 1}}
            colour[start] = 1
            while #stack > 0 do
                local top = stack[#stack]
                local key, index = top[1], top[2]
                local successors = outputs(key)
                if tiles[key].kind == "splitter" then
                    local other = tiles[tiles[key].other]
                    local dx, dy = Grid.dir_vector(other.d)
                    successors[#successors + 1] = dx and tile_key(other.x + dx, other.y + dy)
                end
                local next_key = successors[index]
                if index > #successors then
                    colour[key] = 2
                    stack[#stack] = nil
                else
                    top[2] = index + 1
                    if next_key and tiles[next_key] and not (tiles[key].ug ~= "input"
                        and tiles[next_key].d == Grid.dir_opposite(tiles[key].d)) then
                        if colour[next_key] == 1 then
                            local tile = tiles[next_key]
                            error_record(work.errors, "BP_V_ROUTE_LOOP", {tostring(tile.info.id)},
                                {x = tile.info.cx, y = tile.info.cy})
                            return true
                        elseif colour[next_key] == nil then
                            colour[next_key] = 1
                            stack[#stack + 1] = {next_key, 1}
                        end
                    end
                end
            end
        end
    end
    return true
end

local function cell_occupant(work, x, y)
    if x == nil or y == nil then return nil end
    x, y = math.floor(x), math.floor(y)
    local cache = tile_cache[work]
    if not cache then cache = build_tile_cache(work); tile_cache[work] = cache end
    local list = cache.infos[tile_key(x, y)]
    if list then return list[1] end
    return nil
end

build_tile_cache = function(work)
    local infos, segments = {}, {}
    local function add(index, x, y, value)
        local key = tile_key(x, y); index[key] = index[key] or {}; index[key][#index[key] + 1] = value
    end
    for _, info in ipairs(work.infos) do
        local left, top, width, height = entity_tile_rect(info)
        for x = left, left + width - 1 do for y = top, top + height - 1 do add(infos, x, y, info) end end
    end
    for _, segment in ipairs(work.segments) do
        local points = segment.cells or segment.tiles or segment.path or segment.positions
        local seen = {}
        for _, point in ipairs(list_from(points)) do
            local x, y = type(point) == "table" and finite(point.x) or nil, type(point) == "table" and finite(point.y) or nil
            if x == nil and type(point) == "table" then x, y = finite(point[1]), finite(point[2]) end
            --A segment is listed once per tile: occupant_at walks the segment's own points again for the report.
            if x ~= nil and y ~= nil and not seen[tile_key(math.floor(x), math.floor(y))] then
                seen[tile_key(math.floor(x), math.floor(y))] = true
                add(segments, math.floor(x), math.floor(y), segment)
            end
        end
    end
    local info_order, segment_order = {}, {}
    for index, info in ipairs(work.infos) do info_order[info] = index end
    for index, segment in ipairs(work.segments) do segment_order[segment] = index end
    return {infos = infos, segments = segments, info_order = info_order, segment_order = segment_order}
end

local function legal_transfer_occupant(info)
    return info and (transport_kind(info) == "belt" or is_machine(info))
end

local function transfer_endpoint_error(work, inserter, x, y, role)
    local occupant = cell_occupant(work, x, y)
    if legal_transfer_occupant(occupant) then return occupant end
    local found = occupant and (occupant.kind or name_of(occupant.entity)) or "empty ground"
    error_record(work.errors, "BP_V_INSERTER_GEOMETRY", {tostring(inserter.id), tostring(found)},
        {reason = "inserter " .. tostring(role) .. " cell has invalid occupant", cell = {x = x, y = y},
            found = found})
    return occupant
end

local function external_port_for(work, flow_id, role)
    for _, port in ipairs(work.ports) do
        if is_external_port(port) and (port.role or port.direction) == role then
            if flow_id == nil or flow_compatible(port, flow_id) then return port end
        end
    end
    return nil
end

local function external_path(work, flow_id, role, start_x, start_y, kind)
    for _, port in ipairs(work.ports) do
        if is_external_port(port) and (port.role or port.direction) == role then
            if flow_id == nil or flow_compatible(port, flow_id) then
                local px, py = port_position(work, port)
                if role == "in" then
                    local path = transport_path(work, px, py, start_x, start_y, flow_id, kind)
                    if path then return port, path end
                else
                    local path = transport_path(work, start_x, start_y, px, py, flow_id, kind)
                    if path then return port, path end
                end
            end
        end
    end
    return nil
end

local function external_reachable(work, flow_id, role, start_x, start_y, kind)
    return external_path(work, flow_id, role, start_x, start_y, kind) ~= nil
end

local function external_failure_step(work, flow_id, role, start_x, start_y, kind)
    for _, port in ipairs(work.ports) do
        if is_external_port(port) and (port.role or port.direction) == role then
            if flow_id == nil or flow_compatible(port, flow_id) then
                local px, py = port_position(work, port)
                if role == "in" then
                    return transport_failure_step(work, px, py, start_x, start_y, flow_id, kind)
                end
                return transport_failure_step(work, start_x, start_y, px, py, flow_id, kind)
            end
        end
    end
    return "external:" .. tostring(flow_id)
end

local function machine_ports_for(work, machine, flow_id, role)
    local result = {}
    for _, port in ipairs(work.ports) do
        if not is_external_port(port) and (port.role or port.direction) == role
            and (port.step_id == nil or port.step_id == machine.entity.step_id) then
            if flow_id == nil or flow_compatible(port, flow_id) then
                --A row port serves every machine of its row: they share one belt run (docs/contracts/row_block.md).
                if port.member_id == nil or port.row_port or port.member_id == machine.id
                    or port.member_id == machine.entity.machine_id then
                    result[#result + 1] = port
                end
            end
        end
    end
    return result
end

local function flow_record(work, flow_id)
    for _, flow in ipairs(work.flows or {}) do
        if flow_id_of(flow) == flow_id then return flow end
    end
    return nil
end

local function flow_side_has_external(work, flow_id, side)
    local flow = flow_record(work, flow_id)
    local records = list_from(flow and flow[side])
    if #records == 0 then return true end
    for _, record in ipairs(records) do
        if step_id_of(record) == "$external" then return true end
    end
    return false
end

local function machines_for_step(work, step_id)
    local result = {}
    for _, machine in ipairs(work.machines) do
        if machine.entity.step_id == step_id then result[#result + 1] = machine end
    end
    return result
end

--Return the physical route for an item obligation.  The edge of the factory is one possible source/sink; an
--intermediate machine port is the other.  A flow with no producer/consumer metadata is an old fixture shape and
--is conservatively treated as external, so absence of its declared perimeter endpoint still rejects it.
local function connection_path(work, flow_id, role, x, y, kind)
    kind = kind or "belt"
    local external_role = role == "input" and "in" or "out"
    if flow_side_has_external(work, flow_id, role == "input" and "producers" or "consumers") then
        local port, path = external_path(work, flow_id, external_role, x, y, kind)
        if port then return port, path, nil end
    end
    local flow = flow_record(work, flow_id)
    local side = role == "input" and "producers" or "consumers"
    local missing_port_machine
    local found_port, found_path, found_machine
    for _, record in ipairs(list_from(flow and flow[side])) do
        local step_id = step_id_of(record)
        if step_id and step_id ~= "$external" then
            for _, machine in ipairs(machines_for_step(work, step_id)) do
                local ports = machine_ports_for(work, machine, flow_id, role == "input" and "out" or "in")
                if #ports == 0 then missing_port_machine = missing_port_machine or machine end
                --A machine can expose multiple ports for one flow on separate belt lines. Test each port:
                --choosing only the first made a connected second hand look disconnected and its whole line waste.
                --`local px, py = port and port_position(...)` was silently WRONG: in Lua a call as the right
                --operand of `and` is adjusted to exactly ONE value, so `py` was ALWAYS nil and every internal
                --machine-to-machine walk died on transport_path's first line, which refuses a nil endpoint.
                --Only flows produced at the sheet edge survived, because those go through external_path.
                --Measured 2026-09-22 on legalcopilot-dev, the player's own sheet: every copper-plate and
                --iron-gear-wheel obligation failed this way and was reported BP_V_ROUTE_DISCONTINUOUS, with
                --every belt behind it then swept up as BP_V_TRANSPORT_UNUSED.
                for _, port in ipairs(ports) do
                    local px, py = port_position(work, port)
                    local path
                    if role == "input" then path = transport_path(work, px, py, x, y, flow_id, kind)
                    else path = transport_path(work, x, y, px, py, flow_id, kind) end
                    if path then found_port, found_path, found_machine = port, path, machine end
                end
            end
        end
    end
    if missing_port_machine then return nil, nil, nil, missing_port_machine end
    return found_port, found_path, found_machine
end

local function pipe_to_ground_faces_away(work, connection)
    if connection.direction == nil then return false end
    for _, info in ipairs(work.transport_by_cell and work.transport_by_cell[point_key(connection.x, connection.y)] or {}) do
        local entity = info.entity or {}
        local entity_name = tostring(name_of(entity) or ""):lower()
        if entity_name:find("pipe-to-ground", 1, true) ~= nil or entity.type == "pipe-to-ground" then
            return entity_direction(info) ~= Grid.dir_opposite(connection.direction)
        end
    end
    return false
end

local function transfer_role(info, machine)
    local entity = info.entity or {}
    if entity.role == "input" or entity.role == "output" then return entity.role end
    if entity.drop_target == machine.id or entity.drop_target == machine.entity.id then return "input" end
    if entity.pickup_target == machine.id or entity.pickup_target == machine.entity.id then return "output" end
    return nil
end

local function transfer_matches(work, info, machine, entry, role, used)
    local multi_flow = multi_flow_hands_enabled(work)
    local wanted = entry_flow_id(entry)
    if multi_flow and used[info.id] and used[info.id][tostring(wanted)] then
        return false
    elseif not multi_flow and used[info.id] then
        return false
    end
    if transfer_role(info, machine) ~= role then return false end
    local entity = info.entity or {}
    if entity.machine_id ~= nil and entity.machine_id ~= machine.id and entity.machine_id ~= machine.entity.id then return false end
    local actual = entity.flow_id or entity.full_name
    if multi_flow then
        if wanted == nil or not declares_flow(entity, wanted) then return false end
    elseif actual ~= nil and wanted ~= nil and actual ~= wanted then
        return false
    end
    local pickup_x, pickup_y, drop_x, drop_y = transfer_cells(info, work)
    if pickup_x == nil or drop_x == nil then return false end
    if role == "input" and not cell_inside_machine(machine, drop_x, drop_y) then return false end
    if role == "output" and not cell_inside_machine(machine, pickup_x, pickup_y) then return false end
    local source_x, source_y = role == "input" and pickup_x or drop_x, role == "input" and pickup_y or drop_y
    if not transport_at(work, source_x, source_y, wanted, "belt") then return false end
    return pickup_x, pickup_y, drop_x, drop_y
end

local function fluid_connection_cells(machine, entry, role)
    local boxes = machine.spec and (machine.spec.fluid_boxes or machine.spec.fluidbox_prototypes)
    if type(boxes) ~= "table" then return {} end
    local result = {}
    local wanted_box = entry and (entry.fluidbox_index or entry.box_index)
    local wanted_connection = entry and (entry.connection_index or entry.pipe_connection_index)
    local dir = entity_direction(machine) or Grid.NORTH
    local rotation_index = math.floor((dir % 16) / 4) + 1
    for box_index, box in ipairs(boxes) do
        local production = box.production_type or box.type or box.role
        if (wanted_box == nil or wanted_box == box.index or wanted_box == box_index)
            and (production == nil or production == role or (role == "input" and production == "input")
                or (role == "output" and production == "output")) then
            local connections = box.pipe_connections or box.connections or {}
            for connection_index, connection in ipairs(connections) do
                if wanted_connection == nil or wanted_connection == connection_index then
                    local position
                    if type(connection.positions) == "table" then
                        position = connection.positions[rotation_index]
                    else
                        --Older hand-written fixtures used one north-frame position.  Captured catalogs use
                        --the four-entry `positions` vector above; this compatibility branch still rotates the
                        --singular fixture value into the entity frame.
                        position = connection.position or connection.pos
                    end
                    if type(position) == "table" then
                        local px, py = finite(position.x), finite(position.y)
                        if px ~= nil and py ~= nil then
                            if type(connection.positions) ~= "table" then px, py = Grid.rotate_vector(px, py, dir) end
                            --The position is the machine's own tile; the pipe that serves it sits one tile out
                            --along the rotated connection direction. Walking from the machine tile found the
                            --machine, never a pipe, so every fluid box read as disconnected.
                            --A hand-written fixture may already name the outside tile (the 1.1 habit); step
                            --out only from a tile the machine itself covers.
                            local outward = connection.direction or connection.dir
                            if outward ~= nil then outward = Grid.rotate_dir(outward, dir) end
                            local cell_x, cell_y = math.floor(machine.cx + px + EPSILON), math.floor(machine.cy + py + EPSILON)
                            local ox, oy = 0, 0
                            if outward ~= nil and cell_inside_machine(machine, cell_x, cell_y) then ox, oy = Grid.dir_vector(outward) end
                            result[#result + 1] = {x = cell_x + (ox or 0), y = cell_y + (oy or 0), direction = outward}
                        end
                    end
                end
            end
        end
    end
    return result
end

local function check_physical_transfers(work, machine_index, final)
    local used = work._physical_used or {}; work._physical_used = used
    local multi_flow = multi_flow_hands_enabled(work)
    local endpoint_checked = work._physical_endpoint_checked or {}; work._physical_endpoint_checked = endpoint_checked

    local function transfer_failure_ladder(candidate_seen, shape_seen, wrong_network, explicit_target)
        if next(work.transport_by_cell) == nil then
            return "BP_V_ROUTE_DISCONTINUOUS", {reason = "candidate has no transport", cause = "no_transport"}
        end
        if candidate_seen and explicit_target and (not shape_seen or wrong_network) then
            if wrong_network then
                return "BP_V_TRANSFER_BROKEN", {reason = "belt is on the wrong flow network", cause = "wrong_network"}
            end
            return "BP_V_TRANSFER_BROKEN", {reason = "belt is missing at the inserter outward tile", cause = "missing_belt"}
        end
        if candidate_seen then
            return "BP_V_ROUTE_DISCONTINUOUS", {reason = "inserter is present but its route is discontinuous", cause = "disconnected_route"}
        end
        return "BP_V_TRANSFER_BROKEN", {reason = "inserter is missing for the required transfer", cause = "missing_inserter"}
    end

    local function mark_used(info, flow_id)
        if multi_flow then
            used[info.id] = used[info.id] or {}
            used[info.id][tostring(flow_id)] = true
        else
            used[info.id] = true
        end
    end

    local function used_any(info)
        if work._collector_witnessed and work._collector_witnessed[info.id] then return true end
        if not multi_flow then return used[info.id] == true end
        return used[info.id] ~= nil and next(used[info.id]) ~= nil
    end

    local flow_id_for_feeds
    --Marks a witnessed path and everything that FEEDS it: a belt behind or side-loading into a used transport, a
    --splitter input, an underground entrance behind its exit. Only upstream: a belt the used line feeds and that
    --leads nowhere is waste and stays BP_V_TRANSPORT_UNUSED (tests/test_validate_witness_underground.lua dangle).
    local function pair_of(info)
        local entity = info.entity or {}
        local id = entity.ug_pair_id or entity.underground_pair_id
        return id and work.info_by_id[id] or nil
    end
    local function feeds(candidate, current)
        local partner = work._underground_partner and work._underground_partner[candidate.id] or pair_of(candidate)
        if partner == current then
            --An underground pair joins both ways in the index; the entrance is the end that faces the exit.
            local cx, cy = transport_tile(candidate)
            local tx, ty = transport_tile(current)
            local dx, dy = Grid.dir_vector(entity_direction(candidate) or Grid.NORTH)
            return dx ~= nil and ((tx - cx) * dx + (ty - cy) * dy) > 0
        end
        for _, next_info in ipairs(transport_neighbors(work, candidate, flow_id_for_feeds)) do
            if next_info == current then return true end
        end
        return false
    end
    local function mark_path(path, flow_id)
        local function binding_matches_inserter(binding, inserter)
            local port_id = inserter.entity and inserter.entity.port_id
            local source_id = binding.source_port_id
            return type(port_id) == "string" and type(source_id) == "string"
                and (source_id == port_id or source_id:sub(1, #port_id + 1) == port_id .. ":")
        end
        flow_id_for_feeds = flow_id
        local queue, head, seen = {}, 1, {}
        for _, info in ipairs(path or {}) do
            if not seen[info.id] then seen[info.id] = true; queue[#queue + 1] = info end
        end
        while queue[head] do
            local current = queue[head]; head = head + 1
            mark_used(current, flow_id)
            local x, y = transport_tile(current)
            -- A collector can be fed by several output hands. The route binding may
            -- name just one representative port, so witness every same-flow hand
            -- whose drop cell is this witnessed belt tile.
            local witnessed_output_segments = {}
            for _, inserter in ipairs(work.inserters or {}) do
                if transport_accepts_flow(inserter, flow_id) then
                    local role = inserter.entity and inserter.entity.role
                    if role ~= "output" then
                        local machine = inserter.entity and inserter.entity.machine_id and work.info_by_id[inserter.entity.machine_id]
                        role = machine and transfer_role(inserter, machine) or nil
                    end
                    if role == "output" then
                        local _, _, drop_x, drop_y = transfer_cells(inserter, work)
                        local position = inserter.entity and inserter.entity.drop_position
                        if type(position) == "table" and finite(position.x) ~= nil and finite(position.y) ~= nil then
                            drop_x, drop_y = math.floor(finite(position.x) + EPSILON), math.floor(finite(position.y) + EPSILON)
                        end
                        if drop_x == x and drop_y == y then
                            work._collector_witnessed = work._collector_witnessed or {}
                            work._collector_witnessed[inserter.id] = true
                            for _, binding in ipairs(work.bindings or {}) do
                                if binding.segment_id and binding.flow_id == flow_id and binding_matches_inserter(binding, inserter) then
                                    witnessed_output_segments[binding.segment_id] = true
                                end
                            end
                        end
                    end
                end
            end
            -- Collector bindings retain the shared route segment. Credit only the
            -- same-flow output hands bound to that segment whose own drop tile has
            -- a matching belt; hands elsewhere on the machine stay independently
            -- subject to the transport witness.
            if next(witnessed_output_segments) then
                for _, inserter in ipairs(work.inserters or {}) do
                    local entity = inserter.entity or {}
                    if entity.role == "output" and (entity.flow_id or entity.full_name) == flow_id then
                        local same_route = false
                        for _, binding in ipairs(work.bindings or {}) do
                            if binding.flow_id == flow_id and binding_matches_inserter(binding, inserter)
                                and witnessed_output_segments[binding.segment_id] then same_route = true; break end
                        end
                        if same_route then
                            local position = entity.drop_position
                            local dx, dy
                            if type(position) == "table" and finite(position.x) ~= nil and finite(position.y) ~= nil then
                                dx, dy = math.floor(finite(position.x) + EPSILON), math.floor(finite(position.y) + EPSILON)
                            else
                                local _, _, drop_x, drop_y = transfer_cells(inserter, work); dx, dy = drop_x, drop_y
                            end
                            for _, belt in ipairs(work.transport_by_cell and work.transport_by_cell[point_key(dx, dy)] or {}) do
                                if transport_kind(belt) == "belt" and transport_accepts_flow(belt, flow_id) then
                                    work._collector_witnessed[inserter.id] = true
                                    work._collector_witnessed[belt.id] = true
                                end
                            end
                        end
                    end
                end
            end
            local candidates = {}
            --Belts, splitters and a side-load sit next to what they feed (a splitter is two tiles wide).
            for oy = -2, 2 do
                for ox = -2, 2 do
                    for _, candidate in ipairs(work.transport_by_cell and work.transport_by_cell[point_key(x + ox, y + oy)] or {}) do
                        candidates[#candidates + 1] = candidate
                    end
                end
            end
            --An underground's partner may be many tiles away, and an export may name the pair on one end only.
            if not work._underground_partner then
                work._underground_partner = {}
                for _, info in ipairs(work.infos or {}) do
                    local partner = pair_of(info)
                    if partner then
                        work._underground_partner[info.id] = partner
                        work._underground_partner[partner.id] = work._underground_partner[partner.id] or info
                    end
                end
            end
            candidates[#candidates + 1] = work._underground_partner[current.id]
            for _, candidate in ipairs(candidates) do
                if candidate ~= current and not seen[candidate.id] and transport_kind(candidate) == "belt"
                    and transport_accepts_flow(candidate, flow_id) and feeds(candidate, current) then
                    seen[candidate.id] = true; queue[#queue + 1] = candidate
                end
            end
        end
    end

    local function witness_step(info)
        return {id = tostring(info.id), name = name_of(info.entity), kind = transport_kind(info) or info.kind}
    end

    local function add_witness(key, role, source_id, destination_id, prefix, path, suffix)
        local steps, ids = {}, {}
        local function add(id, info)
            if id == nil then return end
            local text_id = tostring(id)
            if ids[#ids] == text_id then return end
            ids[#ids + 1] = text_id
            if info then steps[#steps + 1] = witness_step(info)
            else steps[#steps + 1] = {id = text_id, kind = "endpoint"} end
        end
        for _, item in ipairs(prefix or {}) do add(item.id or item, item.entity and item or nil) end
        for _, info in ipairs(path or {}) do add(info.id, info) end
        for _, item in ipairs(suffix or {}) do add(item.id or item, item.entity and item or nil) end
        local witness = {key = key, role = role, source_id = tostring(source_id), destination_id = tostring(destination_id),
            ids = ids, steps = steps}
        work.metrics.connection_witnesses[#work.metrics.connection_witnesses + 1] = witness
        work.metrics.transfer_witnesses[#work.metrics.transfer_witnesses + 1] = witness
        return witness
    end

    local function failed_transfer(machine, flow_id, code, first_illegal, witness, failure_detail, missing_port_machine)
        local detail = {flow_id = flow_id, machine_id = tostring(machine.id), machine_name = name_of(machine.entity),
            first_illegal_step = first_illegal}
        for key, value in pairs(failure_detail or {}) do detail[key] = value end
        if missing_port_machine then
            local missing_id = tostring(missing_port_machine.id)
            local missing_name = name_of(missing_port_machine.entity)
            detail.reason = "machine " .. missing_name .. " has no own port for flow " .. tostring(flow_id)
            detail.missing_port_machine_id = missing_id
            detail.missing_port_machine_name = missing_name
            detail.transport_reason = failure_detail and failure_detail.reason
        end
        if witness then detail.witness = witness end
        local ids = {tostring(machine.id), tostring(flow_id), tostring(first_illegal)}
        if missing_port_machine and tostring(missing_port_machine.id) ~= tostring(machine.id) then
            ids[#ids + 1] = tostring(missing_port_machine.id)
        end
        error_record(work.errors, code, ids, detail)
    end

    local function validate_inserter_endpoints(inserter)
        if endpoint_checked[inserter.id] then return endpoint_checked[inserter.id] end
        local pickup_x, pickup_y, drop_x, drop_y = transfer_cells(inserter, work)
        local valid = pickup_x ~= nil and drop_x ~= nil
        if not valid then
            error_record(work.errors, "BP_V_INSERTER_GEOMETRY", {tostring(inserter.id)},
                {reason = "captured inserter offsets are missing", found = "no endpoint cell"})
        else
            local pickup = transfer_endpoint_error(work, inserter, pickup_x, pickup_y, "pickup")
            local drop = transfer_endpoint_error(work, inserter, drop_x, drop_y, "drop")
            valid = legal_transfer_occupant(pickup) and legal_transfer_occupant(drop)
        end
        endpoint_checked[inserter.id] = valid
        return valid
    end

    -- A fluid connection is a pipe endpoint, never an item inserter.  Check this before looking for a missing
    -- pipe so a malformed transfer receives the actionable entity error.
    if not work._physical_initialized then
    for _, inserter in ipairs(work.inserters) do
        local flow_id = inserter.entity.flow_id or inserter.entity.full_name
        if flow_is_fluid(flow_id, inserter.entity, work) then
            error_record(work.errors, "BP_V_FLUID_INSERTER", {tostring(inserter.id)}, {flow_id = flow_id})
        end
    end
    for _, inserter in ipairs(work.inserters) do
        local flow_id = inserter.entity.flow_id or inserter.entity.full_name
        if not flow_is_fluid(flow_id, inserter.entity, work) then validate_inserter_endpoints(inserter) end
    end
    work._physical_initialized = true
    end

    --A machine may carry several hands for one flow (round 31: enough hands per flow). The first connected hand
    --witnesses the transfer; every further hand of that machine and flow that is connected by its own route is
    --a real transfer too, so it is used, not waste.
    local function extra_hands(machine, entry, flow_id, role)
        for _, other in ipairs(work.inserters) do
            local pickup_x, pickup_y, drop_x, drop_y = transfer_matches(work, other, machine, entry, role, used)
            if pickup_x then
                local cell_x, cell_y = role == "input" and pickup_x or drop_x, role == "input" and pickup_y or drop_y
                local port, path = connection_path(work, flow_id, role, cell_x, cell_y, "belt")
                if port then
                    validate_inserter_endpoints(other)
                    mark_path(path, flow_id)
                    mark_used(other, flow_id)
                end
            end
        end
    end

    local machine = machine_index and work.machines[machine_index]
    for _, machine in ipairs(machine and {machine} or {}) do
        local step = work.steps[machine.entity.step_id]
        if step then
            for _, entry in ipairs(plan_entries(step, "inputs")) do
                local flow_id = entry_flow_id(entry)
                if flow_is_fluid(flow_id, entry, work) then
                    local reached = false
                    for _, connection in ipairs(fluid_connection_cells(machine, entry, "input")) do
                        if pipe_to_ground_faces_away(work, connection) then goto continue_ptg_input end
                        local port, path, source_machine = connection_path(work, flow_id, "input", connection.x, connection.y, "pipe")
                        if port then
                            mark_path(path, flow_id)
                            add_witness(tostring(machine.id) .. ":input:" .. tostring(flow_id), "input",
                                source_machine and source_machine.id or port.port_id, machine.id,
                                {{id = port.port_id}}, path, {{id = machine.id, entity = machine}})
                            if source_machine then
                                local witness = work.metrics.connection_witnesses[#work.metrics.connection_witnesses]
                                table.insert(witness.ids, 1, tostring(source_machine.id))
                                table.insert(witness.steps, 1, witness_step(source_machine))
                            end
                            reached = true
                            break
                        end
                        ::continue_ptg_input::
                    end
                    if not reached then
                        failed_transfer(machine, flow_id, "BP_V_FLUID_DISCONNECTED", "fluid connection")
                    end
                else
                    local found = false
                    local candidate_seen, shape_seen, wrong_network, explicit_target, first_illegal, candidate_id = false, false, false, false, nil, nil
                    local missing_port_machine
                    for _, inserter in ipairs(work.inserters) do
                        local role = transfer_role(inserter, machine)
                        if role == "input" then
                            local actual = inserter.entity.flow_id or inserter.entity.full_name
                            if (multi_flow and declares_flow(inserter.entity, flow_id))
                                or (not multi_flow and (actual == nil or actual == flow_id)) then
                                candidate_seen = true
                                explicit_target = explicit_target or inserter.entity.pickup_target ~= nil or inserter.entity.drop_target ~= nil
                            end
                        end
                        if role == "input" then candidate_id = candidate_id or tostring(inserter.id) end
                        local pickup_x, pickup_y, drop_x, drop_y = transfer_matches(work, inserter, machine, entry, "input", used)
                        if pickup_x then
                            shape_seen = true
                            local port, path, source_machine, missing = connection_path(work, flow_id, "input", pickup_x, pickup_y, "belt")
                            missing_port_machine = missing_port_machine or missing
                            first_illegal = first_illegal or (source_machine and ("internal:" .. tostring(flow_id))
                                or (flow_side_has_external(work, flow_id, "producers")
                                    and external_failure_step(work, flow_id, "in", pickup_x, pickup_y, "belt")
                                    or ("internal:" .. tostring(flow_id))))
                            if port then
                                validate_inserter_endpoints(inserter)
                                mark_path(path, flow_id)
                                mark_used(inserter, flow_id)
                                work.metrics.transport_demand_by_entity_id[inserter.id] = flow_share(entry)
                                add_witness(tostring(machine.id) .. ":input:" .. tostring(flow_id), "input",
                                    source_machine and source_machine.id or port.port_id,
                                    machine.id, {{id = port.port_id}}, path,
                                    {{id = inserter.id, entity = inserter}, {id = machine.id, entity = machine}})
                                if source_machine then
                                    local witness = work.metrics.connection_witnesses[#work.metrics.connection_witnesses]
                                    table.insert(witness.ids, 1, tostring(source_machine.id))
                                    table.insert(witness.steps, 1, witness_step(source_machine))
                                end
                                found = true
                                extra_hands(machine, entry, flow_id, "input")
                                break
                            end
                            local opposite = external_port_for(work, flow_id, "out")
                            if opposite then
                                local ox, oy = port_position(work, opposite)
                                if transport_path(work, ox, oy, pickup_x, pickup_y, flow_id, "belt") then wrong_network = true end
                            end
                        end
                    end
                    if not found then
                        -- This hand was considered for a required input and has a
                        -- specific transfer failure below. Keep it out of the
                        -- duplicate orphan report; geometry, reachability and
                        -- target-shortfall validation remain fatal and unchanged.
                        if candidate_seen then
                            work._failed_obligation_hand = work._failed_obligation_hand or {}
                            for _, inserter in ipairs(work.inserters) do
                                if transfer_role(inserter, machine) == "input"
                                    and (inserter.entity.flow_id or inserter.entity.full_name) == flow_id then
                                    work._failed_obligation_hand[inserter.id] = true
                                end
                            end
                        end
                        local code, failure_detail = transfer_failure_ladder(candidate_seen, shape_seen, wrong_network, explicit_target)
                        failed_transfer(machine, flow_id, code, first_illegal or candidate_id or "input transfer", nil,
                            failure_detail, missing_port_machine)
                    end
                end
            end
            for _, entry in ipairs(plan_entries(step, "outputs")) do
                local flow_id = entry_flow_id(entry)
                if flow_is_fluid(flow_id, entry, work) then
                    local reached = false
                    for _, connection in ipairs(fluid_connection_cells(machine, entry, "output")) do
                        if pipe_to_ground_faces_away(work, connection) then goto continue_ptg_output end
                        local port, path, target_machine = connection_path(work, flow_id, "output", connection.x, connection.y, "pipe")
                        if port then
                            mark_path(path, flow_id)
                            add_witness(tostring(machine.id) .. ":output:" .. tostring(flow_id), "output", machine.id,
                                target_machine and target_machine.id or port.port_id,
                                {{id = machine.id, entity = machine}}, path, {{id = port.port_id}})
                            if target_machine then
                                local witness = work.metrics.connection_witnesses[#work.metrics.connection_witnesses]
                                witness.ids[#witness.ids + 1] = tostring(target_machine.id)
                                witness.steps[#witness.steps + 1] = witness_step(target_machine)
                            end
                            reached = true
                            break
                        end
                        ::continue_ptg_output::
                    end
                    if not reached then
                        failed_transfer(machine, flow_id, "BP_V_FLUID_DISCONNECTED", "fluid connection")
                    end
                else
                    local found = false
                    local candidate_seen, shape_seen, wrong_network, explicit_target, first_illegal, candidate_id = false, false, false, false, nil, nil
                    local missing_port_machine
                    for _, inserter in ipairs(work.inserters) do
                        local role = transfer_role(inserter, machine)
                        if role == "output" then
                            local actual = inserter.entity.flow_id or inserter.entity.full_name
                            if (multi_flow and declares_flow(inserter.entity, flow_id))
                                or (not multi_flow and (actual == nil or actual == flow_id)) then
                                candidate_seen = true
                                explicit_target = explicit_target or inserter.entity.pickup_target ~= nil or inserter.entity.drop_target ~= nil
                            end
                        end
                        if role == "output" then candidate_id = candidate_id or tostring(inserter.id) end
                        local pickup_x, pickup_y, drop_x, drop_y = transfer_matches(work, inserter, machine, entry, "output", used)
                        if pickup_x then
                            shape_seen = true
                            local port, path, target_machine, missing = connection_path(work, flow_id, "output", drop_x, drop_y, "belt")
                            missing_port_machine = missing_port_machine or missing
                            first_illegal = first_illegal or (target_machine and ("internal:" .. tostring(flow_id))
                                or (flow_side_has_external(work, flow_id, "consumers")
                                    and external_failure_step(work, flow_id, "out", drop_x, drop_y, "belt")
                                    or ("internal:" .. tostring(flow_id))))
                            if port then
                                validate_inserter_endpoints(inserter)
                                mark_path(path, flow_id)
                                mark_used(inserter, flow_id)
                                work.metrics.transport_demand_by_entity_id[inserter.id] = flow_share(entry)
                                add_witness(tostring(machine.id) .. ":output:" .. tostring(flow_id), "output", machine.id,
                                    target_machine and target_machine.id or port.port_id,
                                    {{id = machine.id, entity = machine}, {id = inserter.id, entity = inserter}},
                                    path, {{id = port.port_id}})
                                if target_machine then
                                    local witness = work.metrics.connection_witnesses[#work.metrics.connection_witnesses]
                                    witness.ids[#witness.ids + 1] = tostring(target_machine.id)
                                    witness.steps[#witness.steps + 1] = witness_step(target_machine)
                                end
                                found = true
                                extra_hands(machine, entry, flow_id, "output")
                                break
                            end
                            local opposite = external_port_for(work, flow_id, "in")
                            if opposite then
                                local ox, oy = port_position(work, opposite)
                                if transport_path(work, ox, oy, drop_x, drop_y, flow_id, "belt") then wrong_network = true end
                            end
                        end
                    end
                    if not found then
                        local code, failure_detail = transfer_failure_ladder(candidate_seen, shape_seen, wrong_network, explicit_target)
                        failed_transfer(machine, flow_id, code, first_illegal or candidate_id or "output transfer", nil,
                            failure_detail, missing_port_machine)
                    end
                end
            end
        end
    end

    --Waste is measured AGAINST obligations, so a candidate that carries none cannot be judged for it: every
    --entity is trivially unused when there is nothing to serve. tests/test_route_layout_contract.lua L1 and L4
    --are pure geometry -- an underground pair and a middle belt, no machine and no plan step -- and the rule
    --rejected all three of their belts as waste. A candidate whose plan has no steps is already refused by
    --plan completeness long before this, so nothing escapes through the guard.
    local has_obligations = false
    for _ in pairs(work.steps or {}) do has_obligations = true; break end
    if not has_obligations then return true end
    if not final then return true end

    local function published_cell(entity, field)
        local position = entity and entity[field]
        if type(position) ~= "table" then return nil end
        local x, y = finite(position.x), finite(position.y)
        if x == nil or y == nil then return nil end
        return math.floor(x + EPSILON), math.floor(y + EPSILON)
    end

    local function inserter_outward_cell(inserter)
        local entity = inserter.entity or {}
        local role = entity.role
        if role ~= "input" and role ~= "output" then
            local machine = entity.machine_id and work.info_by_id[entity.machine_id]
            role = machine and transfer_role(inserter, machine) or nil
            if not role then
                for _, candidate in ipairs(work.machines) do
                    role = transfer_role(inserter, candidate)
                    if role then break end
                end
            end
        end
        local pickup_x, pickup_y, drop_x, drop_y = transfer_cells(inserter, work)
        local x, y = role == "output" and drop_x or pickup_x, role == "output" and drop_y or pickup_y
        if x == nil or y == nil then
            x, y = published_cell(entity, role == "output" and "drop_position" or "pickup_position")
        end
        if x == nil or y == nil then x, y = transport_tile(inserter) end
        return x, y
    end

    local function unused_detail(info, inserter)
        local x, y
        if inserter then x, y = inserter_outward_cell(info) else x, y = transport_tile(info) end
        return {x = x, y = y, flow_id = flow_detail_id(info), facing = entity_direction(info) or Grid.NORTH}
    end

    for _, inserter in ipairs(work.inserters) do
        if not used_any(inserter) and not (work._failed_obligation_hand and work._failed_obligation_hand[inserter.id]) then
            local detail = unused_detail(inserter, true)
            detail.reason = "inserter serves no required transfer"
            error_record(work.errors, "BP_V_TRANSPORT_UNUSED", {tostring(inserter.id)}, detail)
        end
    end
    for _, info in ipairs(work.infos) do
        if transport_kind(info) and not used_any(info) then
            local detail = unused_detail(info, false)
            detail.reason = "transport entity serves no required transfer"
            error_record(work.errors, "BP_V_TRANSPORT_UNUSED", {tostring(info.id)}, detail)
        end
    end
    return true
end

local function check_port_approaches(work, port_index)
    local reported = work._approach_reported or {}; work._approach_reported = reported
    local function report(port, x, y, flow_id, source)
        local key = tostring(port.port_id) .. "\0" .. tile_key(x, y) .. "\0" .. tostring(flow_id)
        if reported[key] then return end
        reported[key] = true
        error_record(work.errors, "BP_V_PORT_EDGE_WRONG", {tostring(port.port_id), tostring(source.id or source.segment_id)},
            {reason = "port-owned tile carries another flow", port_id = port.port_id, x = x, y = y,
                port_flow_id = port.flow_id or port.full_name, occupant_flow_id = flow_id})
    end
    local function occupant_at(port, x, y, points_into_port)
        local wanted_flow = port.flow_id or port.full_name
        if wanted_flow == nil then return end
        local cache = tile_cache[work]
        if not cache then cache = build_tile_cache(work); tile_cache[work] = cache end
        for _, info in ipairs(cache.infos[tile_key(math.floor(x), math.floor(y))] or {}) do
            local kind = transport_kind(info)
            local fluid_port = port.kind == "fluid" or port.is_fluid == true or port.fluid_pinned == true
            if kind and ((fluid_port and kind == "pipe") or (not fluid_port and kind == "belt")) then
                local tx, ty = tile_of(info)
                local flow_id = info.entity.flow_id or info.entity.full_name
                local direction = entity_direction(info)  --takes the info, not its entity (was always nil: PA3)
                local follows_approach = fluid_port or not points_into_port or direction == nil
                    or direction == points_into_port
                if tx == math.floor(x) and ty == math.floor(y) and flow_id ~= nil and flow_id ~= wanted_flow
                    and follows_approach then
                    report(port, x, y, flow_id, info.entity)
                end
            end
        end
        for _, segment in ipairs(cache.segments[tile_key(math.floor(x), math.floor(y))] or {}) do
            local fluid_port = port.kind == "fluid" or port.is_fluid == true or port.fluid_pinned == true
            local segment_kind = segment.kind == "pipe" and "pipe" or "belt"
            local flow_ids = {}
            if segment.flow_id ~= nil then flow_ids[segment.flow_id] = true end
            for _, allocation in ipairs(segment.allocations or {}) do
                if allocation.flow_id ~= nil then flow_ids[allocation.flow_id] = true end
            end
            for flow_id, _ in pairs(flow_ids) do
                local segment_direction = segment.direction or segment.dir or segment.travel_dir
                local follows_approach = fluid_port or not points_into_port or segment_direction == nil
                    or segment_direction == points_into_port
                if flow_id ~= wanted_flow and follows_approach and ((fluid_port and segment_kind == "pipe")
                    or (not fluid_port and segment_kind == "belt")) then
                    local points = segment.cells or segment.tiles or segment.path or segment.positions
                    for _, point in ipairs(list_from(points)) do
                        local px, py
                        if type(point) == "table" then
                            px, py = finite(point.x), finite(point.y)
                            if px == nil or py == nil then px, py = finite(point[1]), finite(point[2]) end
                        end
                        if px ~= nil and py ~= nil and math.floor(px) == math.floor(x) and math.floor(py) == math.floor(y) then
                            report(port, x, y, flow_id, segment)
                        end
                    end
                end
            end
        end
    end
    local port = port_index and work.ports[port_index]
    for _, port in ipairs(port and {port} or {}) do
        local x, y = port_position(work, port)
        local direction = port_travel_direction(work, port)
        local dx, dy
        if direction then dx, dy = Grid.dir_vector(direction) end
        if x ~= nil and y ~= nil and dx ~= nil and dy ~= nil then
            occupant_at(port, x, y)
            if port.role == "in" then
                -- 2026-09-28 stack1: the (44,58) belt beside port (43,58) feeds nothing; only northbound flow enters.
                occupant_at(port, x - dx, y - dy, direction)
            elseif port.role == "out" then
                -- 2026-09-28 stack1: the (22,19) tile is ahead only if the belt on port (21,19) runs east.
                local approach_x, approach_y = dx, dy
                for _, info in ipairs(work.infos) do
                    if transport_kind(info) == "belt" then
                        local tx, ty = tile_of(info)
                        local flow_id = info.entity.flow_id or info.entity.full_name
                        local belt_dir = entity_direction(info)
                        if tx == math.floor(x) and ty == math.floor(y) and flow_id == (port.flow_id or port.full_name)
                            and belt_dir ~= nil then
                            approach_x, approach_y = Grid.dir_vector(belt_dir)
                            break
                        end
                    end
                end
                occupant_at(port, x + approach_x, y + approach_y)
            end
        end
    end
    return true
end

-- Pipes join every orthogonally adjacent ordinary pipe.  A pipe-to-ground only joins its declared pair;
-- its surface tile does not connect to nearby pipes.
local function check_fluid_mix(work)
    local pipes, underground = {}, {}
    for _, info in ipairs(work.infos or {}) do
        local entity = info.entity or {}
        local name = tostring(name_of(entity) or "")
        if transport_kind(info) == "pipe" then
            local is_underground = name == "pipe-to-ground" or entity.type == "pipe-to-ground" or entity.kind == "pipe-to-ground"
            if is_underground then underground[#underground + 1] = info else pipes[#pipes + 1] = info end
        end
    end
    for _, info in ipairs(underground) do
        local entity = info.entity or {}
        local pair_id = entity.ug_pair_id or entity.underground_pair_id or entity.pipe_connection
        local pair = pair_id and work.info_by_id[pair_id]
        local flow_id, pair_flow = transport_flow(info), transport_flow(pair)
        if pair and transport_kind(pair) == "pipe" and flow_id and pair_flow and flow_id ~= pair_flow
            and tostring(info.id) < tostring(pair.id) then
            error_record(work.errors, "BP_V_FLUID_MIX", {tostring(info.id), tostring(pair.id)},
                {flow_a = flow_id, flow_b = pair_flow})
        end
    end
    for i = 1, #pipes do
        local a = pipes[i]
        local ax, ay = transport_tile(a)
        for j = i + 1, #pipes do
            local b = pipes[j]
            local bx, by = transport_tile(b)
            local af, bf = transport_flow(a), transport_flow(b)
            if af and bf and af ~= bf and math.abs(ax - bx) + math.abs(ay - by) == 1 then
                error_record(work.errors, "BP_V_FLUID_MIX", {tostring(a.id), tostring(b.id)},
                    {flow_a = af, flow_b = bf})
            end
        end
    end
    return true
end

local function check_ports(work)
    local bound_source, bound_sink = {}, {}
    local edge_sources = {}
    for _, port in ipairs(work.ports) do
        if is_external_port(port) and (port.role or port.direction) == "in" then
            local flow_id = flow_id_of(port)
            if flow_id then
                local key = tostring(flow_id)
                edge_sources[key] = edge_sources[key] or {}
                edge_sources[key][#edge_sources[key] + 1] = port.port_id
            end
        end
    end
    for flow_id, ids in pairs(edge_sources) do
        if #ids > 1 then
            table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
            error_record(work.errors, "BP_V_SOURCE_DUPLICATE", {flow_id}, {flow_id = flow_id, port_ids = ids})
        end
    end
    for _, binding in ipairs(work.bindings) do
        local source_id, sink_id = binding.source_port_id or binding.source, binding.sink_port_id or binding.sink
        local source, sink = resolve_port(work.port_by_id, source_id, binding, "source"), resolve_port(work.port_by_id, sink_id, binding, "sink")
        local source_external = source and is_external_port(source)
        local sink_external = sink and is_external_port(sink)
        local source_ok = source and (source.role == "out" or (source.role == "in" and source_external))
        local sink_ok = sink and (sink.role == "in" or (sink.role == "out" and sink_external))
        local bad = not source or not sink or not source_ok or not sink_ok; local flow_id = binding.flow_id
        if not bad and flow_id then
            if not flow_compatible(source, flow_id) or not flow_compatible(sink, flow_id) then bad = true end
        end
        if bad then
            --Name the failing half. A bare code cannot be repaired: the reader needs to know whether the port is
            --missing from the candidate or present with the wrong role for this binding.
            local reason
            if not source then reason = "binding source port is missing"
            elseif not sink then reason = "binding sink port is missing"
            elseif not source_ok then reason = "binding source has role " .. tostring(source.role)
            elseif not sink_ok then reason = "binding sink has role " .. tostring(sink.role)
            else reason = "binding flow differs from its port flow" end
            error_record(work.errors, "BP_V_PORT_EDGE_WRONG", {tostring(source_id), tostring(sink_id)},
                {reason = reason})
        end
        if source_id then bound_source[source_id] = true end; if sink_id then bound_sink[sink_id] = true end
        if binding.rate_per_second and source_id then work.metrics.achieved_rate_by_port_id[source_id] = (work.metrics.achieved_rate_by_port_id[source_id] or 0) + flow_share(binding) end
        if binding.rate_per_second and sink_id then work.metrics.achieved_rate_by_port_id[sink_id] = (work.metrics.achieved_rate_by_port_id[sink_id] or 0) + flow_share(binding) end
        if binding.segment_id and not work.segment_by_id[binding.segment_id] then error_record(work.errors, "BP_V_PORT_EDGE_WRONG", {tostring(binding.segment_id)}, {reason = "segment is missing"}) end
    end
    for _, port in ipairs(work.ports) do
        local rate = finite(port.rate_per_second, finite(port.rate, 0)); local role = port.role or port.direction
        --Each port plays exactly one side. A block output and an edge input both feed transport, so both must be
        --a binding source; a block input and an edge output both receive, so both must be a binding sink.
        --Demanding both sides of one port made every edge input unreachable by definition: nothing inside the
        --layout produces into the factory's own supply.
        local external = is_external_port(port)
        local must_source = (role == "out" and not external) or (role == "in" and external)
        local must_sink = (role == "in" and not external) or (role == "out" and external)
        if role == "in" and port.row_port and port.port_id ~= "row:in:rear" then
            local rear_bound = false
            for _, binding in ipairs(work.bindings) do
                if binding.sink_port_id == "row:in:rear" then rear_bound = true; break end
            end
            if rear_bound then must_sink = false end
        end
        if rate > tolerance(rate) and ((must_source and not bound_source[port.port_id])
            or (must_sink and not bound_sink[port.port_id])) then
            error_record(work.errors, "BP_V_PORT_UNREACHABLE", {tostring(port.port_id)},
                {reason = (must_source and "no binding uses this port as a source")
                    or "no binding uses this port as a sink"})
        end
    end
    return true
end

local function check_machines(work)
    local count_by_step = {}
    for _, machine in ipairs(work.machines) do
        local step_id = machine.entity.step_id
        if step_id ~= nil then count_by_step[step_id] = (count_by_step[step_id] or 0) + 1 end
        local step = step_id ~= nil and work.steps[step_id] or nil
        if step then
            local expected_machine = prototype_name(step.machine or step.machine_name or step.entity)
            local actual_machine = machine.name
            local expected_quality = quality_of(step.machine_quality)
            if (expected_machine and actual_machine ~= expected_machine)
                or quality_of(machine.entity.quality) ~= expected_quality then
                error_record(work.errors, "BP_V_MACHINE_IDENTITY", {tostring(machine.id)},
                    {step_id = step_id, expected_machine = expected_machine, actual_machine = actual_machine,
                        expected_quality = expected_quality, actual_quality = quality_of(machine.entity.quality)})
            end

            --Recipe semantics are catalog facts.  A modded assembler is still an assembler, while a furnace
            --must never receive an assembler recipe merely because its prototype name happens to look similar.
            local etype = etype_of(machine)
            if etype == "assembling-machine" then
                if step.recipe ~= nil and machine.entity.recipe ~= step.recipe then
                    error_record(work.errors, "BP_V_MACHINE_IDENTITY", {tostring(machine.id)},
                        {reason = "recipe differs", expected = step.recipe, actual = machine.entity.recipe})
                end
                if step.recipe ~= nil and quality_of(machine.entity.recipe_quality) ~= quality_of(step.recipe_quality) then
                    error_record(work.errors, "BP_V_MACHINE_IDENTITY", {tostring(machine.id)},
                        {reason = "recipe quality differs", expected = quality_of(step.recipe_quality),
                            actual = quality_of(machine.entity.recipe_quality)})
                end
            elseif machine.entity.recipe ~= nil then
                error_record(work.errors, "BP_V_MACHINE_IDENTITY", {tostring(machine.id)},
                    {reason = "recipe is not supported by catalog etype", etype = etype})
            end
            if step.modules and not module_lists_equal(machine.entity.modules or {}, step.modules) then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(machine.id)}, {step_id = step_id}) end
            if machine.spec.module_slots ~= nil and #expand_modules(machine.entity.modules or {}) > machine.spec.module_slots then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(machine.id)}, {reason = "machine module slots exceeded"}) end
        end
    end
    for step_id, step in pairs(work.steps) do if step.machine_count ~= nil and count_by_step[step_id] ~= finite(step.machine_count, 0) then error_record(work.errors, "BP_V_MACHINE_COUNT_MISMATCH", {tostring(step_id)}, {expected = step.machine_count, placed = count_by_step[step_id] or 0}) end end
    for _, info in ipairs(work.beacons) do if info.spec.module_slots ~= nil and #beacon_modules(info) > info.spec.module_slots then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(info.id)}, {reason = "beacon module slots exceeded"}) end end
    for _, info in ipairs(work.inserters) do
        local rate = finite(info.entity.rate_per_second, finite(info.entity.flow_rate, 0)); local capacity = finite(info.entity.items_per_second, finite(info.spec.items_per_second, work.catalog.inserter and work.catalog.inserter.items_per_second))
        if rate > capacity + tolerance(capacity) then error_record(work.errors, "BP_V_INSERTER_CAPACITY", {tostring(info.id)}, {capacity = capacity, requested = rate}) end
        --Both sides must be OFFSETS from the entity centre. A published `pickup_position` is in world
        --coordinates, so it is converted here; comparing it directly against a rotated catalog offset
        --compared (1.5, 4.5) with (-1, 0) and rejected every correct inserter. The bug never fired only
        --because groups.lua published no position and the oracle's catalog carried no offset, so both sides
        --were nil. Publishing either one made the whole positive control fail with BP_V_INSERTER_GEOMETRY.
        local function as_offset(value)
            if type(value) ~= "table" then return nil end
            local x, y = finite(value.x), finite(value.y)
            if x == nil or y == nil then return nil end
            return {x = x, y = y}
        end
        local function centred(value)
            local offset = as_offset(value)
            if offset == nil then return nil end
            return {x = offset.x - finite(info.cx, 0), y = offset.y - finite(info.cy, 0)}
        end
        local pickup = centred(info.entity.pickup_position) or as_offset(info.entity.pickup_offset)
        local drop = centred(info.entity.drop_position) or as_offset(info.entity.drop_offset)
        local expected_pickup, expected_drop = info.spec.pickup_offset, info.spec.drop_offset or info.spec.drop_position
        local function rotated(offset)
            if not offset then return nil end
            local x, y = Grid.rotate_vector(offset.x, offset.y, info.entity.dir or info.entity.direction or Grid.NORTH)
            return {x = x, y = y}
        end
        expected_pickup, expected_drop = rotated(expected_pickup), rotated(expected_drop)
        if pickup and expected_pickup and (not near(pickup.x, expected_pickup.x) or not near(pickup.y, expected_pickup.y))
            or drop and expected_drop and (not near(drop.x, expected_drop.x) or not near(drop.y, expected_drop.y)) then
            error_record(work.errors, "BP_V_INSERTER_GEOMETRY", {tostring(info.id)})
        end
    end
    return true
end

coordinate_key = function(work)
    local parts = {}; for _, info in ipairs(work.infos) do parts[#parts + 1] = tostring(info.id) .. "@" .. tostring(info.cx) .. ":" .. tostring(info.cy) end
    table.sort(parts); return table.concat(parts, "|")
end

make_score = function(work)
    local min_x, min_y, max_x, max_y = INF, INF, -INF, -INF
    local beacon_count, pole_count, transport_entities, transport_cost = 0, 0, 0, 0
    local underground_seen = {}
    for _, info in ipairs(work.infos) do
        if not is_robo(info) then
            local rect = rect_of_entity(info.entity, info.spec)
            min_x, min_y = math.min(min_x, rect.x), math.min(min_y, rect.y)
            max_x, max_y = math.max(max_x, rect.x + rect.w), math.max(max_y, rect.y + rect.h)
        end
        if is_beacon(info) then beacon_count = beacon_count + 1 end
        if is_pole(info) then pole_count = pole_count + 1 end
        if transport_kind(info) then
            transport_entities = transport_entities + 1
            local pair_id = info.entity.ug_pair_id or info.entity.underground_pair_id
            local pair = pair_id and work.info_by_id[pair_id]
            if pair then
                local left, right = tostring(info.id), tostring(pair.id)
                if left > right then left, right = right, left end
                local pair_key = left .. "\0" .. right
                if not underground_seen[pair_key] then
                    underground_seen[pair_key] = true
                    transport_cost = transport_cost + math.max(1, math.abs(info.cx - pair.cx) + math.abs(info.cy - pair.cy))
                end
            else
                transport_cost = transport_cost + 1
            end
        end
    end
    if work.plan and #work.segments > 0 and not work.root.route then
        for _, segment in ipairs(work.segments) do
            if type(segment.length) ~= "number" then
                error_record(work.errors, "BP_V_METRIC_MISSING", {tostring(segment.segment_id or segment.id)},
                    {metric = "transport_cost", reason = "segment has no measured length"})
            end
        end
    end
    local production_area = max_x == -INF and 0 or (max_x - min_x) * (max_y - min_y)
    local cell_envelope_area
    if work.grid_w and work.grid_h then
        cell_envelope_area = math.max(0, work.grid_w * work.grid_h)
    elseif #work.roboports > 0 then
        local rmin_x, rmin_y, rmax_x, rmax_y = INF, INF, -INF, -INF
        for _, robo in ipairs(work.roboports) do
            local rect = rect_of_entity(robo.entity, robo.spec)
            rmin_x, rmin_y = math.min(rmin_x, rect.x), math.min(rmin_y, rect.y)
            rmax_x, rmax_y = math.max(rmax_x, rect.x + rect.w), math.max(rmax_y, rect.y + rect.h)
        end
        cell_envelope_area = (rmax_x - rmin_x) * (rmax_y - rmin_y)
    else
        cell_envelope_area = 0
    end
    local score = {beacon_count = beacon_count, production_area = production_area,
        cell_envelope_area = cell_envelope_area, transport_cost = transport_cost,
        transport_entities = transport_entities, pole_count = pole_count, coord_key = work.coordinate_key or coordinate_key(work)}
    for key, value in pairs(score) do work.metrics[key] = value end
    return score
end

local function finish(work, state)
    block_port_geometry(work.errors, work.root, work.placements)
    local score = work.initial_score or make_score(work)
    local result = {score = score, metrics = work.metrics}
    if #work.errors == 0 then state.ok = true; state.result = result; state.errors = nil
    else state.ok = false; state.errors = work.errors; state.result = result end
    state.done = true; state.cursor = {phase = "done"}; state.progress.phase = "done"; state.progress.done_units = state.progress.total_units
end

function Validate.begin(input)
    local work = make_work(input)
    return {done = false, ok = nil, cursor = {phase = "geometry", index = 1, other_index = 2}, progress = {phase = "validating", done_units = 0, total_units = math.max(1, #work.infos + #work.wires + #work.segments + #work.flows)}, result = nil, errors = nil, ops_used = 0, _work = work}
end

function Validate.step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    budget = type(budget) == "table" and budget or {ops = 1}; local ops = math.max(0, math.floor(finite(budget.ops, 1))); local work = state._work
    while ops > 0 and not state.done do
        local phase = state.cursor.phase
        local op_cost = 1
        if phase == "geometry" then
            -- Pair testing includes box conversion and mask intersection; account for that nested work.
            op_cost = 1 --a pair test is ~1-2 us (measured green, 2026-09-24)
            local index, other_index = state.cursor.index, state.cursor.other_index or 2
            if index <= #work.infos then
                if other_index == 2 then
                    local info = work.infos[index]
                    if info then
                        local world = work.geometry_world[index] or box_world(info)
                        if work.grid_w and (world.left < -EPSILON or world.right > work.grid_w + EPSILON or world.top < -EPSILON or world.bottom > work.grid_h + EPSILON) then
                            error_record(work.errors, "BP_V_OUT_OF_GRID", {tostring(info.id)}, {box = world, grid_w = work.grid_w, grid_h = work.grid_h})
                        end
                    end
                end
                if other_index <= #work.infos then
                    if other_index > index then check_geometry_pair(work, index, other_index) end
                    state.cursor.other_index = other_index + 1
                else
                    state.cursor.index, state.cursor.other_index = index + 1, 2
                end
            end
            if state.cursor.index > #work.infos then check_buffer_zones(work); state.cursor.phase, state.cursor.index = "robo", 1 end
        elseif phase == "robo" then check_robo(work); state.cursor.phase = "beacon"
        elseif phase == "beacon" then check_beacons(work); state.cursor.phase = "power_coverage"
        elseif phase == "power_coverage" then check_power_coverage(work); state.cursor.phase = "wire_legality"
        elseif phase == "wire_legality" then check_wire_legality(work); state.cursor.phase = "wire_connectivity"
        elseif phase == "wire_connectivity" then check_wire_connectivity(work); state.cursor.phase = "segments"
        --Each whole-list pass gets its own tick: two passes in one tick made 0.4-0.6 s ticks on the gray + magenta
        --sheet (legalcopilot-dev, 2026-09-28). Same checks, same order, same errors.
        elseif phase == "segments" then check_segments(work); state.cursor.phase = "fluid_mix"
        elseif phase == "fluid_mix" then check_fluid_mix(work); state.cursor.phase = "underground"
        elseif phase == "underground" then check_underground(work); state.cursor.phase = "shapes"
        elseif phase == "shapes" then check_transport_shapes(work); state.cursor.phase = "port_approaches"
        elseif phase == "port_approaches" then
            local index = state.cursor.approach_index or 1
            if index <= #work.ports then check_port_approaches(work, index); state.cursor.approach_index = index + 1
            else state.cursor.phase = "ports" end
        elseif phase == "ports" then check_ports(work); state.cursor.phase = "physical"
        elseif phase == "physical" then
            local index = state.cursor.physical_index or 1
            if index == 1 then check_physical_transfers(work, index, false)
            elseif index <= #work.machines then check_physical_transfers(work, index, false)
            else check_physical_transfers(work, nil, true); state.cursor.phase = "machines" end
            state.cursor.physical_index = index + 1
            op_cost = 500
        elseif phase == "machines" then check_machines(work); state.cursor.phase = "finish"
        elseif phase == "finish" then finish(work, state)
        end
        local spent = math.min(ops, op_cost)
        --One-shot passes (beacon, underground + transport shapes) take one game tick; per-item passes pay per item.
        if phase == "beacon" or phase == "segments" or phase == "fluid_mix" or phase == "underground" or phase == "shapes"
            or phase == "physical" then spent = math.min(ops, 2000) end
        if phase == "port_approaches" then spent = math.min(ops, 20) end
        ops = ops - spent; state.ops_used = state.ops_used + spent; state.progress.done_units = math.min(state.progress.total_units, state.progress.done_units + spent)
    end
    budget.ops = ops; return state
end

local function artifact_entities(artifact)
    if type(artifact) ~= "table" then return {} end
    local root = type(artifact.blueprint) == "table" and artifact.blueprint or artifact
    return list_from(root.entities)
end

local function artifact_modules(entity)
    if type(entity.modules) == "table" then return expand_modules(entity.modules), false end
    local result, has_slots = {}, false
    for _, item in ipairs(list_from(entity.items)) do
        local id = item.id
        local name, quality
        if type(id) == "table" then name, quality = id.name or id.id, quality_of(id.quality) else name = id end
        if name then
            local locations = item.items and item.items.in_inventory
            if type(locations) ~= "table" then locations = {{inventory = 1, stack = #result}} end
            for _, location in ipairs(locations) do
                local slot = finite(location.stack, #result)
                result[#result + 1] = {name = name, quality = quality_of(quality), slot = slot,
                    inventory = finite(location.inventory, 1)}
                has_slots = true
            end
        end
    end
    table.sort(result, function(a, b) return a.slot < b.slot end)
    local expanded = {}
    for _, module in ipairs(result) do expanded[#expanded + 1] = {name = module.name, quality = module.quality} end
    return expanded, has_slots, result
end

local function artifact_module_match(entity, expected)
    local actual, has_slots, placed = artifact_modules(entity)
    if not module_lists_equal(actual, expected or {}) then return false, "module multiset differs" end
    if #actual > 0 and not has_slots then return false, "module inventory placement is absent" end
    --The module inventory index differs per entity: a beacon's is 1, an assembling machine's is 4. Demanding 1
    --everywhere failed all seven machines of the player's sheet against an artifact that was correct.
    --
    --The validator cannot know the engine's `defines.inventory` values offline, so it checks the property it
    --CAN establish: every module of one entity sits in one inventory, and its slots run from 0 without a gap.
    --That rejects modules scattered across inventories or left at arbitrary slots, and never invents a
    --constant it has no way to verify.
    local inventory
    for index, module in ipairs(placed or {}) do
        if inventory == nil then inventory = module.inventory end
        if module.inventory ~= inventory then return false, "modules are split across inventories" end
        if module.slot ~= index - 1 then return false, "module inventory placement differs" end
    end
    return true
end

--The bound identity map, built from physical position.
--
--Pairing the i-th expected machine with the i-th placed machine is an ORDERING, never a binding, and contract
--25.5 forbids it. On the player's sheet it compared an electromagnetic-plant making copper-cable -- correct --
--against the foundry step, and reported six machine-identity failures that were not real.
--
--The serialized artifact carries no step identity: that is internal bookkeeping the game never sees. The
--candidate that produced it does carry it, and every artifact position is unique, so position is what binds
--the two. A machine standing at a position is the member that was placed there.
local function artifact_identity_map(internal)
    local by_position = {}
    for _, entity in ipairs(list_from(internal and (internal.entities or internal.placed_entities))) do
        local step_id = entity.step_id
        if step_id ~= nil then
            local position = entity.position
            local x = position and position.x or (entity.x ~= nil and entity.w ~= nil and entity.x + entity.w / 2)
            local y = position and position.y or (entity.y ~= nil and entity.h ~= nil and entity.y + entity.h / 2)
            if x and y then
                by_position[tostring(x) .. ":" .. tostring(y)] = {step_id = step_id, ordinal = entity.ordinal}
            end
        end
    end
    return by_position
end

local function artifact_expected_machines(plan)
    local result = {}
    for _, step in ipairs(list_from(plan and plan.steps)) do
        local count = math.max(0, math.floor(finite(step.machine_count or step.machines, 0)))
        for ordinal = 1, count do result[#result + 1] = {step = step, ordinal = ordinal} end
    end
    return result
end

local function artifact_expected_beacon_groups(plan)
    local result = {}
    for _, step in ipairs(list_from(plan and plan.steps)) do
        for _, group in ipairs(list_from(step.beacon_groups or step.beacons)) do
            result[#result + 1] = group
        end
    end
    return result
end

local function expected_direction(plan, entity)
    local source = plan and (plan.entity_directions or plan.directions or plan.direction_by_entity)
    if type(source) ~= "table" then return nil end
    local id = entity.id or entity.entity_id or entity.entity_number
    local value = source[id] or source[tostring(id)]
    if type(value) == "table" then value = value.direction or value.dir end
    return value
end

local function artifact_wire_tuple(edge)
    if type(edge) ~= "table" then return nil end
    if edge.a_id ~= nil or edge.b_id ~= nil then
        return {edge.a_id or edge.a, edge.a_connector or edge.a_connection or edge[2],
            edge.b_id or edge.b, edge.b_connector or edge.b_connection or edge[4]}
    end
    if type(edge[1]) == "table" and type(edge[2]) == "table" then
        return {edge[1][1] or edge[1].entity_id or edge[1].id, edge[1][2] or edge[1].connector,
            edge[2][1] or edge[2].entity_id or edge[2].id, edge[2][2] or edge[2].connector}
    end
    return {edge[1], edge[2], edge[3], edge[4]}
end

function Validate.reconcile_artifact(input)
    input = type(input) == "table" and input or {}
    local artifact = input.artifact
    local plan = input.plan
    local catalog = input.catalog or {}
    local errors = {}
    local function reject(code, ids, detail)
        local record = {code = code}
        if ids then record.ids = ids end
        if detail then record.detail = detail end
        errors[#errors + 1] = record
    end
    if type(artifact) ~= "table" or type(plan) ~= "table" then
        reject("BP_V_ARTIFACT_INCOMPLETE", nil, {reason = "artifact and plan are required"})
        return {ok = false, errors = errors}
    end

    local entities = artifact_entities(artifact)
    local expected_machines = artifact_expected_machines(plan)
    local actual_machines = {}
    local actual_beacons = {}
    local entity_numbers = {}
    for index, entity in ipairs(entities) do
        local number = entity.entity_number or index
        entity_numbers[number] = true
        local spec = catalog_entity(catalog, entity)
        local etype = spec and spec.etype or entity.etype or entity.type
        if etype == "beacon" then actual_beacons[#actual_beacons + 1] = {entity = entity, spec = spec} end
        --`type` is the internal kind marker on a candidate's own entities, and it falls back to that whenever
        --the catalog has no entry for the prototype. Reading only `kind` made a machine INVISIBLE to the
        --count check in any fixture whose catalog omits its etype, and the artifact then reported
        --'expected 1, actual 0' against a blueprint that held the machine all along. A real Factorio
        --blueprint never carries type = "machine"; there it is the input/output half of an underground belt.
        if etype == "assembling-machine" or etype == "furnace" or etype == "rocket-silo"
            or etype == "lab" or etype == "mining-drill"
            or entity.kind == "machine" or entity.type == "machine" then
            actual_machines[#actual_machines + 1] = {entity = entity, spec = spec}
        end
        local direction = entity.direction or entity.dir
        if direction ~= nil and (direction ~= 0 and direction ~= 4 and direction ~= 8 and direction ~= 12) then
            reject("BP_V_ARTIFACT_DIRECTION", {tostring(number)}, {direction = direction})
        end
        local wanted_direction = expected_direction(plan, entity)
        if wanted_direction ~= nil and direction ~= wanted_direction then
            reject("BP_V_ARTIFACT_DIRECTION", {tostring(number)},
                {expected = wanted_direction, actual = direction})
        end
    end
    table.sort(actual_machines, function(a, b) return (a.entity.entity_number or 0) < (b.entity.entity_number or 0) end)

    if #actual_machines ~= #expected_machines then
        reject("BP_V_ARTIFACT_MACHINE_COUNT", {"machines"}, {expected = #expected_machines, actual = #actual_machines})
    end
    --Expected steps, reachable by identity rather than by position in a list.
    local step_by_id = {}
    for _, expected in ipairs(expected_machines) do
        step_by_id[expected.step.step_id] = expected.step
    end
    local identity = artifact_identity_map(input.internal)

    local bound = {}
    for index, expected in ipairs(expected_machines) do
        local actual = actual_machines[index]
        local step = expected.step
        if actual then
            --Bind by position when the caller supplied the candidate that produced this artifact. Falling back
            --to the list position keeps the old behaviour for a caller that cannot supply one, and that
            --fallback is the reason the check must never be read as an identity proof on its own.
            local entity_position = actual.entity.position
            local key = entity_position and (tostring(entity_position.x) .. ":" .. tostring(entity_position.y))
            local bound_step = key and identity[key]
            if bound_step and step_by_id[bound_step.step_id] then
                step = step_by_id[bound_step.step_id]
            end
        end
        if actual then
            local entity, spec = actual.entity, actual.spec or {}
            local wanted_name = prototype_name(step.machine or step.machine_name or step.entity)
            local wanted_quality = quality_of(step.machine_quality)
            local actual_quality = quality_of(entity.quality)
            local mismatch = (wanted_name ~= nil and entity.name ~= wanted_name) or actual_quality ~= wanted_quality
            if mismatch then
                reject("BP_V_ARTIFACT_MACHINE_IDENTITY", {tostring(entity.entity_number or index)},
                    {expected_machine = wanted_name, actual_machine = entity.name,
                        expected_quality = wanted_quality, actual_quality = actual_quality})
            end
            local etype = spec.etype or entity.etype or entity.type
            if etype == "assembling-machine" then
                if step.recipe ~= nil and entity.recipe ~= step.recipe then
                    reject("BP_V_ARTIFACT_MACHINE_IDENTITY", {tostring(entity.entity_number or index)},
                        {reason = "recipe differs", expected = step.recipe, actual = entity.recipe})
                end
                if step.recipe ~= nil and quality_of(entity.recipe_quality) ~= quality_of(step.recipe_quality) then
                    reject("BP_V_ARTIFACT_MACHINE_IDENTITY", {tostring(entity.entity_number or index)},
                        {reason = "recipe quality differs", expected = quality_of(step.recipe_quality),
                            actual = quality_of(entity.recipe_quality)})
                end
            elseif entity.recipe ~= nil then
                reject("BP_V_ARTIFACT_MACHINE_IDENTITY", {tostring(entity.entity_number or index)},
                    {reason = "recipe is not supported by catalog etype", etype = etype})
            end
            local modules_ok, module_reason = artifact_module_match(entity, step.modules or {})
            if not modules_ok then reject("BP_V_ARTIFACT_MODULE_MISMATCH", {tostring(entity.entity_number or index)}, {reason = module_reason}) end
            bound[entity.entity_number or index] = {step_id = step.step_id, ordinal = expected.ordinal}
        end
    end

    local groups = artifact_expected_beacon_groups(plan)
    for _, actual in ipairs(actual_beacons) do
        local entity, spec = actual.entity, actual.spec or {}
        local matched = false
        for _, group in ipairs(groups) do
            local group_name = prototype_name(group.name or group.prototype or group.entity)
            local group_quality = quality_of(group.quality)
            if (group_name == nil or entity.name == group_name) and quality_of(entity.quality) == group_quality
                and module_lists_equal((artifact_modules(entity)), group.modules or {}) then
                matched = true
                break
            end
        end
        if #groups > 0 and not matched then
            reject("BP_V_ARTIFACT_BEACON_IDENTITY", {tostring(entity.entity_number)},
                {name = entity.name, quality = quality_of(entity.quality)})
        end
        if spec.module_slots ~= nil and #artifact_modules(entity) > spec.module_slots then
            reject("BP_V_ARTIFACT_MODULE_MISMATCH", {tostring(entity.entity_number)}, {reason = "beacon module slots exceeded"})
        end
    end

    local root = type(artifact.blueprint) == "table" and artifact.blueprint or artifact
    for _, raw in ipairs(list_from(root.wires)) do
        local wire = artifact_wire_tuple(raw)
        if not wire or not entity_numbers[wire[1]] or not entity_numbers[wire[3]] then
            reject("BP_V_ARTIFACT_WIRE_MISMATCH", {tostring(wire and wire[1]), tostring(wire and wire[3])},
                {reason = "wire endpoint is absent"})
        elseif wire[1] == wire[3] then
            reject("BP_V_ARTIFACT_WIRE_MISMATCH", {tostring(wire[1])}, {reason = "wire connects an entity to itself"})
        else
            local first, second
            for _, entity in ipairs(entities) do
                local number = entity.entity_number
                if number == wire[1] then first = entity end
                if number == wire[3] then second = entity end
            end
            local first_spec = first and catalog_entity(catalog, first) or {}
            local second_spec = second and catalog_entity(catalog, second) or {}
            local function power_entity(spec, entity)
                local etype = spec and spec.etype or entity and (entity.etype or entity.type)
                return etype == "electric-pole" or etype == "power-switch" or etype == "substation"
            end
            if not power_entity(first_spec, first) or not power_entity(second_spec, second) then
                reject("BP_V_ARTIFACT_WIRE_MISMATCH", {tostring(wire[1]), tostring(wire[3])},
                    {reason = "wire endpoint is not power infrastructure"})
            end
        end
    end
    if type(plan.wires) == "table" then
        local expected_wires, actual_wires = {}, {}
        for _, raw in ipairs(list_from(plan.wires)) do local wire = artifact_wire_tuple(raw); if wire then expected_wires[table.concat(wire, "\0")] = true end end
        for _, raw in ipairs(list_from(root.wires)) do local wire = artifact_wire_tuple(raw); if wire then actual_wires[table.concat(wire, "\0")] = true end end
        for key, _ in pairs(expected_wires) do if not actual_wires[key] then reject("BP_V_ARTIFACT_WIRE_MISMATCH", {key}, {reason = "declared wire is missing"}) end end
    end
    return {ok = #errors == 0, errors = #errors > 0 and errors or nil, identity = bound}
end

--The only place the user's priority is expressed: fewer physical beacons, then smaller footprint, then fewer
--poles, then deterministic tie-breakers.  The packer's fit score never decides which layout wins.
--Contract 25.4's comparator, amended 2026-09-22 on the player's instruction after they placed the round 18
--delivery. Two changes, both measured on legalcopilot-dev against their own factory:
--
--TRANSPORT BEFORE AREA. The old order ranked `production_area` before `transport_cost`, so the search
--shipped production_area 1100 / transport 301 / 297 entities over a candidate scoring 1200 / 258 / 254.
--It paid 43 extra transport entities to save 100 tiles squared of bounding box. The player's own factory is
--25x17 with 84 belts against our 21x49 with 274, so judging transport first is what chases their shape.
--
--THE ENVELOPE NOW RANKS, LAST. `cell_envelope_area` was "reported only, never optimized against", so
--nothing preferred a smaller roboport cell. Three candidates with identical scores existed at envelopes
--2916, 5616 and 8316 and the tiebreak fell to `coord_key`, which is arbitrary: we shipped cols=3 rows=2,
--6 roboports over TWO cells at 104x54, for a factory that fits 22x50. The player builds ONE cell -- 4
--roboports, cols=2 rows=2, 54x54. It ranks after every physical measure and before `coord_key`, so it can
--only break a tie, never buy a worse factory.
function Validate.compare(a_score, b_score)
    a_score, b_score = a_score or {}, b_score or {}
    for _, key in ipairs({"beacon_count", "transport_cost", "transport_entities", "production_area",
                          "pole_count", "cell_envelope_area"}) do
        local a, b = finite(a_score[key], 0), finite(b_score[key], 0); if a < b then return -1 end; if a > b then return 1 end
    end
    local a_key, b_key = tostring(a_score.coord_key or ""), tostring(b_score.coord_key or "")
    if a_key < b_key then return -1 end; if a_key > b_key then return 1 end; return 0
end

return Validate

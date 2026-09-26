--Machines and the beacons that serve them, arranged together before anything is placed on the map.
--
--Owned by lane W3-groups. Beacon count is the first thing the search minimises, so sharing has to be planned
--here: packing machines first and sprinkling beacons afterwards would miss the objective the user asked for.
--
--A block is a rectangle with its contents laid out relative to its own corner, its beacons already assigned, its
--inserters already placed, and its ports on the outside:
--  BlockPort = {port_id, role = "in"|"out", kind = "item"|"fluid", flow_id, step_id, rate_per_second,
--               attach_dx, attach_dy,   -- the tile OUTSIDE the envelope this port attaches to
--               normal_dir,             -- from that tile INTO the block
--               travel_dir,             -- transport travel: into the block for an input, out of it for an output
--               member_id}
--Adjacency is bounded on both axes, so a port cannot sit far off the edge while satisfying one equality:
--  (attach_dx == -1 or attach_dx == w) and 0 <= attach_dy < h, or the same with the axes swapped.
--
--A machine holding a quality module must never end up inside a speed beacon's influence. That is a hard
--placement rule here and a hard failure in the validator, not a score.
local Groups = {}

local Grid = require "logic.bp.grid"
local Geometry = require "logic.bp.geometry"
local Flags = require "logic.bp.flags"
local Buffer = require "logic.bp.buffer"

local NORTH, EAST, SOUTH, WEST = Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function name_of(value)
    if type(value) == "string" then return value end
    if type(value) == "table" then return value.name or value.prototype or value.id end
    return nil
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        -- The grouping boundary is deliberately data-only.  This also keeps a malformed fixture from
        -- smuggling a prototype object or a function into a job that may be saved in storage.
        if type(key) ~= "function" and type(child) ~= "function" and type(child) ~= "userdata" then
            result[copy(key, seen)] = copy(child, seen)
        end
    end
    return result
end

local function sorted(list, less)
    table.sort(list, less or function(a, b) return tostring(a) < tostring(b) end)
    return list
end

local function list_copy(list)
    local result = {}
    for index, value in ipairs(list or {}) do result[index] = copy(value) end
    return result
end

local function first_number(values, fallback)
    -- Several callers intentionally put optional fields before a catalog fallback.  ipairs stops at the first
    -- nil, which would silently discard the catalog value; scan the small fixed-size precedence lists directly.
    for index = 1, math.max(#values, 10) do
        local value = values[index]
        local number = finite(value)
        if number ~= nil then return number end
    end
    return fallback
end

local function lookup_entity(catalog, name, kind)
    if not name then return {} end
    local entity = catalog and catalog.entity and catalog.entity[name]
    if entity then return entity end
    if kind and catalog and catalog[kind] and catalog[kind][name] then return catalog[kind][name] end
    return {}
end

local function catalog_name(catalog, fallback)
    local facts = catalog and catalog.entity and catalog.entity[fallback]
    return facts and facts.name or fallback
end

local function flow_id_of(flow)
    return flow and (flow.flow_id or flow.full_name or flow.id)
end

local function flow_is_fluid(entry, flows)
    if type(entry) ~= "table" then return false end
    if entry.kind == "fluid" or entry.is_fluid == true then return true end
    local flow_id = entry.flow_id or entry.full_name or entry.id
    if type(flow_id) == "string" and flow_id:sub(1, 6) == "fluid/" then return true end
    if type(flows) == "table" and #flows == 0 then
        local flow = flows[flow_id]
        if flow and (flow.kind == "fluid" or flow.is_fluid == true) then return true end
    end
    for _, flow in ipairs(flows or {}) do
        if flow_id_of(flow) == flow_id and (flow.kind == "fluid" or flow.is_fluid == true) then return true end
    end
    return false
end

local function fluid_connection(catalog, step, entry, role)
    if not flow_is_fluid(entry) then return nil end
    local explicit = entry.connection or entry.pipe_connection or entry.fluid_connection
    if explicit then return {connection = copy(explicit), box_index = entry.fluidbox_index or entry.box_index,
        connection_index = entry.connection_index or entry.pipe_connection_index} end

    local entity = lookup_entity(catalog, step.machine, "machine")
    local boxes = entity.fluid_boxes or entity.fluidbox_prototypes
    if type(boxes) ~= "table" then return nil end
    local wanted_box = entry.fluidbox_index or entry.box_index
    local wanted_connection = entry.connection_index or entry.pipe_connection_index
    local preferred = role == "input" and "input" or "output"
    if wanted_box == nil then
        local recipe = catalog and catalog.recipe and catalog.recipe[step.recipe or step.recipe_name or ""]
        local list = recipe and (role == "input" and recipe.ingredients or (recipe.results or recipe.products)) or {}
        local ordinal, fluid_count = nil, 0
        for _, item in ipairs(list) do
            if item.type == "fluid" then
                fluid_count = fluid_count + 1
                if ("fluid/" .. tostring(item.name)) == (entry.flow_id or entry.full_name or entry.id)
                    or item.name == entry.name then ordinal = fluid_count end
            end
        end
        if fluid_count >= 2 and ordinal then
            local role_index = 0
            for box_index, box in ipairs(boxes) do
                local production = tostring(box.production_type or box.flow_direction or ""):lower()
                if production == preferred then
                    role_index = role_index + 1
                    if role_index == ordinal then wanted_box = box.index or box_index; break end
                end
            end
        end
    end
    local fallback
    local first, last, increment = 1, #boxes, 1
    if role ~= "input" then first, last, increment = #boxes, 1, -1 end
    for box_index = first, last, increment do
        local box = boxes[box_index]
        if wanted_box == nil or wanted_box == box.index or wanted_box == box_index then
            local production = tostring(box.production_type or box.flow_direction or ""):lower()
            local matches_role = production == preferred or production:find(preferred, 1, true) ~= nil
            local connections = box.connections or box.pipe_connections or {}
            for connection_index, connection in ipairs(connections) do
                if wanted_connection == nil or wanted_connection == connection_index then
                    local selected = {connection = connection, box_index = box.index or box_index,
                        connection_index = connection_index, matches_role = matches_role}
                    if matches_role then return copy(selected) end
                    fallback = fallback or selected
                end
            end
        end
    end
    return fallback and copy(fallback) or nil
end

local function dimensions(catalog, name, kind, fallback_w, fallback_h)
    local entity = lookup_entity(catalog, name, kind)
    local size = entity.size or entity.footprint
    local w = first_number({entity.tile_w, entity.tile_width, entity.w, size and size.w}, fallback_w)
    local h = first_number({entity.tile_h, entity.tile_height, entity.h, size and size.h}, fallback_h)
    return math.max(1, math.floor(w or fallback_w)), math.max(1, math.floor(h or fallback_h))
end

local function group_modules(group)
    local modules = group and (group.modules or group.module_set or {}) or {}
    local result = {}
    for index, module in ipairs(modules) do
        local name = name_of(module)
        if name then
            result[#result + 1] = {
                name = name,
                quality = type(module) == "table" and (module.quality or "normal") or "normal",
                count = math.max(1, math.floor(finite(type(module) == "table" and module.count, 1))),
            }
        end
    end
    return result
end

local function module_is_speed(module)
    local name = tostring(module.name or ""):lower()
    if name:find("speed", 1, true) then return true end
    local effects = module.effects
    return type(effects) == "table" and finite(effects.speed, 0) > 0
end

local function beacon_is_speed(group)
    if group.has_speed_module ~= nil then return group.has_speed_module == true end
    if group.speed == true or group.speed_module == true then return true end
    local signature = tostring(group.signature or ""):lower()
    if signature:find("speed", 1, true) then return true end
    for _, module in ipairs(group_modules(group)) do
        if module_is_speed(module) then return true end
    end
    local name = tostring(group.name or group.beacon or group.type or ""):lower()
    return name:find("speed", 1, true) ~= nil
end

local function group_name(group, catalog)
    return name_of(group.name or group.beacon or group.type or group.prototype) or catalog_name(catalog, "beacon")
end

local function group_signature(group, catalog)
    if group.signature ~= nil then return tostring(group.signature) end
    local pieces = {group_name(group, catalog), tostring(group.quality or "normal")}
    for _, module in ipairs(group_modules(group)) do
        pieces[#pieces + 1] = tostring(module.name) .. "@" .. tostring(module.quality) .. "x" .. tostring(module.count)
    end
    -- A catalog may distinguish two beacon profiles with the same prototype name.  The explicit signature
    -- remains authoritative, while this fallback is stable for the normal catalog shape.
    local entity = lookup_entity(catalog, group_name(group, catalog), "beacon")
    if entity.beacon and entity.beacon.counter then pieces[#pieces + 1] = tostring(entity.beacon.counter) end
    return table.concat(pieces, "|")
end

local function group_supply(catalog, group)
    local entity = lookup_entity(catalog, group_name(group, catalog), "beacon")
    local beacon = entity.beacon or (catalog and catalog.beacon and catalog.beacon[group_name(group, catalog)]) or {}
    local supply = group.supply_area_distance or group.supply_distance or group.supply_w
    local supply_h = group.supply_area_distance_h or group.supply_h
    return first_number({supply, beacon.supply_w, beacon.supply_area_distance, beacon.radius, 3}, 3),
        first_number({supply_h, beacon.supply_h, beacon.supply_area_distance_h, beacon.radius, 3}, 3)
end

local function modules_have_quality(modules)
    for _, module in ipairs(modules or {}) do
        local name = tostring(module.name or ""):lower()
        if name:find("quality", 1, true) then return true end
        if type(module.effects) == "table" and finite(module.effects.quality, 0) > 0 then return true end
    end
    return false
end

local function normalize_step(step, catalog)
    local result = copy(step or {})
    result.step_id = tostring(step.step_id or step.id or step.recipe or "step")
    result.machine = name_of(step.machine or step.machine_name or step.entity) or catalog_name(catalog, "assembling-machine-1")
    result.machine_quality = step.machine_quality or "normal"
    result.machine_count = math.max(0, math.floor(finite(step.machine_count or step.machines, 0)))
    result.modules = list_copy(step.modules)
    result.beacon_groups = list_copy(step.beacon_groups or step.beacons)
    result.forbids_speed_beacon = step.forbids_speed_beacon == true
        or step.has_quality_module == true or modules_have_quality(result.modules)
    result.inputs = list_copy(step.inputs)
    result.outputs = list_copy(step.outputs)
    result.interface_signature = step.interface_signature
    result._groups = {}
    for _, group in ipairs(result.beacon_groups) do
        local normalized = {
            signature = group_signature(group, catalog),
            name = group_name(group, catalog),
            quality = group.quality or "normal",
            count_per_machine = math.max(0, math.ceil(finite(group.count_per_machine or group.count, 0))),
            has_speed_module = beacon_is_speed(group),
            modules = group_modules(group),
        }
        normalized.supply_w, normalized.supply_h = group_supply(catalog, group)
        result._groups[#result._groups + 1] = normalized
    end
    table.sort(result._groups, function(a, b)
        if a.signature == b.signature then return a.name < b.name end
        return a.signature < b.signature
    end)
    return result
end

local function normalize_plan(input)
    input = input or {}
    local plan = input.plan or input.result or input
    local catalog = input.catalog or plan.catalog or {}
    local steps = {}
    for _, step in ipairs(plan.steps or input.steps or {}) do
        local normalized = normalize_step(step, catalog)
        if normalized.machine_count > 0 then steps[#steps + 1] = normalized end
    end
    table.sort(steps, function(a, b) return a.step_id < b.step_id end)
    return plan, catalog, steps, plan.flows or input.flows or {}, plan.ports or input.ports or {}
end

local function step_can_join(a, b)
    -- A physical step fragment was introduced because one shared block could not expose all of its item hands
    -- on the perimeter. Keep each fragment a block of its own; joining it back to a neighbouring machine would
    -- reintroduce the interior face the partition is meant to escape.
    if a._force_block == true or b._force_block == true then return false end
    -- A physical block has one recipe and one machine setup.  Buffer sharing is permitted only
    -- between machines of that exact pair, so distinct steps cannot share a block across either.
    if a.recipe ~= b.recipe or a.machine ~= b.machine then return false end
    -- Older plan fixtures may omit recipe; without a recipe identity those distinct steps cannot safely share.
    if a.recipe == nil and a.step_id ~= b.step_id then return false end
    if a.forbids_speed_beacon ~= b.forbids_speed_beacon then return false end
    if a.interface_signature ~= nil and b.interface_signature ~= nil
        and tostring(a.interface_signature) ~= tostring(b.interface_signature) then
        return false
    end
    -- A shared strip only has one setup.  Equal signatures are the useful case: a different beacon setup is
    -- still a legal separate block, but joining it here would hide the first search objective.
    local a_signatures, b_signatures = {}, {}
    for _, group in ipairs(a._groups) do a_signatures[group.signature] = true end
    for _, group in ipairs(b._groups) do b_signatures[group.signature] = true end
    local keys = {}
    for key, _ in pairs(a_signatures) do keys[key] = true end
    for key, _ in pairs(b_signatures) do keys[key] = true end
    for key, _ in pairs(keys) do
        if a_signatures[key] ~= b_signatures[key] then return false end
    end
    return true
end

local function item_port_count(step, role, flows)
    local n = 0
    for _, p in ipairs(step[role] or {}) do if not flow_is_fluid(p, flows) then n = n + 1 end end
    return n
end

local function member_id(kind, step_id, number, role)
    local suffix = role and (":" .. role) or ""
    return kind .. ":" .. step_id .. ":" .. tostring(number) .. suffix
end

local function machine_size(step, catalog)
    return dimensions(catalog, step.machine, "machine", step.machine_w or 3, step.machine_h or 3)
end

local function inserter_size(catalog, input)
    local name = input and input.name
    if not name and catalog and catalog.inserter then name = catalog.inserter.name end
    name = name or catalog_name(catalog, "inserter")
    return name, dimensions(catalog, name, "inserter", 1, 1)
end

local function point(value)
    if type(value) ~= "table" then return nil end
    local x, y = finite(value.x), finite(value.y)
    if x == nil or y == nil then x, y = finite(value[1]), finite(value[2]) end
    if x == nil or y == nil then return nil end
    return {x = x, y = y}
end

local function inserter_offsets(catalog, name)
    local facts = catalog and catalog.inserter
    local entity_facts = lookup_entity(catalog, name, "inserter")
    if not facts or (not facts.pickup_offset and entity_facts.pickup_offset) then facts = entity_facts end
    facts = facts or {}
    -- The normal catalog always supplies these facts.  The fallback keeps the small, older grouping fixtures
    -- meaningful while still making every real placement below go through the captured geometry when present.
    return point(facts.pickup_offset) or {x = 0, y = 1},
        point(facts.drop_offset or facts.drop_position) or {x = 0, y = -1}
end

local function rotated_point(cx, cy, offset, direction)
    local dx, dy = Grid.rotate_vector(offset.x, offset.y, direction)
    return {x = cx + dx, y = cy + dy}
end

local function cell_of(value)
    return math.floor(value + Geometry.EPSILON)
end

local function transfer_cells(x, y, w, h, direction, pickup_offset, drop_offset)
    local cx, cy = x + w / 2, y + h / 2
    local pickup = rotated_point(cx, cy, pickup_offset, direction)
    local drop = rotated_point(cx, cy, drop_offset, direction)
    return pickup, drop, cell_of(pickup.x), cell_of(pickup.y), cell_of(drop.x), cell_of(drop.y)
end

local function cell_in_rect(rect, x, y)
    return rect ~= nil and x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

local function rectangles_overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function member_for(block, reference)
    if reference == nil then return nil end
    local wanted = tostring(reference)
    for _, member in ipairs(block.machines or {}) do
        if tostring(member.id) == wanted or "m:" .. tostring(member.id) == wanted then return member end
    end
    return nil
end

local function member_for_step(block, step_id, avoid)
    if step_id == nil or step_id == "$external" then return nil end
    for _, member in ipairs(block.machines or {}) do
        if tostring(member.step_id) == tostring(step_id) and member ~= avoid then return member end
    end
    return nil
end

local function flow_record(flows, flow_id)
    for _, flow in ipairs(flows or {}) do
        if (flow.flow_id or flow.full_name or flow.id) == flow_id then return flow end
    end
    return nil
end

local function counterpart_member(block, machine, role, flow_id, flows)
    local flow = flow_record(flows, flow_id)
    local entries = flow and (role == "input" and flow.producers or flow.consumers) or {}
    for _, entry in ipairs(entries or {}) do
        local member = member_for_step(block, entry.step_id, machine)
        if member then return member end
    end
    return nil
end

local function port_bound_for(block, machine, role, port, flows)
    local source_reference = role == "input"
        and (port.source_machine_id or port.source_id or port.source_member_id or port.source)
        or (port.drain_machine_id or port.drain_id or port.drain_member_id or port.drain)
    local source_member = member_for(block, source_reference)
    source_member = source_member or counterpart_member(block, machine, role,
        port.flow_id or port.full_name, flows)
    local target_member = role == "input" and machine or member_for(block, source_reference)
    if role == "output" then
        target_member = target_member or counterpart_member(block, machine, role,
            port.flow_id or port.full_name, flows)
    end
    return (role == "input" and source_member == nil) or (role == "output" and target_member == nil),
        source_member, target_member
end

local function explicit_cell(entry, keys)
    for _, key in ipairs(keys) do
        local value = point(entry and entry[key])
        if value then return cell_of(value.x), cell_of(value.y) end
    end
    return nil, nil
end

local function candidate_inserter(block, machine, role, index, iw, ih, catalog, input, source_member, target_member,
    source_cell, target_cell, port_bound, face_column, face)
    local name = input and input.name
    local pickup_offset, drop_offset = inserter_offsets(catalog, name)
    local preferred = role == "input" and EAST or SOUTH
    local desired_x, desired_y
    if port_bound and face ~= nil then
        -- A port-bound hand is deliberately placed on the machine face owned by its flow.  The direction is
        -- role-dependent because an input picks up outside and drops into the machine, while an output picks up
        -- inside and drops outside.  The one-tile margin in each branch is also the block perimeter ring.
        if face == "top" then
            desired_x, desired_y = machine.x + (math.max(1, face_column or 1) - 1) * iw, machine.y - ih
            preferred = role == "input" and SOUTH or NORTH
        elseif face == "bottom" then
            desired_x, desired_y = machine.x + (math.max(1, face_column or 1) - 1) * iw, machine.y + machine.h
            preferred = role == "input" and NORTH or SOUTH
        elseif face == "left" then
            desired_x, desired_y = machine.x - iw, machine.y + (math.max(1, face_column or 1) - 1) * ih
            preferred = role == "input" and EAST or WEST
        else
            desired_x, desired_y = machine.x + machine.w, machine.y + (math.max(1, face_column or 1) - 1) * ih
            preferred = role == "input" and WEST or EAST
        end
    elseif port_bound then
        -- The named mutation used by the lane's red proof disables face-per-flow layout. Keep the old shared
        -- bottom-face geometry as a valid, deterministic mutant rather than making the proof a syntax check.
        desired_x = machine.x + (math.max(1, face_column or 1) - 1) * iw
        desired_y = machine.y + machine.h
        preferred = role == "input" and NORTH or SOUTH
    elseif role == "input" then
        desired_x, desired_y = machine.x + (-iw), machine.y + index - 1
    else
        desired_x, desired_y = machine.x + math.max(0, math.min(machine.w - iw, index - 1)), machine.y + machine.h
    end
    --Inserters are appended to block.inserters, never to block.members, so a members-only occupancy test
    --cannot see an inserter this same call placed a moment ago. Measured on the player's sheet: the two input
    --inserters of assembling-machine-2 both scored the same best cell and the candidate rejected with
    --BP_V_COLLISION naming `:input:3` against `:input:4`.
    local occupied = {}
    for _, member in ipairs(block.members or {}) do occupied[#occupied + 1] = member end
    for _, placed in ipairs(block.inserters or {}) do occupied[#occupied + 1] = placed end
    local best, best_score
    -- Offsets are prototype facts, not necessarily one tile.  The bounded search covers the ordinary inserter
    -- envelope plus modded long-reach prototypes without ever trying a different inserter family.
    local radius = 8
    local directions = {EAST, SOUTH, WEST, NORTH}
    for direction_index, direction in ipairs(directions) do
        for y = machine.y - radius, machine.y + machine.h + radius do
            for x = machine.x - radius, machine.x + machine.w + radius do
                local rect = {x = x, y = y, w = iw, h = ih}
                if not rectangles_overlap(rect, machine) then
                    local _, _, pickup_x, pickup_y, drop_x, drop_y =
                        transfer_cells(x, y, iw, ih, direction, pickup_offset, drop_offset)
                    local target_x, target_y = drop_x, drop_y
                    local source_x, source_y = pickup_x, pickup_y
                    local target_ok = target_member and cell_in_rect(target_member, target_x, target_y)
                        or (target_cell and target_x == target_cell[1] and target_y == target_cell[2])
                    local source_ok = source_member and cell_in_rect(source_member, source_x, source_y)
                        or (source_cell and source_x == source_cell[1] and source_y == source_cell[2])
                    if not source_member and not source_cell then
                        source_ok = role == "input" and not cell_in_rect(machine, source_x, source_y)
                            or cell_in_rect(machine, source_x, source_y)
                    end
                    if not target_member and not target_cell then
                        target_ok = role == "input" and cell_in_rect(machine, target_x, target_y)
                            or not cell_in_rect(machine, target_x, target_y)
                    end
                    local face_ok = true
                    if port_bound and face ~= nil then
                        local port_x, port_y = role == "input" and source_x or target_x,
                            role == "input" and source_y or target_y
                        local endpoint_clear = true
                        for _, member in ipairs(block.members or {}) do
                            if cell_in_rect(member, port_x, port_y) then endpoint_clear = false; break end
                        end
                        if endpoint_clear then
                            for _, member in ipairs(block.machines or {}) do
                                local spec = lookup_entity(catalog, member.name, "machine")
                                local box = Geometry.world_box(member, spec)
                                if port_x + 1 > box.left and port_x < box.right
                                    and port_y + 1 > box.top and port_y < box.bottom then
                                    endpoint_clear = false
                                    break
                                end
                            end
                        end
                        if endpoint_clear then
                            for _, placed in ipairs(block.inserters or {}) do
                                if cell_in_rect(placed, port_x, port_y) then endpoint_clear = false; break end
                            end
                        end
                        face_ok = endpoint_clear
                        if face == "top" then
                            face_ok = face_ok and port_y < machine.y and port_x >= machine.x and port_x < machine.x + machine.w
                        elseif face == "bottom" then
                            face_ok = face_ok and port_y >= machine.y + machine.h and port_x >= machine.x and port_x < machine.x + machine.w
                        elseif face == "left" then
                            face_ok = face_ok and port_x < machine.x and port_y >= machine.y and port_y < machine.y + machine.h
                        else
                            face_ok = face_ok and port_x >= machine.x + machine.w and port_y >= machine.y and port_y < machine.y + machine.h
                        end
                    end
                    if target_ok and source_ok and face_ok then
                        local blocked = false
                        for _, other in ipairs(occupied) do
                            if other ~= machine and rectangles_overlap(rect, other) then blocked = true; break end
                        end
                        if not blocked then
                            local score = math.abs(x - desired_x) + math.abs(y - desired_y)
                                + (direction == preferred and 0 or 100)
                                + direction_index / 1000
                            if best_score == nil or score < best_score then
                                local pickup_position, drop_position =
                                    transfer_cells(x, y, iw, ih, direction, pickup_offset, drop_offset)
                                best_score = score
                                best = {x = x, y = y, w = iw, h = ih, dir = direction,
                                    pickup_position = pickup_position, drop_position = drop_position}
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function covers(beacon, machine, machine_spec, supply_w, supply_h)
    -- Supply is measured from the beacon centre, but the supplied entity is its collision box.  Keeping the
    -- conversion in Geometry is important: a tile footprint is a deliberate fallback, not a second predicate.
    local beacon_x, beacon_y = Geometry.center(beacon)
    --Engine: a beacon's supply_area_distance counts from its EDGE (vanilla 3x3, distance 3 -> 9x9), unlike a pole's.
    return Geometry.box_in_supply(machine, machine_spec, beacon_x, beacon_y,
        (supply_w or 0) + (beacon.w or 3) / 2, (supply_h or supply_w or 0) + (beacon.h or beacon.w or 3) / 2)
end

--Contract 28.1 and 28.3: one hand may serve two item flows that ride one belt, using both belt lanes, which
--is how the player's own factory gets 22 inserters where ours plans 26.  The switch is OFF here and stays off
--for every lane: three lanes build three halves of one feature behind it -- groups pairs the hands, route shares the belt, validate witnesses per flow -- and integration
--flips all three together, because that is the only point where the halves meet.  Golden tests therefore keep
--passing at default configuration while the halves are being built.
local function forced_multi_flow_hands(input)
    --A characterization test may exercise the dormant half without changing the production default.  This
    --local capability is intentionally named the same way as the switch: lane_mutate can turn it off and the
    --test then proves that the paired-hand assertions really depend on the implementation.
    local multi_flow_hands = true
    if input and input._force_multi_flow_hands then return multi_flow_hands end
    return false
end

local multi_flow_hands = Flags.multi_flow_hands
--Rows are the single physical form for eligible machine groups (docs/contracts/row_block.md).

local function flow_entry_rate(entry)
    return math.max(0, finite(entry and entry.share_per_second,
        finite(entry and entry.rate_per_second, finite(entry and entry.rate, 0))))
end

local function flow_entry_id(entry)
    return entry and (entry.flow_id or entry.full_name or entry.id)
end

local function arrival_cell(entry)
    -- The planner may carry either a decoded blueprint cell or the continuous position from which that cell
    -- was recovered.  Pairing without an authored arrival cell would turn "same belt tile" into a guess, so
    -- an otherwise compatible pair is deliberately left as two hands when neither entry carries one.
    for _, key in ipairs({"pickup_cell", "source_cell", "belt_cell", "arrival_cell", "belt_tile",
        "pickup_position", "source_position", "belt_position", "arrival_position"}) do
        local position = point(entry and entry[key])
        if position then return cell_of(position.x), cell_of(position.y) end
    end
    return nil, nil
end

local function same_cell(first, second)
    local first_x, first_y = arrival_cell(first)
    local second_x, second_y = arrival_cell(second)
    return first_x ~= nil and first_x == second_x and first_y == second_y
end

local function hand_key(role, ports)
    local ids = {}
    for _, port in ipairs(ports) do ids[#ids + 1] = tostring(flow_entry_id(port)) end
    table.sort(ids)
    return tostring(role) .. ":" .. table.concat(ids, "+")
end

local function hand_group(role, ports, machine_count)
    local ids, shares, total = {}, {}, 0
    for _, port in ipairs(ports) do
        local id = flow_entry_id(port)
        if id ~= nil then
            local share = flow_entry_rate(port)
            ids[#ids + 1] = id
            shares[id] = share
            total = total + share
        end
    end
    table.sort(ids)
    local count = math.max(1, machine_count or 1)
    local per_machine = {}
    for _, id in ipairs(ids) do per_machine[id] = shares[id] / count end
    return {
        key = hand_key(role, ports), role = role, ports = ports, port = ports[1],
        flow_ids = ids, flow_shares = shares, flow_shares_per_machine = per_machine,
        rate_per_second = total, rate_per_second_per_machine = total / count,
        port_bound = true,
    }
end

local function hand_groups_for(block, step, machine, catalog, input, flows)
    local machine_count = step._rate_machine_count or step.machine_count or 1
    local inputs, outputs = {}, {}
    for _, port in ipairs(step.inputs or {}) do
        if not flow_is_fluid(port, flows) then inputs[#inputs + 1] = port end
    end
    for _, port in ipairs(step.outputs or {}) do
        if not flow_is_fluid(port, flows) then outputs[#outputs + 1] = port end
    end

    local groups, used = {}, {}
    local capacity = finite(catalog and catalog.belt and catalog.belt.items_per_second)
    local function input_bound(port)
        return port_bound_for(block, machine, "input", port, flows)
    end
    for index, port in ipairs(inputs) do
        if not used[index] then
            local pair
            if multi_flow_hands and capacity and capacity > 0 and input_bound(port) then
                for other_index = index + 1, #inputs do
                    local other = inputs[other_index]
                    if not used[other_index] and input_bound(other) and same_cell(port, other)
                        and flow_entry_rate(port) + flow_entry_rate(other) <= capacity + math.max(1e-9, capacity * 1e-9) then
                        pair = other_index
                        break
                    end
                end
            end
            local entries = pair and {port, inputs[pair]} or {port}
            groups[#groups + 1] = hand_group("input", entries, machine_count)
            used[index] = true
            if pair then used[pair] = true end
        end
    end
    for _, port in ipairs(outputs) do groups[#groups + 1] = hand_group("output", {port}, machine_count) end
    -- A hand has a finite transfer rate. Split each single-flow obligation into independent
    -- hands so every hand and every routed port has an honest per-hand rate.
    local capacity = finite(catalog and catalog.inserter and catalog.inserter.items_per_second)
    if capacity and capacity > 0 then
        local expanded = {}
        for _, hand in ipairs(groups) do
            local count = 1
            if #hand.flow_ids == 1 then
                count = math.max(1, math.ceil(hand.rate_per_second_per_machine / capacity - 1e-9))
            end
            for ordinal = 1, count do
                local part = copy(hand)
                if count > 1 then
                    local id = hand.flow_ids[1]
                    part.key = hand.key .. ":hand:" .. tostring(ordinal)
                    part.rate_per_second = hand.rate_per_second / count
                    part.rate_per_second_per_machine = hand.rate_per_second_per_machine / count
                    part.flow_shares[id] = (part.flow_shares[id] or 0) / count
                    part.flow_shares_per_machine[id] = (part.flow_shares_per_machine[id] or 0) / count
                    part.port = copy(hand.port)
                    part.port.port_id = tostring(hand.port.port_id or id) .. ":hand:" .. tostring(ordinal)
                    part.port.rate_per_second = (flow_entry_rate(hand.port) / count)
                    part.ports = {part.port}
                end
                expanded[#expanded + 1] = part
            end
        end
        groups = expanded
    end
    return groups
end

--Round 26 row block: every item input of the row rides one shared two-lane belt, one flow per lane, so
--the row's input hand carries all of them (at most two) whatever the single-belt pairing rule says.
--Outputs keep one hand each. Nil when the step cannot be a row.
local function row_hand_groups(step, flows)
    local machine_count = step._rate_machine_count or step.machine_count or 1
    local inputs, groups = {}, {}
    for _, port in ipairs(step.inputs or {}) do
        if not flow_is_fluid(port, flows) then inputs[#inputs + 1] = port end
    end
    if #inputs > 3 then return nil end
    if #inputs > 0 then
        --Three or more inputs: the plain hand reads the near belt, which carries the first two flows in flow-id
        --order; the rest ride far belts read by long hands (docs/contracts/row_block.md §Far belt).
        table.sort(inputs, function(a, b) return tostring(a.flow_id or a.full_name) < tostring(b.flow_id or b.full_name) end)
        groups[#groups + 1] = hand_group("input", #inputs <= 2 and inputs or {inputs[1], inputs[2]}, machine_count)
    end
    local outs = 0
    for _, port in ipairs(step.outputs or {}) do
        if not flow_is_fluid(port, flows) then
            outs = outs + 1
            groups[#groups + 1] = hand_group("output", {port}, machine_count)
        end
    end
    if outs > 1 then return nil end
    return groups
end

local function contains_flow(hand, flow_id)
    if type(hand and hand.flow_ids) == "table" then
        for _, id in ipairs(hand.flow_ids) do if id == flow_id then return true end end
        return false
    end
    return hand and hand.flow_id == flow_id
end

local function new_face_allocator(machine, iw, ih, block)
    local capacities = {
        top = math.floor(machine.w / math.max(1, iw)),
        bottom = math.floor(machine.w / math.max(1, iw)),
        left = math.floor(machine.h / math.max(1, ih)),
        right = math.floor(machine.h / math.max(1, ih)),
    }
    if machine.y <= 0 then capacities.top = 0 end
    if block and block.has_bottom_beacon_row then capacities.bottom = 0 end
    if block and block.has_top_beacon_row then capacities.top = 0 end
    local used = {top = 0, bottom = 0, left = 0, right = 0}
    return function(preferred)
        local order = block and block.hand_face_spread
            and {preferred, "top", "bottom", "left", "right"} or {preferred}
        local seen = {}
        for _, side in ipairs(order) do
            if side and not seen[side] then
                seen[side] = true
                if used[side] < (capacities[side] or 0) then
                    used[side] = used[side] + 1
                    return side, used[side]
                end
            end
        end
        return nil
    end
end

local function append_single_flow_inserters(block, step, machine, catalog, input, flows)
    local name, iw, ih = inserter_size(catalog, input and input.inserter)
    local inputs, outputs = {}, {}
    for _, port in ipairs(step.inputs or {}) do
        if not flow_is_fluid(port, flows) then inputs[#inputs + 1] = port end
    end
    for _, port in ipairs(step.outputs or {}) do
        if not flow_is_fluid(port, flows) then outputs[#outputs + 1] = port end
    end
    local allocate_face = new_face_allocator(machine, iw, ih, block)
    local function append(role, list)
        for index, port in ipairs(list) do
            local entry = {role = role, port = port}
            local port_bound, source_member, target_member = port_bound_for(block, machine, role, port, flows)
            local transfer_source_member = source_member
            if role == "output" then transfer_source_member = machine end
            local face, face_column
            if port_bound then
                local assigned = block.face_by_machine and block.face_by_machine[machine.id]
                    and block.face_by_machine[machine.id][port.flow_id or port.full_name]
                face, face_column = allocate_face(assigned)
                if not face then
                    block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                        detail = "no free machine face for " .. tostring(port.flow_id or port.full_name)}
                    return
                end
            end
            local source_x, source_y = explicit_cell(port, role == "input"
                and {"pickup_cell", "source_cell", "source_position"}
                or {"drop_cell", "drain_cell", "drain_position"})
            local target_x, target_y = explicit_cell(port, role == "input"
                and {"drop_cell", "target_cell", "target_position"}
                or {"pickup_cell", "source_cell", "source_position"})
            local source_cell = source_x ~= nil and {source_x, source_y} or nil
            local target_cell = target_x ~= nil and {target_x, target_y} or nil
            local placement = candidate_inserter(block, machine, role, index, iw, ih, catalog, input,
                transfer_source_member, target_member, source_cell, target_cell, port_bound, face_column,
                face)
            if not placement then
                block.failure = {name = "inserter-reach", code = "BP_P_NO_FIT",
                    detail = "no catalog inserter reach for " .. tostring(step.step_id) .. ":"
                        .. tostring(port.flow_id or port.full_name)}
                return
            end
            block.inserters[#block.inserters + 1] = {
            id = member_id("inserter", step.step_id, machine.ordinal, entry.role .. ":" .. tostring(index)),
            kind = "inserter", type = "inserter", name = name,
            step_id = step.step_id, machine_id = machine.id, role = entry.role,
            port_id = (entry.role == "input" and "in:" or "out:")
                .. tostring(entry.port.port_id or entry.port.flow_id or entry.port.full_name),
            flow_id = entry.port.flow_id or entry.port.full_name,
            x = placement.x, y = placement.y, w = iw, h = ih, dir = placement.dir,
            -- These are block-frame coordinates until materialize rotates and translates the member.  Keeping
            -- the assignments explicit is intentional: the validator must consume the captured cells and never
            -- fall back to its direction-vector guess.
            pickup_position = placement.pickup_position,
            drop_position = placement.drop_position,
            pickup_target = entry.role == "input"
                and (entry.port.source_id or entry.port.source_port_id or ("port:" .. tostring(entry.port.flow_id or entry.port.full_name)))
                or machine.id,
            drop_target = entry.role == "input"
                and machine.id
                or (entry.port.drain_id or entry.port.drain_port_id or ("port:" .. tostring(entry.port.flow_id or entry.port.full_name))),
            port_bound = port_bound,
            }
        end
    end
    append("input", inputs)
    append("output", outputs)
end

local function append_multi_flow_inserters(block, step, machine, catalog, input, flows)
    local name, iw, ih = inserter_size(catalog, input and input.inserter)
    local groups = block.hand_groups_by_machine and block.hand_groups_by_machine[machine.id] or
        hand_groups_for(block, step, machine, catalog, input, flows)
    local machine_count = math.max(1, step._rate_machine_count or step.machine_count or 1)
    local allocate_face = new_face_allocator(machine, iw, ih, block)
    for index, hand in ipairs(groups) do
        local port_bound, source_member, target_member = port_bound_for(block, machine, hand.role, hand.port, flows)
        hand.port_bound = port_bound
        local face, face_column
        if port_bound then
            local preferred = block.face_by_machine and block.face_by_machine[machine.id]
                and block.face_by_machine[machine.id][hand.flow_ids[1]]
            face, face_column = allocate_face(preferred)
            if not face then
                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                    detail = "no free machine face for " .. tostring(hand.flow_ids[1])}
                return
            end
        end
        local source_x, source_y = explicit_cell(hand.port, hand.role == "input"
            and {"pickup_cell", "source_cell", "source_position"}
            or {"drop_cell", "drain_cell", "drain_position"})
        local target_x, target_y = explicit_cell(hand.port, hand.role == "input"
            and {"drop_cell", "target_cell", "target_position"}
            or {"pickup_cell", "source_cell", "source_position"})
        local source_cell = source_x ~= nil and {source_x, source_y} or nil
        local target_cell = target_x ~= nil and {target_x, target_y} or nil
        local transfer_source_member = hand.role == "output" and machine or source_member
        local placement = candidate_inserter(block, machine, hand.role, index, iw, ih, catalog, input,
            transfer_source_member, target_member, source_cell, target_cell, port_bound, face_column, face)
        if not placement then
            block.failure = {name = "inserter-reach", code = "BP_P_NO_FIT",
                detail = "no catalog inserter reach for " .. tostring(step.step_id) .. ":" .. tostring(hand.key)}
            return
        end
        local id = member_id("inserter", step.step_id, machine.ordinal, hand.role .. ":" .. tostring(index))
        local shared = #hand.flow_ids > 1
        local flow_ids = shared and list_copy(hand.flow_ids) or nil
        local flow_shares = shared and copy(hand.flow_shares_per_machine) or nil
        block.inserters[#block.inserters + 1] = {
            id = id, kind = "inserter", type = "inserter", name = name,
            step_id = step.step_id, machine_id = machine.id, role = hand.role,
            port_id = shared and ((hand.role == "input" and "in:" or "out:") .. "shared:" .. hand.key)
                or ((hand.role == "input" and "in:" or "out:")
                    .. tostring(hand.port.port_id or hand.port.flow_id or hand.port.full_name)),
            flow_id = shared and nil or hand.flow_ids[1], flow_ids = flow_ids, flow_shares = flow_shares,
            rate_per_second = hand.rate_per_second_per_machine,
            x = placement.x, y = placement.y, w = iw, h = ih, dir = placement.dir,
            pickup_position = placement.pickup_position, drop_position = placement.drop_position,
            flow_entries = shared and list_copy(hand.ports) or nil,
            pickup_target = hand.role == "input"
                and (shared and ("port:" .. id)
                    or (hand.port.source_id or hand.port.source_port_id
                        or ("port:" .. tostring(hand.port.flow_id or hand.port.full_name))))
                or machine.id,
            drop_target = hand.role == "input"
                and machine.id
                or (shared and ("port:" .. id)
                    or (hand.port.drain_id or hand.port.drain_port_id
                        or ("port:" .. tostring(hand.port.flow_id or hand.port.full_name)))),
            port_bound = port_bound,
            _hand_key = hand.key,
        }
    end
end

local function append_inserters(block, step, machine, catalog, input, flows)
    if multi_flow_hands then
        return append_multi_flow_inserters(block, step, machine, catalog, input, flows)
    end
    return append_single_flow_inserters(block, step, machine, catalog, input, flows)
end

local function port_for_hand(inserter, fallback)
    if not inserter then return fallback end
    local source = copy(fallback or {})
    if inserter.rate_per_second ~= nil then source.rate_per_second = inserter.rate_per_second end
    if not (type(inserter.flow_ids) == "table" and #inserter.flow_ids > 1) then
        source.port_id = inserter.port_id or source.port_id
        return source
    end
    source.flow_id, source.full_name = nil, nil
    source.flow_ids = list_copy(inserter.flow_ids)
    source.flow_shares = {}
    source.rate_per_second = 0
    for _, entry in ipairs(inserter.flow_entries or {}) do
        local id = flow_entry_id(entry)
        local share = flow_entry_rate(entry)
        if id ~= nil then source.flow_shares[id] = share; source.rate_per_second = source.rate_per_second + share end
    end
    source.port_id = inserter.port_id
    source.role = inserter.role == "input" and "in" or "out"
    source.kind, source.is_fluid = "item", false
    return source
end

local function block_ports(block, steps, ports, flows)
    local members_by_step = {}
    local machine_count_by_step = {}
    for _, step in ipairs(steps or {}) do
        machine_count_by_step[step.step_id] = math.max(1, step._rate_machine_count or step.machine_count or 1)
    end
    for _, machine in ipairs(block.machines) do
        members_by_step[machine.step_id] = members_by_step[machine.step_id] or {}
        members_by_step[machine.step_id][#members_by_step[machine.step_id] + 1] = machine
    end

    local selected, selected_hands = {}, {}
    for _, port in ipairs(ports or {}) do
        local flow_id = port.flow_id or port.full_name or port.id
        local step_id = port.step_id or port.member_step_id
        if step_id and members_by_step[step_id] then
            local is_fluid = port.kind == "fluid" or port.is_fluid == true
            if is_fluid then
                -- Every replicated machine has its own fluid box. Preserve one pipe endpoint per machine so
                -- validation and routing can witness the physical connection on every member.
                for _, machine in ipairs(members_by_step[step_id]) do
                    local machine_port = copy(port)
                    machine_port.port_id = tostring(port.port_id) .. ":" .. tostring(machine.id)
                    selected[#selected + 1] = {
                        port = machine_port, flow_id = flow_id, step_id = step_id, member_id = machine.id,
                    }
                end
            else
                for _, inserter in ipairs(block.inserters or {}) do
                    local wanted_role = port.role == "out" and "output" or "input"
                    if inserter.port_bound and inserter.step_id == step_id and inserter.role == wanted_role
                        and contains_flow(inserter, flow_id) and not selected_hands[inserter.id] then
                        selected_hands[inserter.id] = true
                        local selected_port = {
                            port = port_for_hand(inserter, port), flow_id = flow_id, step_id = step_id,
                            member_id = inserter.machine_id, inserter_id = inserter.id, inserter = inserter,
                        }
                        if inserter.flow_ids then selected_port.flow_id = nil end
                        selected[#selected + 1] = selected_port
                    end
                end
            end
        end
    end

    -- A partition can put the producer and consumer of an internal flow in different blocks.  That hand is
    -- external to this block even though the flow has no sheet perimeter terminal, so it still needs a real
    -- block port for the unchanged router to connect.  External plan ports were selected above; this fills only
    -- the missing cross-block interfaces and never duplicates an already selected hand.
    selected_hands = {}
    for _, selected_port in ipairs(selected) do
        if selected_port.inserter_id ~= nil then selected_hands[selected_port.inserter_id] = true end
    end
    for _, inserter in ipairs(block.inserters or {}) do
        if inserter.port_bound and not selected_hands[inserter.id] then
            local wanted_role = inserter.role == "input" and "in" or "out"
            local source
            for _, step in ipairs(steps or {}) do
                if step.step_id == inserter.step_id then
                    local entries = wanted_role == "in" and step.inputs or step.outputs
                    for _, entry in ipairs(entries or {}) do
                        if contains_flow(inserter, entry.flow_id or entry.full_name) then
                            source = port_for_hand(inserter, entry)
                            source.port_id = source.port_id
                                or (tostring(step.step_id) .. ":" .. wanted_role .. ":" .. tostring(inserter.flow_id))
                            source.role = wanted_role
                            source.kind = source.kind or (flow_is_fluid(source, flows) and "fluid" or "item")
                            source.is_fluid = source.kind == "fluid" or source.is_fluid == true
                            if not source.flow_ids then source.flow_id = source.flow_id or source.full_name end
                            break
                        end
                    end
                    break
                end
            end
            if source then
                selected[#selected + 1] = {
                    port = source, flow_id = source.flow_id, step_id = inserter.step_id,
                    member_id = inserter.machine_id, inserter_id = inserter.id, inserter = inserter,
                }
            end
        end
    end
    table.sort(selected, function(a, b)
        local aid = tostring(a.port.port_id or a.port.id or a.flow_id)
        local bid = tostring(b.port.port_id or b.port.id or b.flow_id)
        if aid ~= bid then return aid < bid end
        return tostring(a.inserter_id or "") < tostring(b.inserter_id or "")
    end)

    local inputs, outputs = {}, {}
    for _, selected_port in ipairs(selected) do
        local role = selected_port.port.role == "out" and "out" or "in"
        if role == "out" then outputs[#outputs + 1] = selected_port else inputs[#inputs + 1] = selected_port end
    end
    --Ports without an item hand still use the deterministic side fallback below. Item ports with a hand use its
    --captured outward cell directly, so the side bookkeeping is derived from the actual attachment.
    local function place_side(list, role, side, normal, travel, offset)
        for index, selected_port in ipairs(list) do
            local x, y
            if side == "top" then
                x, y = (offset or 0) + index - 1, -1
            elseif side == "bottom" then
                x, y = (offset or 0) + index - 1, block.h
            elseif side == "left" then
                x, y = -1, (offset or 0) + index - 1
            else
                x, y = block.w, (offset or 0) + index - 1
            end
            local source = selected_port.port
            local inserter_id = selected_port.inserter_id
            local wanted_role = role == "in" and "input" or "output"
            local inserter = selected_port.inserter
            if inserter then
                local position = role == "in" and point(inserter.pickup_position) or point(inserter.drop_position)
                if position then x, y = cell_of(position.x), cell_of(position.y) end
            else
                for _, candidate_inserter in ipairs(block.inserters or {}) do
                    if candidate_inserter.machine_id == selected_port.member_id and candidate_inserter.role == wanted_role
                        and contains_flow(candidate_inserter, source.flow_id or source.full_name or selected_port.flow_id) then
                        inserter_id = candidate_inserter.id
                        local position = role == "in" and point(candidate_inserter.pickup_position)
                            or point(candidate_inserter.drop_position)
                        if position then
                            local candidate_x, candidate_y = cell_of(position.x), cell_of(position.y)
                            local on_edge = (candidate_x == -1 and candidate_y >= 0 and candidate_y < block.h)
                                or (candidate_x == block.w and candidate_y >= 0 and candidate_y < block.h)
                                or (candidate_y == -1 and candidate_x >= 0 and candidate_x < block.w)
                                or (candidate_y == block.h and candidate_x >= 0 and candidate_x < block.w)
                            if on_edge then x, y = candidate_x, candidate_y end
                        end
                        break
                    end
                end
            end
            local machine = member_for(block, selected_port.member_id)
            local fluid_pipe_tile
            if source.kind == "fluid" or source.is_fluid == true then
                local connection = source.connection
                local position = connection and point(connection.position or connection.pos)
                if not position and connection and type(connection.positions) == "table" then
                    position = point(connection.positions[1])
                end
                if machine and position then
                    local dx, dy = Grid.rotate_vector(position.x, position.y, machine.dir or NORTH)
                    local connection_x = cell_of(machine.x + machine.w / 2 + dx)
                    local connection_y = cell_of(machine.y + machine.h / 2 + dy)
                    source.connection_position = {x = connection_x, y = connection_y}
                    --The catalog position is the machine's OWN tile that carries the fluid box; the pipe that
                    --connects to it sits one tile further along the connection's direction. That pipe tile is
                    --the port, wherever it falls: on the block edge or in a gap row inside the envelope.
                    --The old test accepted the machine tile only when it lay OUTSIDE the block, which never
                    --happens, so every fluid port fell back to the arbitrary top/left fallback slot.
                    local outward = Grid.rotate_dir(connection.direction or connection.dir or NORTH, machine.dir or NORTH)
                    local ox, oy = Grid.dir_vector(outward)
                    local inside = connection_x >= machine.x and connection_x < machine.x + machine.w
                        and connection_y >= machine.y and connection_y < machine.y + machine.h
                    if not inside then ox, oy = 0, 0 end
                    if ox then
                        x, y = connection_x + ox, connection_y + oy
                        fluid_pipe_tile = {normal = Grid.dir_opposite(outward),
                            travel = role == "in" and Grid.dir_opposite(outward) or outward}
                    end
                end
            end
            local actual_normal, actual_travel = normal, travel
            if fluid_pipe_tile then actual_normal, actual_travel = fluid_pipe_tile.normal, fluid_pipe_tile.travel end
            if fluid_pipe_tile then
            elseif x == -1 then actual_normal, actual_travel = EAST, role == "in" and EAST or WEST
            elseif x == block.w then actual_normal, actual_travel = WEST, role == "in" and WEST or EAST
            elseif y == -1 then actual_normal, actual_travel = SOUTH, role == "in" and SOUTH or NORTH
            elseif y == block.h then actual_normal, actual_travel = NORTH, role == "in" and NORTH or SOUTH end
            local actual_side
            if x == -1 then actual_side = "left" elseif x == block.w then actual_side = "right"
            elseif y == -1 then actual_side = "top" elseif y == block.h then actual_side = "bottom" end
            if actual_side then
                block.port_sides = block.port_sides or {}
                block.port_sides[actual_side] = true
            else
                block.port_sides = block.port_sides or {}
                block.port_sides[side] = true
            end
            local shared = type(source.flow_ids) == "table" and #source.flow_ids > 1
            local block_port_id = source.port_id or source.id or ((role or "port") .. ":" .. tostring(index))
            if inserter_id ~= nil then block_port_id = tostring(block_port_id) .. ":" .. tostring(inserter_id) end
            local block_port = {
                port_id = block_port_id,
                role = role, kind = source.kind or (source.is_fluid and "fluid" or "item"),
                flow_id = shared and nil or (source.flow_id or source.full_name or selected_port.flow_id),
                flow_ids = shared and list_copy(source.flow_ids) or nil,
                flow_shares = shared and copy(source.flow_shares) or nil,
                rate_per_second = source.rate_per_second,
                step_id = selected_port.step_id,
                attach_dx = x, attach_dy = y, normal_dir = actual_normal, travel_dir = actual_travel,
                member_id = selected_port.member_id, inserter_id = inserter_id,
                fluid_pinned = fluid_pipe_tile ~= nil or nil,
            }
            local machine_count = machine_count_by_step[selected_port.step_id]
            if block_port.rate_per_second ~= nil and machine_count and machine_count > 0 then
                block_port.rate_per_second = block_port.rate_per_second / machine_count
            end
            if shared then
                for flow_id, share in pairs(block_port.flow_shares or {}) do
                    block_port.flow_shares[flow_id] = share / math.max(1, machine_count or 1)
                end
            end
            for _, field in ipairs({"full_name", "is_fluid", "machine", "machine_id", "fluidbox_index", "box_index",
                "connection_index", "pipe_connection_index", "production_type", "filter", "connection_position"}) do
                if source[field] ~= nil then block_port[field] = copy(source[field]) end
            end
            if source.connection ~= nil then block_port.connection = copy(source.connection) end
            if source.pipe_connection ~= nil then block_port.pipe_connection = copy(source.pipe_connection) end
            block.ports[#block.ports + 1] = block_port
        end
    end
    place_side(inputs, "in", "top", SOUTH, SOUTH, 0)
    place_side(outputs, "out", "left", EAST, Grid.WEST, 0)
end

local function build_block(step_group, catalog, ports, flows, input, block_id)
    local steps = list_copy(step_group)
    table.sort(steps, function(a, b) return a.step_id < b.step_id end)
    local block = {
        id = block_id, block_id = block_id, members = {}, machines = {}, beacons = {}, inserters = {}, ports = {},
        beacon_coverage = {}, physical_beacon_count = 0,
        allowed_dirs = {NORTH},
    }
    local beacon_groups = {}
    local seen_groups = {}
    for _, step in ipairs(steps) do
        for _, group in ipairs(step._groups) do
            local existing = beacon_groups[group.signature]
            if not existing then
                existing = copy(group)
                existing.required_machines = {}
                beacon_groups[group.signature] = existing
            end
            -- This is a per-machine requirement.  The number of physical beacons is determined below by the
            -- rows and their actual overlap, so it must never be stored in this field.
            existing.count_per_machine = math.max(existing.count_per_machine, group.count_per_machine)
            existing.has_speed_module = existing.has_speed_module or group.has_speed_module
            seen_groups[group.signature] = true
        end
    end
    local ordered_groups = {}
    for _, group in pairs(beacon_groups) do ordered_groups[#ordered_groups + 1] = group end
    table.sort(ordered_groups, function(a, b) return a.signature < b.signature end)

    -- Put the machines in a compact deterministic strip.  With external item hands, the strip turns vertical:
    -- the two long sides are available to every machine and the top/bottom endpoints provide the remaining
    -- faces for a two-machine step.  Blocks without item ports retain the established horizontal strip, which
    -- keeps beacon-only grouping independent of transport-face layout.
    local face_per_flow = true
    local has_item_port = false
    for _, port in ipairs(ports or {}) do
        if not flow_is_fluid(port, flows) then has_item_port = true; break end
    end
    -- A one/two-machine block can put each hand on a real machine face. Larger legacy strips still keep every
    -- hand on their common bottom perimeter; their ports are grouped by flow on separate block faces so the
    -- unchanged router sees contiguous, routable endpoints. The strict machine-face check below remains the
    -- refusal path for layouts whose individual machines cannot expose enough perimeter faces.
    local machine_total = 0
    for _, step in ipairs(steps) do machine_total = machine_total + step.machine_count end
    local face_layout = face_per_flow and has_item_port and machine_total <= 2
    local logical_face_layout = face_per_flow and has_item_port
    --A row takes at most three item inputs: two on the near belt, one on a far belt read by long hands.
    --Four or more stay unsupported, as before round 29: a far belt with two side-fed flows lost one of them in
    --route (tests/golden/long_hand_probe.lua 2, 2026-09-24), and single-machine blocks run out of faces.
    local row_layout = machine_total >= 2
    for _, step in ipairs(steps) do
        for _, role in ipairs({"inputs", "outputs"}) do
            for _, entry in ipairs(step[role] or {}) do
                if flow_is_fluid(entry, flows) then row_layout = false end
            end
        end
        if item_port_count(step, "outputs", flows) > 1 then row_layout = false end
        if item_port_count(step, "inputs", flows) > 3 then row_layout = false end
    end
    --A row is one horizontal line of touching machines; the one/two machine vertical face stack never applies.
    if row_layout then face_layout = false end
    local machine_specs = {}
    local machine_specs_by_id = {}
    local machines_by_id = {}
    local max_machine_h = 1
    local machine_w = 0
    local machine_h = 0
    for _, step in ipairs(steps) do
        local mw, mh = machine_size(step, catalog)
        local machine_spec = lookup_entity(catalog, step.machine, "machine")
        max_machine_h = math.max(max_machine_h, mh)
        local layout_w = mw
        local _, step_inserter_w = inserter_size(catalog, input and input.inserter)
        for _, entry in ipairs(step.inputs or {}) do layout_w = math.max(layout_w, step_inserter_w) end
        for _, entry in ipairs(step.outputs or {}) do layout_w = math.max(layout_w, step_inserter_w) end
        for ordinal = 1, step.machine_count do
            local physical_ordinal = step._physical_ordinal or ordinal
            local spec = {step = step, ordinal = physical_ordinal, w = mw, h = mh, layout_w = layout_w,
                machine_spec = machine_spec}
            spec.id = member_id("machine", step.step_id, physical_ordinal)
            machine_specs[#machine_specs + 1] = spec
            machine_specs_by_id[spec.id] = spec
            if face_layout then
                machine_w = math.max(machine_w, layout_w)
                machine_h = machine_h + mh
                if #machine_specs > 1 then machine_h = machine_h + 1 end
            elseif row_layout then
                machine_w = machine_w + mw
                machine_h = math.max(machine_h, mh)
            else
                machine_w = machine_w + layout_w
                if #machine_specs > 1 then machine_w = machine_w + 1 end
            end
        end
    end

    -- Ordinary blocks use a beacon strip above their machines. Machine rows keep their input face above
    -- the machines, so their beacon strip belongs below the output belt instead.
    --beacon_rows_h measures ONLY the rows stacked ABOVE the machine strip, because that is the single thing
    --it is used for: the machine strip's y offset and the top rows' own stacking. Counting a bottom row here
    --pushed the machines a full row further down while the top row stayed at y=0, so the top row no longer
    --reached the machine and a three-beacon requirement covered nothing.
    local beacon_rows_h = 0
    local top_rows, bottom_rows, beacon_row_specs = {}, {}, {}
    for _, group in ipairs(ordered_groups) do
        if group.count_per_machine > 0 then
            local bw, bh = dimensions(catalog, group.name, "beacon", 3, 3)
            local count = math.max(1, group.count_per_machine)
            --One row per side is only worth its height when the near side cannot satisfy the requirement on
            --its own. A beacon row reaches a machine from above with supply measured from its centre, so a
            --single row of adjacent beacons already covers a machine several times over. Placing a second
            --row unconditionally cost a one-beacon machine FOUR beacons and made every block tall enough
            --that, once rotated, it walled the perimeter ports into a pocket with no route out.
            if row_layout then
                local output = {group = group, w = bw, h = bh, count = count, side = "output"}
                bottom_rows[#bottom_rows + 1] = output
                beacon_row_specs[#beacon_row_specs + 1] = output
                -- A possible second output row is used only if actual supply-box coverage from the first
                -- row leaves a deficit. place_row skips it when the first row is enough.
                local second = {group = group, w = bw, h = bh, count = count, side = "output"}
                bottom_rows[#bottom_rows + 1] = second
                beacon_row_specs[#beacon_row_specs + 1] = second
            else
                local top = {group = group, w = bw, h = bh, count = count, side = "top"}
                top_rows[#top_rows + 1] = top
                beacon_row_specs[#beacon_row_specs + 1] = top
                beacon_rows_h = beacon_rows_h + bh + 1
            end
        end
    end
    if beacon_rows_h > 0 then beacon_rows_h = beacon_rows_h - 1 end

    --Beacons sit adjacent. A one-tile gap pushes centres a full pitch apart, and since supply reach is
    --measured from the CENTRE, that gap costs a narrow machine the third supply area it needs.
    local function row_width(row)
        if row.count <= 0 then return 0 end
        local far = 0
        for _, origin_x in ipairs(row.positions or {}) do far = math.max(far, origin_x + row.w) end
        if far > 0 then return far end
        return row.count * row.w
    end

    local function rows_width()
        local result = 0
        for _, row in ipairs(beacon_row_specs) do result = math.max(result, row_width(row)) end
        return result
    end

    local input_count, output_count = 0, 0
    for _, port in ipairs(ports or {}) do
        if port.role == "out" then output_count = output_count + 1 else input_count = input_count + 1 end
    end
    local w = math.max(1, machine_w, rows_width(), input_count, output_count, input_count + output_count)
    local machine_y = beacon_rows_h > 0 and beacon_rows_h + 1 or 0
    --Insetting the machine row by one is what MAKES the top face a perimeter face. Without it the row
    --starts at y=0, a hand above it occupies y=-1 and its outward cell lands at y=-2, which is two tiles
    --outside a block whose own top edge is -1. Measured on the player's sheet: block:iron-plate published
    --its iron-ore ports at attach_dy=-2, pack.lua's bounded_slot refused every one of them, and packing
    --could place that block on no grid at all -- BP_FAIL_GRID_LIMIT with twelve BP_P_NO_FIT and zero
    --candidates reaching validate. The inset is owed to every block that puts a hand on a face, not only
    --to the one and two machine cases that face_layout covers.
    if (face_layout or logical_face_layout) and beacon_rows_h == 0 then machine_y = 1 end
    if row_layout and beacon_rows_h == 0 then
        --A far belt above the row needs two more rows: the belt and its top side feed.
        machine_y = item_port_count(steps[1], "inputs", flows) >= 3 and 4 or 2
    end
    if beacon_rows_h > 0 then
        -- Keep the established spacer when the collision box still reaches the row, but remove it when the
        -- actual y extent would leave a gap.  This is deliberately a world-box test, not a centre comparison.
        local needs_tighter_row = false
        local row_y = 0
        for _, row in ipairs(top_rows) do
            row.y = row_y
            row_y = row_y + row.h + 1
            for _, spec in ipairs(machine_specs) do
                local requests = false
                for _, entry in ipairs(spec.step._groups or {}) do
                    if entry.signature == row.group.signature and entry.count_per_machine > 0 then
                        requests = true
                        break
                    end
                end
                local beacon = {x = 0, y = row.y, w = row.w, h = row.h}
                local box = Geometry.world_box({x = 0, y = machine_y, w = spec.w, h = spec.h}, spec.machine_spec)
                local beacon_x, beacon_y = Geometry.center(beacon)
                local supply = Geometry.supply_box(beacon_x, beacon_y, row.group.supply_w + row.w / 2,
                    (row.group.supply_h or row.group.supply_w) + row.h / 2)
                local y_overlap = box.top < supply.bottom + Geometry.EPSILON
                    and supply.top - Geometry.EPSILON < box.bottom
                if requests and not y_overlap then
                    needs_tighter_row = true
                    break
                end
            end
            if needs_tighter_row then break end
        end
        if needs_tighter_row then machine_y = beacon_rows_h end
    end
    --Offset the machine strip by one beacon width when any group needs beacons, so a row starting at x=0
    --straddles the machines instead of starting flush with them. Supply reach is measured from the beacon
    --CENTRE, so a flush row puts its last beacon's centre past the far edge of a narrow machine and that
    --beacon covers nothing: a 3-wide machine could be reached by only two beacons however many were placed.
    --A row starts flush at x=0 so it is mirror-symmetric about its machines' centre line: its head sits one tile
    --before the first pickup and its output port one tile past the run's end, so legacy run reversal could flip either
    --run and every port still lands on the block boundary (docs/contracts/row_block.md §Reversal).
    local machine_x0 = row_layout and 0 or (face_layout and 1 or 0)
    for _, row in ipairs(beacon_row_specs) do
        if not face_layout then machine_x0 = math.max(machine_x0, row.w) end
    end
    local x, y = machine_x0, machine_y
    for _, spec in ipairs(machine_specs) do
        local machine = {
            id = spec.id,
            kind = "machine", type = "machine", name = spec.step.machine, entity = spec.step.machine,
            quality = spec.step.machine_quality, step_id = spec.step.step_id, ordinal = spec.ordinal,
            x = x, y = y, w = spec.w, h = spec.h,
            modules = list_copy(spec.step.modules), forbids_speed_beacon = spec.step.forbids_speed_beacon,
        }
        local machine_etype = spec.machine_spec and spec.machine_spec.etype
        if machine_etype ~= nil then machine.etype = machine_etype end
        -- Recipe fields are meaningful only for assembling-machine prototypes. In particular, a furnace's
        -- product is determined by its item input and must never be turned into a blueprint recipe field merely
        -- because the plan step happens to carry a recipe name.
        if machine_etype == "assembling-machine" and spec.step.recipe ~= nil then
            machine.recipe = spec.step.recipe
            machine.recipe_quality = spec.step.recipe_quality
        end
        if spec.step.module_inventory ~= nil then machine.module_inventory = copy(spec.step.module_inventory) end
        if spec.step.inventory ~= nil then machine.inventory = copy(spec.step.inventory) end
        block.machines[#block.machines + 1] = machine
        block.members[#block.members + 1] = machine
        machines_by_id[machine.id] = machine
        if face_layout then y = y + spec.h + 1
        elseif row_layout then x = x + spec.w
        else x = x + spec.layout_w + 1 end
    end

    if row_layout then
        block.row = {machines = #block.machines}
        block.allowed_dirs = {NORTH, EAST}
        block.face_by_machine = {}
        for _, machine in ipairs(block.machines) do
            block.face_by_machine[machine.id] = {}
            for _, flow in ipairs(steps[1].inputs or {}) do
                if not flow_is_fluid(flow, flows) then block.face_by_machine[machine.id][flow.flow_id or flow.full_name] = "top" end
            end
            for _, flow in ipairs(steps[1].outputs or {}) do
                if not flow_is_fluid(flow, flows) then block.face_by_machine[machine.id][flow.flow_id or flow.full_name] = "bottom" end
            end
        end
    end

    if multi_flow_hands then
        block.hand_groups_by_machine, block.hand_key_by_machine, block.hand_flows = {}, {}, {}
        for _, machine in ipairs(block.machines) do
            local step
            for _, candidate in ipairs(steps) do
                if candidate.step_id == machine.step_id then step = candidate; break end
            end
            local groups = row_layout and row_hand_groups(step or {}, flows)
                or hand_groups_for(block, step or {}, machine, catalog, input, flows)
            local by_flow = {}
            block.hand_groups_by_machine[machine.id] = groups
            block.hand_key_by_machine[machine.id] = by_flow
            for _, hand in ipairs(groups) do
                block.hand_flows[hand.key] = list_copy(hand.flow_ids)
                for _, flow_id in ipairs(hand.flow_ids) do by_flow[flow_id] = hand.key end
            end
        end
    end

    if logical_face_layout and not row_layout then
        local flow_machines, machine_indices = {}, {}
        for index, machine in ipairs(block.machines) do machine_indices[machine.id] = index end
        for _, machine in ipairs(block.machines) do
            local step
            for _, candidate in ipairs(steps) do
                if candidate.step_id == machine.step_id then step = candidate; break end
            end
            local function collect(role, entries)
                for _, port in ipairs(entries or {}) do
                    if not flow_is_fluid(port, flows) then
                        local bound = port_bound_for(block, machine, role, port, flows)
                        if bound then
                            local flow_id = port.flow_id or port.full_name
                            if multi_flow_hands then
                                flow_id = block.hand_key_by_machine[machine.id][flow_id] or flow_id
                            end
                            flow_machines[flow_id] = flow_machines[flow_id] or {}
                            flow_machines[flow_id][machine.id] = machine
                        end
                    end
                end
            end
            collect("input", step and step.inputs)
            collect("output", step and step.outputs)
        end

        local flow_ids = {}
        for flow_id, _ in pairs(flow_machines) do flow_ids[#flow_ids + 1] = flow_id end
        table.sort(flow_ids)
        local function set_face(machine_id, flow_id, side)
            block.face_by_machine[machine_id][flow_id] = side
            if multi_flow_hands and block.hand_flows[flow_id] then
                for _, member_flow_id in ipairs(block.hand_flows[flow_id]) do
                    block.face_by_machine[machine_id][member_flow_id] = side
                end
            end
        end
        if #flow_ids > 4 then
            block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                detail = "more distinct port-bound item flows than machine faces for " .. tostring(block.id)}
        elseif not face_layout then
            -- A horizontal strip exposes only its top and bottom faces to every machine. More than two flows
            -- therefore cannot be made perimeter-safe for all members; the caller must try a different
            -- partition. Do not manufacture a logical side and leave the hand on the old shared bottom row.
            --machine_y is no longer required to be 0 here: it is exactly 1 whenever a hand will use the
            --top face, which is the condition that makes that face usable. Demanding 0 and insetting the
            --row are contradictory, and holding both refused every strip that needed a top face.
            if #flow_ids > 2 or #bottom_rows > 0 then
                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                    detail = "more port-bound item flows than perimeter faces for " .. tostring(block.id)}
            else
                block.face_by_flow = {}
                block.face_by_machine = {}
                for _, machine in ipairs(block.machines) do block.face_by_machine[machine.id] = {} end
                for index, flow_id in ipairs(flow_ids) do
                    local side = index == 1 and "top" or "bottom"
                    block.face_by_flow[flow_id] = side
                    for machine_id, _ in pairs(flow_machines[flow_id]) do
                        set_face(machine_id, flow_id, side)
                    end
                end
            end
        else
            local ordered = {}
            for _, flow_id in ipairs(flow_ids) do
                local members, interior = {}, false
                for machine_id, machine in pairs(flow_machines[flow_id]) do
                    members[#members + 1] = machine
                    local index = machine_indices[machine_id]
                    if index ~= 1 and index ~= #block.machines then interior = true end
                end
                ordered[#ordered + 1] = {flow_id = flow_id, members = members, interior = interior}
            end
            table.sort(ordered, function(a, b)
                if a.interior ~= b.interior then return a.interior end
                if #a.members ~= #b.members then return #a.members > #b.members end
                return tostring(a.flow_id) < tostring(b.flow_id)
            end)

            local horizontal = {}
            for _, entry in ipairs(ordered) do
                if entry.interior then horizontal[#horizontal + 1] = entry end
            end
            for _, entry in ipairs(ordered) do
                local already = false
                for _, selected in ipairs(horizontal) do if selected == entry then already = true; break end end
                if not already and #horizontal < 2 then horizontal[#horizontal + 1] = entry end
            end
            if #horizontal > 2 then
                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                    detail = "more port-bound item flows need long machine faces than " .. tostring(block.id)}
            else
                local side_by_flow = {}
                for index, entry in ipairs(horizontal) do side_by_flow[entry.flow_id] = index == 1 and "left" or "right" end
                local vertical = {}
                for _, entry in ipairs(ordered) do
                    if side_by_flow[entry.flow_id] == nil then vertical[#vertical + 1] = entry end
                end
                local top_available = machine_y == 1
                local bottom_available = #bottom_rows == 0
                local vertical_sides = {}
                for _, entry in ipairs(vertical) do
                    local needs_top, needs_bottom = false, false
                    if #block.machines == 1 then
                        local side
                        if top_available and vertical_sides.top == nil then side = "top"
                        elseif bottom_available and vertical_sides.bottom == nil then side = "bottom" end
                        if side == nil then
                            block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                                detail = "no free machine face is on the block perimeter for " .. tostring(entry.flow_id)}
                        else
                            entry.endpoint_side = side
                            vertical_sides[side] = entry.flow_id
                        end
                    else
                        for _, machine in ipairs(entry.members) do
                            local index = machine_indices[machine.id]
                            if index == 1 then needs_top = true
                            elseif index == #block.machines then needs_bottom = true
                            else
                                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                                    detail = "a port-bound item flow cannot reach the perimeter for " .. tostring(machine.id)}
                                break
                            end
                        end
                        if block.failure then break end
                    end
                    if needs_top and not top_available then
                        block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                            detail = "top machine face is not on the block perimeter for " .. tostring(entry.flow_id)}
                        break
                    end
                    if needs_bottom and not bottom_available then
                        block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                            detail = "bottom machine face is not on the block perimeter for " .. tostring(entry.flow_id)}
                        break
                    end
                    if #block.machines > 1 then
                        if needs_top and vertical_sides.top ~= nil and vertical_sides.top ~= entry.flow_id then
                            block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                                detail = "top machine face is claimed by two flows for " .. tostring(block.id)}
                            break
                        end
                        if needs_bottom and vertical_sides.bottom ~= nil and vertical_sides.bottom ~= entry.flow_id then
                            block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                                detail = "bottom machine face is claimed by two flows for " .. tostring(block.id)}
                            break
                        end
                        if needs_top then vertical_sides.top = entry.flow_id end
                        if needs_bottom then vertical_sides.bottom = entry.flow_id end
                    end
                end
                if not block.failure then
                    block.face_by_machine = {}
                    for _, machine in ipairs(block.machines) do block.face_by_machine[machine.id] = {} end
                    for _, entry in ipairs(horizontal) do
                        local side = side_by_flow[entry.flow_id]
                        for _, machine in ipairs(entry.members) do
                            set_face(machine.id, entry.flow_id, side)
                        end
                    end
                    for _, entry in ipairs(vertical) do
                        for _, machine in ipairs(entry.members) do
                            local index = machine_indices[machine.id]
                            local side = #block.machines == 1 and entry.endpoint_side
                                or (index == 1 and "top" or "bottom")
                            if block.face_by_machine[machine.id][entry.flow_id] ~= nil
                                or (vertical_sides[side] ~= nil and vertical_sides[side] ~= entry.flow_id) then
                                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                                    detail = "two port-bound item flows claim one machine face for " .. tostring(machine.id)}
                                break
                            end
                            set_face(machine.id, entry.flow_id, side)
                        end
                        if block.failure then break end
                    end
                end
            end
        end
    end

    if block.failure then return block end
    block.hand_face_spread = face_layout
    block.has_bottom_beacon_row = #bottom_rows > 0
    --Beacon rows are placed after the hands; a face under a beacon row has no free port tiles (round 36: two copper
    --cable hands overflowed onto a foundry's top face and their ports landed on its beacon row).
    block.has_top_beacon_row = #top_rows > 0
    -- All machines are known before any transfer is solved.  That matters for an explicit machine-to-machine
    -- obligation: the inserter at the producer and the inserter at the consumer must each see the other machine
    -- as a real endpoint, even when the producer appears first in step order.
    for _, spec in ipairs(machine_specs) do
        local machine = machines_by_id[spec.id]
        if row_layout then
            local groups = row_hand_groups(spec.step, flows)
            for index, hand in ipairs(groups) do
                local input_hand = hand.role == "input"
                local hx = machine.x + math.floor((machine.w - 1) / 2)
                local hy = input_hand and machine.y - 1 or machine.y + machine.h
                local id = member_id("inserter", spec.step.step_id, machine.ordinal, hand.role .. ":" .. tostring(index))
                local hand_name = inserter_size(catalog, input and input.inserter)
                local hand_member = {id=id,kind="inserter",type="inserter",name=hand_name,
                    step_id=spec.step.step_id,machine_id=machine.id,role=hand.role,flow_ids=list_copy(hand.flow_ids),
                    flow_id=#hand.flow_ids==1 and hand.flow_ids[1] or nil,
                    port_id=(input_hand and "row:in:" or "row:out:") .. tostring(hand.flow_ids[1]),
                    x=hx,y=hy,w=1,h=1,
                    --Both hands move items south in the block frame (top belt -> machine -> bottom belt); the
                    --internal dir names that movement (serialize flips it at the publish boundary).
                    dir=SOUTH,
                    pickup_position={x=hx+0.5,y=(input_hand and machine.y-2 or machine.y+machine.h-1)+0.5},
                    drop_position={x=hx+0.5,y=(input_hand and machine.y or machine.y+machine.h+1)+0.5},
                    port_bound=true,flow_entries=list_copy(hand.ports),_hand_key=hand.key}
                block.inserters[#block.inserters+1]=hand_member
            end
        else append_inserters(block, spec.step, machine, catalog, input, flows) end
    end

    -- The bottom machine face is the shared perimeter face for external item hands.  Refuse an overfull face
    -- after ordinary reach has had first refusal, so an actually unreachable catalog still reports IG9's named
    -- inserter-reach failure rather than being relabelled by this layout guard.
    if not block.failure and not face_layout then
        local _, inserter_w = inserter_size(catalog, input and input.inserter)
        local bound_by_machine = {}
        for _, inserter in ipairs(block.inserters) do
            if inserter.port_bound then
                bound_by_machine[inserter.machine_id] = (bound_by_machine[inserter.machine_id] or 0) + 1
            end
        end
        for _, machine in ipairs(block.machines) do
            local bound = bound_by_machine[machine.id] or 0
            local face_columns = math.floor(machine.w / math.max(1, inserter_w))
            if bound > face_columns then
                block.failure = {name = "inserter-face", code = "BP_P_NO_FIT",
                    detail = "more port-bound item flows than face columns for " .. tostring(machine.id)}
                break
            end
        end
    end
    local has_port_bound_inserter = false
    for _, inserter in ipairs(block.inserters) do
        if inserter.port_bound then has_port_bound_inserter = true; break end
    end
    if not block.failure and has_port_bound_inserter and #bottom_rows > 0 and not row_layout then
        block.failure = {name = "beacon-face", code = "BP_P_NO_FIT",
            detail = "bottom beacon row claims the port-bound inserter face"}
    end

    -- Inserter rows belonging to different machines have disjoint x ranges because machine_specs reserves the
    -- widest inserter footprint for each machine strip.  Rows belonging to one machine were accumulated above,
    -- so variable inserter heights cannot overlap either.
    local inserter_bottom = machine_y + max_machine_h
    for _, machine in ipairs(block.machines) do
        inserter_bottom = math.max(inserter_bottom, machine.y + machine.h)
    end
    for _, inserter in ipairs(block.inserters) do
        inserter_bottom = math.max(inserter_bottom, inserter.y + inserter.h)
    end
    for _, inserter in ipairs(block.inserters) do
        block.members[#block.members + 1] = inserter
    end

    --No gap below the inserters. Supply reach is measured from the beacon CENTRE, so one spare tile puts the
    --bottom row's supply half a tile short of the machine above it and the whole row covers nothing -- which
    --is why a one-beacon requirement was paying for four beacons and covering with two.
    local bottom_y = inserter_bottom
    local bottom_row_y = bottom_y
    if row_layout then
        -- Output hand, output belt, then beacon: all hand and belt cells stay clear.
        bottom_row_y = machine_y + max_machine_h + 2
    end
    for _, row in ipairs(bottom_rows) do
        row.y = bottom_row_y
        bottom_row_y = bottom_row_y + row.h + 1
    end

    --Anchored at the machine strip, never centred in a width the row itself sets. Centring made the block
    --widen as the row grew, which re-centred the row and moved beacons AWAY from the machine that still
    --needed one, so coverage was not monotone in row.count and the old loop could never converge.
    local function row_x(row)
        return face_layout and machine_x0 or 0
    end

    local function required_count(machine, group)
        local step
        for _, candidate in ipairs(steps) do
            if candidate.step_id == machine.step_id then step = candidate; break end
        end
        for _, entry in ipairs(step and step._groups or {}) do
            if entry.signature == group.signature then return entry.count_per_machine end
        end
        return 0
    end

    local function prospective_beacon(row, index)
        return {x = row_x(row) + (index - 1) * row.w, y = row.y, w = row.w, h = row.h}
    end

    --Beacon positions are derived from real coverage, never discovered by trial and never assumed.
    --
    --The origin domain is finite and known before anything is placed: a row anchored at x = 0 can hold a
    --beacon at every multiple of its own width up to the far edge of the machine strip. That list is the
    --whole domain. Choosing from it is a measurement, not a search.
    --
    --Two earlier shapes were both wrong. The original added one beacon at a time, up to 512 times, always to
    --the side with FEWER hits; when that side could not reach the machine vertically at all, every addition
    --was wasted and the block inflated without bound -- 518 beacons and 2059 tiles on the player's
    --casting-iron block, still 2 of 3 covered. Horizontal additions never cure a vertical miss. Replacing it
    --with a pure span count went too far the other way: it spaced beacons by their own WIDTH, ignoring that
    --supply reach is much wider, so two machines that one beacon already covers were given four.
    --
    --So: start from zero, and add only a beacon that reduces a real deficit. Each pass takes the position
    --covering the most still-deficient machines, and stops as soon as no remaining position helps any of
    --them. A machine left deficient keeps its deficit; the coverage check below reports it honestly.
    local function row_origins(row)
        --The domain reaches one supply width PAST the machine strip, never only the strip. Supply is measured
        --from the beacon centre, so a beacon standing beyond the last machine still reaches it -- and a
        --machine wanting three beacons on a strip only two beacons wide has nowhere else to get the third.
        local reach = math.max(0, math.ceil(finite(row.group.supply_w, 0)))
        local span = math.max(1, machine_x0 + machine_w + reach)
        local limit = math.max(1, math.ceil(span / row.w))
        local origins = {}
        for index = 1, limit do origins[index] = (index - 1) * row.w end
        return origins
    end

    local function place_row(row)
        local group = row.group
        local deficit, order = {}, {}
        for _, machine in ipairs(block.machines) do
            local need = required_count(machine, group)
            for _, previous in ipairs(beacon_row_specs) do
                if previous == row then break end
                if previous.group.signature == group.signature then
                    for _, x in ipairs(previous.positions or {}) do
                        local spec = machine_specs_by_id[machine.id].machine_spec
                        if need > 0 and covers({x = row_x(previous) + x, y = previous.y,
                            w = previous.w, h = previous.h}, machine, spec, group.supply_w, group.supply_h) then
                            need = need - 1
                        end
                    end
                end
            end
            if need > 0 then deficit[machine.id] = need; order[#order + 1] = machine end
        end
        row.positions = {}
        if #order == 0 then row.count = 0 return end
        local origins, taken = row_origins(row), {}
        while true do
            local best_x, best_gain, best_index = nil, 0, nil
            for index, origin_x in ipairs(origins) do
                if not taken[index] then
                    local gain = 0
                    for _, machine in ipairs(order) do
                        if deficit[machine.id] > 0 then
                            local spec = machine_specs_by_id[machine.id].machine_spec
                            if covers({x = origin_x, y = row.y, w = row.w, h = row.h}, machine, spec,
                                group.supply_w, group.supply_h) then
                                gain = gain + 1
                            end
                        end
                    end
                    if gain > best_gain then best_x, best_gain, best_index = origin_x, gain, index end
                end
            end
            if best_index == nil then break end
            taken[best_index] = true
            row.positions[#row.positions + 1] = best_x
            for _, machine in ipairs(order) do
                if deficit[machine.id] > 0 then
                    local spec = machine_specs_by_id[machine.id].machine_spec
                    if covers({x = best_x, y = row.y, w = row.w, h = row.h}, machine, spec,
                        group.supply_w, group.supply_h) then
                        deficit[machine.id] = deficit[machine.id] - 1
                    end
                end
            end
        end
        table.sort(row.positions)
        row.count = #row.positions
    end
    for _, row in ipairs(beacon_row_specs) do place_row(row) end

    --The machine strip starts at machine_x0, so the block is that offset wider than the strip itself.
    --Leaving it out let a machine and its inserters end outside block.w, and the validator then saw a member
    --sticking out of its own placed envelope.
    w = math.max(1, machine_x0 + machine_w + (face_layout and 1 or 0), rows_width(), input_count,
        output_count, input_count + output_count)

    local group_beacon_indices = {}
    for _, row in ipairs(beacon_row_specs) do
        local group = row.group
        local placed_row_x = row_x(row)
        local required = {}
        for _, machine in ipairs(block.machines) do
            local step = nil
            for _, candidate in ipairs(steps) do if candidate.step_id == machine.step_id then step = candidate break end end
            for _, step_group_entry in ipairs(step and step._groups or {}) do
                if step_group_entry.signature == group.signature and step_group_entry.count_per_machine > 0 then
                    required[#required + 1] = machine.id
                    break
                end
            end
        end
        group.required_machines = required
        group_beacon_indices[group.signature] = group_beacon_indices[group.signature] or 0
        for beacon_index = 1, row.count do
            group_beacon_indices[group.signature] = group_beacon_indices[group.signature] + 1
            local beacon_x = placed_row_x + ((row.positions or {})[beacon_index] or (beacon_index - 1) * row.w)
            local beacon = {
                --A beacon group signature describes a loadout, not a place: two blocks sharing one loadout
                --produced two beacons with one id, and every reader that indexes entities by id then saw one
                --beacon standing in two places. The block owns its members, so the block belongs in the id.
                id = member_id("beacon", tostring(block.id or block.block_id) .. "|" .. tostring(group.signature),
                    group_beacon_indices[group.signature]),
                kind = "beacon", type = "beacon", name = group.name, quality = group.quality,
                signature = group.signature, group_signature = group.signature,
                has_speed_module = group.has_speed_module, modules = list_copy(group.modules),
                x = beacon_x, y = row.y, w = row.w, h = row.h,
                supply_w = group.supply_w, supply_h = group.supply_h,
            }
            local covered = {}
            for _, machine_id in ipairs(required) do
                for _, machine in ipairs(block.machines) do
                    local machine_spec = machine_specs_by_id[machine.id].machine_spec
                    if machine.id == machine_id and covers(beacon, machine, machine_spec,
                        group.supply_w, group.supply_h) then
                        covered[#covered + 1] = machine_id
                        break
                    end
                end
            end
            beacon.required_for = covered
            beacon.covered_members = list_copy(covered)
            beacon.member_ids = list_copy(covered)
            beacon.members = list_copy(covered)
            block.beacons[#block.beacons + 1] = beacon
            block.members[#block.members + 1] = beacon
            block.physical_beacon_count = block.physical_beacon_count + 1
        end
    end

    -- A row is allowed to cast farther than the machine that motivated it, but a beacon that can be removed
    -- without lowering any configured count is not allowed to survive.  Test the physical influence again after
    -- the whole block is assembled: per-row placement alone cannot see that a second row is covered by the first.
    local function requirement_for(machine, signature)
        for _, step in ipairs(steps) do
            if step.step_id == machine.step_id then
                for _, group in ipairs(step._groups or {}) do
                    if group.signature == signature then return group.count_per_machine end
                end
            end
        end
        return 0
    end

    local function covered_by(beacon, machine)
        local spec = machine_specs_by_id[machine.id] and machine_specs_by_id[machine.id].machine_spec
        return covers(beacon, machine, spec, beacon.supply_w, beacon.supply_h)
    end

    local function redundant(candidate)
        for _, machine in ipairs(block.machines) do
            for _, group in ipairs(ordered_groups) do
                local required = requirement_for(machine, group.signature)
                if required > 0 then
                    local count = 0
                    for _, beacon in ipairs(block.beacons) do
                        if beacon ~= candidate and beacon.signature == group.signature and covered_by(beacon, machine) then
                            count = count + 1
                        end
                    end
                    if count < required then return false end
                end
            end
        end
        return true
    end

    local changed = true
    while changed do
        changed = false
        for index, beacon in ipairs(block.beacons) do
            if redundant(beacon) then
                table.remove(block.beacons, index)
                for member_index, member in ipairs(block.members) do
                    if member == beacon then table.remove(block.members, member_index); break end
                end
                changed = true
                break
            end
        end
    end
    block.physical_beacon_count = #block.beacons

    -- Re-publish the complete physical influence after pruning.  In particular, never blank covered_members to
    -- make a load-bearing beacon look removable: extra influence is legal and remains visible to validation.
    for _, beacon in ipairs(block.beacons) do
        local covered_all, required = {}, {}
        for _, machine in ipairs(block.machines) do
            if covered_by(beacon, machine) then
                covered_all[#covered_all + 1] = machine.id
                if requirement_for(machine, beacon.signature) > 0 then required[#required + 1] = machine.id end
            end
        end
        beacon.required_for = required
        beacon.covered_members = list_copy(covered_all)
        beacon.member_ids = list_copy(covered_all)
        beacon.members = list_copy(covered_all)
    end

    -- The inset rows belong to the block too.  They are placed after machines and never share an occupancy
    -- cell with a machine, another inserter, or a beacon.
    local max_inserter_bottom = inserter_bottom
    for _, inserter in ipairs(block.inserters) do
        max_inserter_bottom = math.max(max_inserter_bottom, inserter.y + inserter.h)
    end
    block.w = w
    block.h = math.max(machine_y + max_machine_h, max_inserter_bottom, beacon_rows_h, bottom_row_y - 1)
    block.envelope = {x = 0, y = 0, w = block.w, h = block.h}
    block.beacon_count = block.physical_beacon_count
    block_ports(block, steps, ports, flows)
    if row_layout then
        block.ports = {}
        local in_hands, out_hands, xs = {}, {}, {}
        for _, hand in ipairs(block.inserters) do
            if hand.role == "input" then in_hands[#in_hands + 1] = hand else out_hands[#out_hands + 1] = hand end
        end
        table.sort(in_hands, function(a,b) return a.x < b.x end)
        table.sort(out_hands, function(a,b) return a.x < b.x end)
        local flows_in, flows_out = {}, {}
        for _, p in ipairs(steps[1].inputs or {}) do if not flow_is_fluid(p, flows) then flows_in[#flows_in+1] = p.flow_id or p.full_name end end
        for _, p in ipairs(steps[1].outputs or {}) do if not flow_is_fluid(p, flows) then flows_out[#flows_out+1] = p.flow_id or p.full_name end end
        table.sort(flows_in); table.sort(flows_out)
        --Near belt: the first two input flows. Far belt above the near belt: the third.
        local far_in = {}
        if flows_in[3] then far_in[1] = flows_in[3] end
        if #flows_in > 2 then flows_in = {flows_in[1], flows_in[2]} end
        local pickup_y, drop_y = machine_y - 2, machine_y + max_machine_h + 1
        local first_x = block.machines[1].x + math.floor((block.machines[1].w - 1) / 2)
        local last_x = block.machines[#block.machines].x + math.floor(block.machines[#block.machines].w / 2)
        local tiles_in, tiles_out = {}, {}
        for x = first_x - 1, last_x do tiles_in[#tiles_in+1] = {x=x,y=pickup_y} end
        --The output run reaches the block's right edge so its port lies on the boundary (attach_dx == w).
        local row_w = math.max(block.w, last_x + 2)
        for x = first_x, row_w - 1 do tiles_out[#tiles_out+1] = {x=x,y=drop_y} end
        local feeds = {}
        if #flows_in == 1 then
            --One input flow needs no lane split: its belt enters the head straight from behind (a straight or a
            --curve), never by a side-load round the head (docs/contracts/row_block.md §Rear port).
            local fid = flows_in[1]
            block.ports[#block.ports+1] = {port_id="row:in:"..fid, row_port=true, rear=true, role="in",kind="item",
                flow_id=fid,flow_ids={fid},step_id=steps[1].step_id,attach_dx=first_x-2,attach_dy=pickup_y,
                normal_dir=EAST,travel_dir=EAST,member_id=block.machines[1].id}
        else
            for i, fid in ipairs(flows_in) do
                local side = i == 1 and -1 or 1
                feeds[#feeds+1] = {flow_id=fid, side_tile={x=first_x-1,y=pickup_y+side}, travel_dir=side == -1 and SOUTH or NORTH}
                block.ports[#block.ports+1] = {port_id="row:in:"..fid, row_port=true, role="in",kind="item",flow_id=fid,step_id=steps[1].step_id,
                    attach_dx=first_x-1,attach_dy=pickup_y+side,normal_dir=side == -1 and SOUTH or NORTH,
                    travel_dir=side == -1 and SOUTH or NORTH,member_id=block.machines[1].id}
            end
            --The rear port carries every input flow on one already lane-split belt. It has no scalar flow_id, so
            --first routing never uses it; route's merge trial (round 27) may (docs/contracts/row_block.md §Rear port).
            block.ports[#block.ports+1] = {port_id="row:in:rear", row_port=true, rear=true, role="in",kind="item",
                flow_ids=list_copy(flows_in),step_id=steps[1].step_id,attach_dx=first_x-2,attach_dy=pickup_y,
                normal_dir=EAST,travel_dir=EAST,member_id=block.machines[1].id}
        end
        local outflow = flows_out[1]
        block.ports[#block.ports+1] = {port_id="row:out:"..tostring(outflow),row_port=true,role="out",kind="item",flow_id=outflow,
            step_id=steps[1].step_id,attach_dx=row_w,attach_dy=drop_y,normal_dir=WEST,travel_dir=EAST,
            member_id=block.machines[#block.machines].id}
        block.belt_runs = {
            {role="in",flows=flows_in,tiles=tiles_in,dir=EAST,head={x=first_x-1,y=pickup_y},feeds=feeds,hand_ids=(function() local a={} for _,h in ipairs(in_hands) do a[#a+1]=h.id end return a end)()},
            {role="out",flows=flows_out,tiles=tiles_out,dir=EAST,port={x=row_w,y=drop_y,travel_dir=EAST},hand_ids=(function() local a={} for _,h in ipairs(out_hands) do a[#a+1]=h.id end return a end)()},
        }
        --Far belts (docs/contracts/row_block.md §Far belt). A long hand stands in the same hand row as the plain
        --hand, one column to its right, and reaches two tiles: over the near belt to the far belt, and two tiles
        --into its machine. The far belt above the row travels WEST so its head and side feeds sit right of the
        --row, clear of the near belt's own feeds; the far belt below the output belt travels EAST from the left.
        local long_facts = catalog and catalog.long_inserter or {}
        local long_name = long_facts.name or catalog_name(catalog, "long-handed-inserter")
        local far_w = 0
        local function add_far(far_flows, above)
            if #far_flows == 0 then return end
            local far_y = above and pickup_y - 1 or drop_y + 1
            local long_x = {}
            for _, machine in ipairs(block.machines) do
                long_x[#long_x + 1] = machine.x + math.min(machine.w - 1, math.floor((machine.w - 1) / 2) + 1)
            end
            local travel = above and WEST or EAST
            local head_x = above and long_x[#long_x] + 1 or first_x - 1
            local tiles = {}
            if above then
                for x = head_x, long_x[1], -1 do tiles[#tiles + 1] = {x = x, y = far_y} end
            else
                for x = head_x, long_x[#long_x] do tiles[#tiles + 1] = {x = x, y = far_y} end
            end
            local far_feeds = {}
            local run = {role = "in", far = true, flows = list_copy(far_flows), tiles = tiles, dir = travel,
                head = {x = head_x, y = far_y}, feeds = far_feeds, hand_ids = {}}
            if #far_flows == 1 then
                local fid = far_flows[1]
                block.ports[#block.ports + 1] = {port_id = "row:in:" .. fid, row_port = true, rear = true, far = true,
                    role = "in", kind = "item", flow_id = fid, flow_ids = {fid}, step_id = steps[1].step_id,
                    attach_dx = above and head_x + 1 or head_x - 1, attach_dy = far_y,
                    normal_dir = travel, travel_dir = travel, member_id = block.machines[1].id}
            else
                for i, fid in ipairs(far_flows) do
                    --feeds[1] comes from the left of travel: north of an EAST belt, south of a WEST belt.
                    local side = (i == 1) == (travel == EAST) and -1 or 1
                    local into = side == -1 and SOUTH or NORTH
                    far_feeds[#far_feeds + 1] = {flow_id = fid, side_tile = {x = head_x, y = far_y + side}, travel_dir = into}
                    block.ports[#block.ports + 1] = {port_id = "row:in:" .. fid, row_port = true, far = true, role = "in",
                        kind = "item", flow_id = fid, step_id = steps[1].step_id, attach_dx = head_x,
                        attach_dy = far_y + side, normal_dir = into, travel_dir = into, member_id = block.machines[1].id}
                end
            end
            for index, machine in ipairs(block.machines) do
                local hx = long_x[index]
                local hy = above and machine.y - 1 or machine.y + machine.h
                local hid = member_id("inserter", machine.step_id, machine.ordinal or index,
                    "input:long:" .. (above and "top" or "bottom"))
                block.inserters[#block.inserters + 1] = {id = hid, kind = "inserter", type = "inserter", name = long_name,
                    step_id = machine.step_id, machine_id = machine.id, role = "input", long = true,
                    flow_ids = list_copy(far_flows), flow_id = #far_flows == 1 and far_flows[1] or nil,
                    port_id = "row:in:" .. tostring(far_flows[1]), x = hx, y = hy, w = 1, h = 1,
                    dir = above and SOUTH or NORTH,
                    pickup_position = {x = hx + 0.5, y = far_y + 0.5},
                    drop_position = {x = hx + 0.5, y = (above and machine.y + 1 or machine.y + machine.h - 2) + 0.5},
                    pickup_offset = point(long_facts.pickup_offset) or {x = 0, y = 2},
                    drop_offset = point(long_facts.drop_offset) or {x = 0, y = -2},
                    port_bound = true, flow_entries = {}}
                --Groups.materialize places block.members, not block.inserters: a hand missing here never
                --reaches the layout (the synthetic 3-input sheet lost all four long hands, 2026-09-24).
                block.members[#block.members + 1] = block.inserters[#block.inserters]
                run.hand_ids[#run.hand_ids + 1] = hid
            end
            block.belt_runs[#block.belt_runs + 1] = run
            far_w = math.max(far_w, head_x + 2)
        end
        add_far(far_in, true)
        --A far belt head right of the row widens the block; the output run must still end on the block edge
        --(its port lies on the boundary, attach_dx == w).
        if far_w > row_w then
            local out_run = block.belt_runs[2]
            for x = row_w, far_w - 1 do out_run.tiles[#out_run.tiles + 1] = {x = x, y = drop_y} end
            out_run.port = {x = far_w, y = drop_y, travel_dir = EAST}
            for _, port in ipairs(block.ports) do
                if port.role == "out" and port.row_port then port.attach_dx = far_w end
            end
            row_w = far_w
        end
        block.row.machines = #block.machines
        block.row.first_x, block.row.last_x = first_x, last_x
        block.w = math.max(row_w, far_w); block.h = math.max(block.h,drop_y+1)
        block.envelope = {x = 0, y = 0, w = block.w, h = block.h}
    end

    -- A speed beacon is never allowed to claim a quality machine, even if a malformed plan uses a speed
    -- group on that step. Keep the physical influence record intact: removing covered_members while the beacon
    -- remains placed only makes bookkeeping look safe. The candidate is rejected and the caller can try a split.
    for _, beacon in ipairs(block.beacons) do
        if beacon.has_speed_module then
            for _, machine_id in ipairs(beacon.covered_members) do
                local machine
                for _, candidate in ipairs(block.machines) do if candidate.id == machine_id then machine = candidate break end end
                if machine and machine.forbids_speed_beacon then block.invalid_coverage = true end
            end
        end
    end
    for _, machine in ipairs(block.machines) do
        block.beacon_coverage[machine.id] = {}
        for _, beacon in ipairs(block.beacons) do
            local required = false
            for _, member_id_value in ipairs(beacon.covered_members) do
                if member_id_value == machine.id then required = true break end
            end
            if required then block.beacon_coverage[machine.id][#block.beacon_coverage[machine.id] + 1] = beacon.id end
        end
    end
    for _, machine in ipairs(block.machines) do
        for _, group in ipairs(ordered_groups) do
            local required = 0
            local step
            for _, candidate in ipairs(steps) do if candidate.step_id == machine.step_id then step = candidate break end end
            for _, entry in ipairs(step and step._groups or {}) do
                if entry.signature == group.signature then required = entry.count_per_machine break end
            end
            if required > 0 then
                local got = 0
                for _, beacon_id in ipairs(block.beacon_coverage[machine.id]) do
                    for _, beacon in ipairs(block.beacons) do
                        if beacon.id == beacon_id and beacon.signature == group.signature then got = got + 1 end
                    end
                end
                if got < required then block.invalid_coverage = true end
            end
        end
    end
    table.sort(block.members, function(a, b) return a.id < b.id end)
    table.sort(block.machines, function(a, b) return a.id < b.id end)
    table.sort(block.beacons, function(a, b) return a.id < b.id end)
    table.sort(block.inserters, function(a, b) return a.id < b.id end)
    table.sort(block.ports, function(a, b) return tostring(a.port_id) < tostring(b.port_id) end)
    -- Keep explicit recipe-aware buffer facts beside the block in its local frame.  Recipes live on
    -- steps (including furnaces, whose blueprint entities intentionally have no recipe field).
    local step_by_id = {}
    for _, step in ipairs(steps) do step_by_id[step.step_id] = step end
    block.buffer_zones = {}
    for _, machine in ipairs(block.machines) do
        local step = step_by_id[machine.step_id]
        if step then
            block.buffer_zones[#block.buffer_zones + 1] = {
                x = machine.x, y = machine.y, w = machine.w, h = machine.h,
                ring = Buffer.ring(catalog, step.recipe) + math.max(0, math.floor(finite(input and input.ring_bump, 0))),
                key = Buffer.key(machine.name, step.recipe),
            }
        end
    end
    table.sort(block.buffer_zones, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)
    for i = 1, #block.buffer_zones do
        local a = block.buffer_zones[i]
        for j = i + 1, #block.buffer_zones do
            local b = block.buffer_zones[j]
            assert(not Buffer.conflict({rect = a, ring = a.ring, key = a.key},
                {rect = b, ring = b.ring, key = b.key}), "group block contains conflicting machine buffer zones")
        end
    end
    return block
end

local function relevant_ports(block_steps, ports, flows)
    local step_ids = {}
    for _, step in ipairs(block_steps) do step_ids[step.step_id] = true end
    local result = {}
    for _, port in ipairs(ports or {}) do
        if port.step_id and step_ids[port.step_id] then result[#result + 1] = port end
    end
    return result
end

local function step_ports(steps, catalog, flows)
    local ports = {}
    for _, step in ipairs(steps) do
        for _, entry in ipairs(step.inputs or {}) do
            if entry.external ~= false then
                local port = copy(entry)
                --Contract 27.4: a port id must be unique inside the candidate. The old flow-only form
                --"in:"..flow was minted here AND, byte for byte, by logic/bp/plan.lua:646 for the perimeter
                --terminal of the same flow. logic/bp/validate.lua:1740 looks bindings up in a single-valued
                --port_by_id, so one shadowed the other and check_ports judged the binding against the wrong
                --role -- six BP_V_PORT_EDGE_WRONG records "binding source has role in" on player-am2-chain.
                --Qualifying by step makes the two id spaces disjoint; a perimeter id never carries a step.
                --tests/test_blueprint_physical_contract.lua:130-136 already asserts this exact shape.
                port.port_id = entry.port_id
                    or (tostring(step.step_id) .. ":in:" .. tostring(entry.flow_id or entry.full_name))
                port.role = "in"
                port.kind = entry.kind or (flow_is_fluid(entry, flows) and "fluid" or "item")
                port.is_fluid = port.kind == "fluid" or entry.is_fluid == true
                port.flow_id = entry.flow_id or entry.full_name
                port.rate_per_second = entry.rate_per_second
                port.step_id = step.step_id
                port.machine = step.machine
                if port.is_fluid then
                    local facts = fluid_connection(catalog, step, entry, "input")
                    if facts then
                        port.connection = facts.connection
                        port.fluidbox_index = facts.box_index
                        port.connection_index = facts.connection_index
                    end
                end
                ports[#ports + 1] = port
            end
        end
        for _, entry in ipairs(step.outputs or {}) do
            if entry.external ~= false then
                local port = copy(entry)
                --Contract 27.4, the output twin of the rule above.
                port.port_id = entry.port_id
                    or (tostring(step.step_id) .. ":out:" .. tostring(entry.flow_id or entry.full_name))
                port.role = "out"
                port.kind = entry.kind or (flow_is_fluid(entry, flows) and "fluid" or "item")
                port.is_fluid = port.kind == "fluid" or entry.is_fluid == true
                port.flow_id = entry.flow_id or entry.full_name
                port.rate_per_second = entry.rate_per_second
                port.step_id = step.step_id
                port.machine = step.machine
                if port.is_fluid then
                    local facts = fluid_connection(catalog, step, entry, "output")
                    if facts then
                        port.connection = facts.connection
                        port.fluidbox_index = facts.box_index
                        port.connection_index = facts.connection_index
                    end
                end
                ports[#ports + 1] = port
            end
        end
    end
    return ports
end

local function make_candidates_once(input, work)
    --TRI-STATE, and that is load-bearing: `nil` means "use the production switch", `true` forces the feature
    --on, `false` forces it OFF.  The `and ... or previous` form below could only ever force it ON, so once
    --the production flag was on, HE1 in tests/test_hand_economy.lua asked for "switch off", read the global
    --instead, and compared the paired twenty-two against the unpaired twenty-six.  Measured 2026-09-22 on
    --legalcopilot-dev.  `forced_multi_flow_hands` stays in the call so tools/lane_mutate.sh:175 can still
    --mutate it for the `shared-hand-off` mutant.
    local previous_multi_flow_hands = multi_flow_hands
    local forced = input and input._force_multi_flow_hands
    if forced ~= nil then multi_flow_hands = forced == true and forced_multi_flow_hands(input) end
    -- Row blocks own the two-lane belt contract, so eligible grouped steps must construct paired hands even
    -- while the legacy multi-flow switch remains off for all other layouts.
    if forced == nil then multi_flow_hands = true end
    local prepared = work ~= nil
    if not work then
    local _, catalog, steps, flows = normalize_plan(input)
    local ports = step_ports(steps, catalog, flows)
    -- A multi-machine step with three or more distinct item flows cannot expose every machine's hand on a
    -- rectangle perimeter: only the two long sides are shared by the interior machines. Split those physical
    -- instances before partitioning, while retaining the original step id so plan accounting and rates remain
    -- aggregate facts. The fragment ordinal only makes the physical member id unique across its blocks.
    local layout_steps = {}
    for _, step in ipairs(steps) do
        local item_flows = {}
        for _, entry in ipairs(step.inputs or {}) do
            if not flow_is_fluid(entry, flows) then item_flows[entry.flow_id or entry.full_name] = true end
        end
        for _, entry in ipairs(step.outputs or {}) do
            if not flow_is_fluid(entry, flows) then item_flows[entry.flow_id or entry.full_name] = true end
        end
        local distinct = 0
        for _ in pairs(item_flows) do distinct = distinct + 1 end
        local item_inputs, item_outputs = 0, 0
        for _, p in ipairs(step.inputs or {}) do if not flow_is_fluid(p, flows) then item_inputs = item_inputs + 1 end end
        for _, p in ipairs(step.outputs or {}) do if not flow_is_fluid(p, flows) then item_outputs = item_outputs + 1 end end
        local hand_capacity = finite(catalog and catalog.inserter and catalog.inserter.items_per_second)
        local needs_individual_blocks = false
        if hand_capacity and hand_capacity > 0 and step.machine_count > 1 then
            for _, role in ipairs({"inputs", "outputs"}) do
                for _, entry in ipairs(step[role] or {}) do
                    if not flow_is_fluid(entry, flows)
                        and math.ceil(flow_entry_rate(entry) / step.machine_count / hand_capacity - 1e-9) > 1 then
                        needs_individual_blocks = true
                    end
                end
            end
        end
        local row_possible = item_outputs <= 1 and item_inputs <= 3
        if step.machine_count > 1 and (needs_individual_blocks or (distinct > 2 and not row_possible)) then
            for ordinal = 1, step.machine_count do
                local fragment = copy(step)
                fragment.machine_count = 1
                fragment._physical_ordinal = ordinal
                fragment._rate_machine_count = step.machine_count
                fragment._force_block = true
                layout_steps[#layout_steps + 1] = fragment
            end
        else
            local physical = copy(step)
            physical._rate_machine_count = step.machine_count
            layout_steps[#layout_steps + 1] = physical
        end
    end
    local buckets = {}
    for _, step in ipairs(layout_steps) do
        local target
        for _, bucket in ipairs(buckets) do
            if step_can_join(step, bucket[1]) then target = bucket; break end
        end
        if target then target[#target + 1] = step else buckets[#buckets + 1] = {step} end
    end
    work = {catalog = catalog, flows = flows, ports = ports, buckets = buckets,
        bucket_index = 1, blocks = {}, failures = {}}
    end
    if not prepared then
        multi_flow_hands = previous_multi_flow_hands
        return nil, nil, work
    end
    local group = work.buckets[work.bucket_index]
    if group then
        local ids = {}
        for _, step in ipairs(group) do
            ids[#ids + 1] = tostring(step.step_id) .. (step._physical_ordinal and ("#" .. tostring(step._physical_ordinal)) or "")
        end
        local block = build_block(group, work.catalog, relevant_ports(group, work.ports, work.flows), work.flows, input, "block:" .. table.concat(ids, "+"))
        if block.invalid_coverage or block.failure then
            local machine_total = 0
            for _, step in ipairs(group) do machine_total = machine_total + math.max(1, step.machine_count or 1) end
            if block.invalid_coverage and machine_total > 1 then
                -- Shared placement can leave some machines without their requested beacon count even
                -- when each machine fits on its own. Retry the physical instances individually.
                local fragments = {}
                for _, step in ipairs(group) do
                    local count = math.max(1, step.machine_count or 1)
                    for ordinal = 1, count do
                        local fragment = copy(step)
                        fragment.machine_count = 1
                        fragment._physical_ordinal = count == 1 and step._physical_ordinal or ordinal
                        fragment._rate_machine_count = step._rate_machine_count or count
                        fragment._force_block = true
                        fragments[#fragments + 1] = {fragment}
                    end
                end
                for offset = #fragments, 1, -1 do
                    table.insert(work.buckets, work.bucket_index + offset, fragments[offset])
                end
            else
                work.failures[#work.failures + 1] = block.failure or {name="beacon-split",code="BP_P_NO_FIT",detail="configured beacon coverage cannot be split"}
            end
        else work.blocks[#work.blocks + 1] = block end
        work.bucket_index = work.bucket_index + 1
    end
    if work.bucket_index <= #work.buckets then
        multi_flow_hands = previous_multi_flow_hands
        return nil, nil, work
    end
    local candidates = {}
    if #work.failures == 0 then
        local beacon_count = 0
        for _, block in ipairs(work.blocks) do beacon_count = beacon_count + block.physical_beacon_count end
        candidates[1] = {id="one",candidate_id="one",blocks=work.blocks,physical_beacon_count=beacon_count,beacon_count=beacon_count}
    end
    multi_flow_hands = previous_multi_flow_hands
    return candidates, work.failures, nil
end

local function make_candidates(input)
    return make_candidates_once(input)
end

function Groups.begin(input)
    return {
        done = false, ok = nil, cursor = {phase = "enumerate", candidate_index = 1},
        progress = {phase = "grouping", done_units = 0, total_units = nil},
        -- Search already crosses a data-only copy boundary before this call. Retaining this immutable input
        -- reference keeps begin constant-time; candidate construction and its copy costs belong in step.
        work = {input = input or {}, candidates = nil, failures = nil, emitted = {}, build = nil,
            candidate_enumerations = 0},
    }
end

function Groups.step(state, budget)
    if state.done then return state end
    budget = budget or {ops = 1}
    local ops = finite(budget.ops, 1)
    -- Candidate construction is deferred until the budgeted step. Keep the counter on the plain-data
    -- state so callers can verify begin did not enumerate candidates.
    if ops > 0 and state.work.candidates == nil then
        local candidates, failures, build = make_candidates_once(state.work.input, state.work.build)
        state.work.build = build
        if candidates then
            state.work.candidates, state.work.failures = candidates, failures
            state.work.candidate_enumerations = #candidates
            state.progress.total_units = #candidates
            state.cursor.phase = "emit"
        end
        ops = ops - 1
    end
    while ops > 0 and state.work.candidates and state.cursor.candidate_index <= #state.work.candidates do
        local candidate = state.work.candidates[state.cursor.candidate_index]
        state.work.emitted[#state.work.emitted + 1] = candidate
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.progress.done_units = state.progress.done_units + 1
        ops = ops - 1
    end
    budget.ops = ops
    if state.work.candidates and state.cursor.candidate_index > #state.work.candidates then
        state.result = {candidates = state.work.emitted, failures = list_copy(state.work.failures)}
        state.done, state.ok = true, #state.work.emitted > 0
    end
    return state
end

function Groups.materialize(block, placement)
    placement = placement or {x = 0, y = 0, dir = NORTH}
    local px, py, dir = finite(placement.x, 0), finite(placement.y, 0), placement.dir or NORTH
    local placed = {entities = {}, ports = {}, belt_runs = {}, envelope = nil}
    local occupied = {}
    local oriented_w, oriented_h = Grid.rotate_size(block.w, block.h, dir)
    placed.envelope = {x = px, y = py, w = oriented_w, h = oriented_h, dir = dir}
    for _, member in ipairs(block.members or {}) do
        local geometry = Grid.place_member(block, {x = px, y = py, dir = dir}, member)
        local entity = copy(member)
        entity.id = "m:" .. tostring(member.id)
        if entity.machine_id then entity.machine_id = "m:" .. tostring(entity.machine_id) end
        for _, field in ipairs({"inserter_id", "pickup_target", "drop_target"}) do
            if entity[field] == member.id then entity[field] = "m:" .. tostring(entity[field]) end
        end
        for _, field in ipairs({"required_for", "covered_members", "member_ids", "members"}) do
            if type(entity[field]) == "table" then
                local references = {}
                for index, member_id_value in ipairs(entity[field]) do
                    references[index] = tostring(member_id_value):sub(1, 2) == "m:"
                        and tostring(member_id_value) or "m:" .. tostring(member_id_value)
                end
                entity[field] = references
            end
        end
        entity.x, entity.y, entity.w, entity.h, entity.dir = geometry.x, geometry.y, geometry.w, geometry.h, geometry.dir
        entity.position = {x = geometry.x + geometry.w / 2, y = geometry.y + geometry.h / 2}
        if member.kind == "inserter" then
            for _, field in ipairs({"pickup_position", "drop_position"}) do
                local local_position = point(member[field])
                if local_position then
                    local x, y = Grid.rotate_point(local_position.x, local_position.y, block.w, block.h, dir)
                    entity[field] = {x = px + x, y = py + y}
                end
            end
        end
        placed.entities[#placed.entities + 1] = entity
        occupied[#occupied + 1] = {
            x = geometry.x, y = geometry.y, w = geometry.w, h = geometry.h,
            owner = "machine:" .. tostring(block.block_id or block.id),
        }
    end
    local slots = placement.port_slots or {}
    local function slot_for(port, index)
        for _, slot in ipairs(slots) do
            if slot.index ~= nil and slot.index == index then return slot end
        end
        for _, slot in ipairs(slots) do
            if slot.port_id ~= nil and slot.port_id == port.port_id then return slot end
        end
        if slots[port.port_id] then return slots[port.port_id] end
        return nil
    end
    for index, port in ipairs(block.ports or {}) do
        local slot = slot_for(port, index)
        local source = port
        --A slot only replaces the port's own attachment when it actually HAS one. Overwriting unconditionally
        --dropped attach_dx to nil, and Grid.place_port then did arithmetic on that nil deep inside the
        --validator's port-approach check -- a crash no run ever reached while grouping still failed earlier.
        local slot_is_own = slot and slot.attach_dx == port.attach_dx and slot.attach_dy == port.attach_dy
        --A row port sits at its belt run's head or end (docs/contracts/row_block.md); a packer slot never moves it.
        if (port.inserter_id ~= nil or port.row_port) and slot and not slot_is_own then
            -- A packer override may only repeat an inserter's authored hand cell.  A synthetic fallback would
            -- sever the transport handshake, so refuse the override and retain the port's own attachment.
            slot = nil
        end
        if slot and slot.attach_dx ~= nil and slot.attach_dy ~= nil then
            source = copy(port)
            source.attach_dx, source.attach_dy = slot.attach_dx, slot.attach_dy
            source.normal_dir, source.travel_dir = slot.normal_dir, slot.travel_dir
        end
        local geometry = Grid.place_port(block, {x = px, y = py, dir = dir}, source)
        local placed_port = copy(source)
        if source.connection_position then
            local connection = point(source.connection_position)
            if connection then
                local cx, cy = Grid.rotate_point(connection.x, connection.y, block.w, block.h, dir)
                placed_port.connection_position = {x = px + cx, y = py + cy}
            end
        end
        if placed_port.member_id then placed_port.member_id = "m:" .. tostring(placed_port.member_id) end
        if dir == NORTH then
            -- In the source orientation the two representations coincide, so retain the concrete tile for
            -- callers that inspect a north-facing materialization.
            placed_port.x, placed_port.y = geometry.x, geometry.y
            placed_port.normal_dir = geometry.dir
            placed_port.dir = geometry.dir
            placed_port.travel_dir = Grid.rotate_dir(source.travel_dir or NORTH, dir)
        else
            -- The validator's edge predicate consumes attach_dx/attach_dy and normal_dir as a single frame,
            -- while Grid.place_port consumes them as the source frame.  Keep that frame coherent and let Route
            -- use its source-frame fallback (_block_w/_block_h) for the world endpoint on rotated placements.
            -- Supplying x/y here would ask the validator to rotate the already-placed block a second time.
            placed_port.normal_dir = source.normal_dir
            placed_port.dir = source.normal_dir
            placed_port.travel_dir = source.travel_dir or NORTH
        end
        --The search carries placed ports into Route, but not the materialized entity list.  Keep the exact
        --rotated member rectangles on the port so routing indexes the members themselves, not a rotated-again
        --block envelope.  This is internal layout data and never becomes a blueprint entity.
        placed_port._occupied = copy(occupied)
        placed_port._block_w, placed_port._block_h = block.w, block.h
        placed.ports[#placed.ports + 1] = placed_port
    end
    for _, run in ipairs(block.belt_runs or {}) do
        local target = copy(run)
        local function place(p)
            --A run tile is a whole cell: rotating its corner as a point shifts it by one (see Grid.place_port).
            local x,y = Grid.rotate_cell(p.x,p.y,block.w,block.h,dir)
            return {x=px+x,y=py+y}
        end
        for i,tile in ipairs(run.tiles or {}) do target.tiles[i]=place(tile) end
        if run.head then target.head=place(run.head) end
        if run.feeds then
            target.feeds={}
            for i,feed in ipairs(run.feeds) do
                target.feeds[i]={flow_id=feed.flow_id,side_tile=place(feed.side_tile),travel_dir=Grid.rotate_dir(feed.travel_dir,dir)}
            end
        end
        if run.port then
            local p=place(run.port); target.port={x=p.x,y=p.y,travel_dir=Grid.rotate_dir(run.port.travel_dir,dir)}
        end
        target.dir=Grid.rotate_dir(run.dir,dir)
        placed.belt_runs[#placed.belt_runs+1]=target
    end
    table.sort(placed.entities, function(a, b) return a.id < b.id end)
    table.sort(placed.ports, function(a, b)
        if a.inserter_id ~= nil and b.inserter_id ~= nil and a.flow_id == b.flow_id and a.role == b.role then
            return tostring(a.inserter_id) > tostring(b.inserter_id)
        end
        return tostring(a.port_id) < tostring(b.port_id)
    end)
    return placed
end

return Groups

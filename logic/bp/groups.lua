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
    local fallback
    for box_index, box in ipairs(boxes) do
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

local function group_name(group)
    return name_of(group.name or group.beacon or group.type or group.prototype) or "beacon"
end

local function group_signature(group, catalog)
    if group.signature ~= nil then return tostring(group.signature) end
    local pieces = {group_name(group), tostring(group.quality or "normal")}
    for _, module in ipairs(group_modules(group)) do
        pieces[#pieces + 1] = tostring(module.name) .. "@" .. tostring(module.quality) .. "x" .. tostring(module.count)
    end
    -- A catalog may distinguish two beacon profiles with the same prototype name.  The explicit signature
    -- remains authoritative, while this fallback is stable for the normal catalog shape.
    local entity = lookup_entity(catalog, group_name(group), "beacon")
    if entity.beacon and entity.beacon.counter then pieces[#pieces + 1] = tostring(entity.beacon.counter) end
    return table.concat(pieces, "|")
end

local function group_supply(catalog, group)
    local entity = lookup_entity(catalog, group_name(group), "beacon")
    local beacon = entity.beacon or (catalog and catalog.beacon and catalog.beacon[group_name(group)]) or {}
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
    result.machine = name_of(step.machine or step.machine_name or step.entity) or "assembling-machine-1"
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
            name = group_name(group),
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
    return name or "inserter", dimensions(catalog, name, "inserter", 1, 1)
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

local function explicit_cell(entry, keys)
    for _, key in ipairs(keys) do
        local value = point(entry and entry[key])
        if value then return cell_of(value.x), cell_of(value.y) end
    end
    return nil, nil
end

local function candidate_inserter(block, machine, role, index, iw, ih, catalog, input, source_member, target_member,
    source_cell, target_cell)
    local name = input and input.name
    local pickup_offset, drop_offset = inserter_offsets(catalog, name)
    local preferred = role == "input" and EAST or SOUTH
    local desired_x, desired_y
    if role == "input" then
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
                    if target_ok and source_ok then
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
    return Geometry.box_in_supply(machine, machine_spec, beacon_x, beacon_y, supply_w, supply_h)
end

local function append_inserters(block, step, machine, catalog, input, flows)
    local name, iw, ih = inserter_size(catalog, input and input.inserter)
    local inputs, outputs = {}, {}
    for _, port in ipairs(step.inputs or {}) do
        if not flow_is_fluid(port, flows) then inputs[#inputs + 1] = port end
    end
    for _, port in ipairs(step.outputs or {}) do
        if not flow_is_fluid(port, flows) then outputs[#outputs + 1] = port end
    end
    local function append(role, list)
        for index, port in ipairs(list) do
            local entry = {role = role, port = port}
            local source_reference = role == "input"
                and (port.source_machine_id or port.source_id or port.source_member_id or port.source)
                or (port.drain_machine_id or port.drain_id or port.drain_member_id or port.drain)
            local source_member = member_for(block, source_reference)
            local target_member = role == "input" and machine or member_for(block, source_reference)
            local transfer_source_member = source_member
            if role == "output" then transfer_source_member = machine end
            local source_x, source_y = explicit_cell(port, role == "input"
                and {"pickup_cell", "source_cell", "source_position"}
                or {"drop_cell", "drain_cell", "drain_position"})
            local target_x, target_y = explicit_cell(port, role == "input"
                and {"drop_cell", "target_cell", "target_position"}
                or {"pickup_cell", "source_cell", "source_position"})
            local source_cell = source_x ~= nil and {source_x, source_y} or nil
            local target_cell = target_x ~= nil and {target_x, target_y} or nil
            local placement = candidate_inserter(block, machine, role, index, iw, ih, catalog, input,
                transfer_source_member, target_member, source_cell, target_cell)
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
            }
        end
    end
    append("input", inputs)
    append("output", outputs)
end

local function block_ports(block, steps, ports, flows)
    local members_by_step = {}
    for _, machine in ipairs(block.machines) do
        members_by_step[machine.step_id] = members_by_step[machine.step_id] or {}
        members_by_step[machine.step_id][#members_by_step[machine.step_id] + 1] = machine
    end

    local selected = {}
    for _, port in ipairs(ports or {}) do
        local flow_id = port.flow_id or port.full_name or port.id
        local step_id = port.step_id or port.member_step_id
        if step_id and members_by_step[step_id] then
            selected[#selected + 1] = {
                port = port, flow_id = flow_id, step_id = step_id, member_id = members_by_step[step_id][1].id,
            }
        end
    end
    table.sort(selected, function(a, b)
        local aid = tostring(a.port.port_id or a.port.id or a.flow_id)
        local bid = tostring(b.port.port_id or b.port.id or b.flow_id)
        return aid < bid
    end)

    local inputs, outputs = {}, {}
    for _, selected_port in ipairs(selected) do
        local role = selected_port.port.role == "out" and "out" or "in"
        if role == "out" then outputs[#outputs + 1] = selected_port else inputs[#inputs + 1] = selected_port end
    end
    --A port-bearing block needs enough room in both source axes for its top row to remain a legal edge after a
    --quarter-turn. Keeping the ports on one shared top row also avoids source-frame bottom attachments becoming
    --interior coordinates in the rotated envelope.
    local function place_side(list, role, side, normal, travel, offset)
        if #list > 0 then
            block.port_sides = block.port_sides or {}
            block.port_sides[side] = true
        end
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
            local inserter_id
            local wanted_role = role == "in" and "input" or "output"
            for _, inserter in ipairs(block.inserters or {}) do
                if inserter.machine_id == selected_port.member_id and inserter.role == wanted_role
                    and inserter.flow_id == (source.flow_id or source.full_name or selected_port.flow_id) then
                    inserter_id = inserter.id
                    local position = role == "in" and point(inserter.pickup_position) or point(inserter.drop_position)
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
            local machine = member_for(block, selected_port.member_id)
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
                    local on_edge = (connection_x == -1 and connection_y >= 0 and connection_y < block.h)
                        or (connection_x == block.w and connection_y >= 0 and connection_y < block.h)
                        or (connection_y == -1 and connection_x >= 0 and connection_x < block.w)
                        or (connection_y == block.h and connection_x >= 0 and connection_x < block.w)
                    if on_edge then x, y = connection_x, connection_y end
                end
            end
            local actual_normal, actual_travel = normal, travel
            if x == -1 then actual_normal, actual_travel = EAST, role == "in" and EAST or WEST
            elseif x == block.w then actual_normal, actual_travel = WEST, role == "in" and WEST or EAST
            elseif y == -1 then actual_normal, actual_travel = SOUTH, role == "in" and SOUTH or NORTH
            elseif y == block.h then actual_normal, actual_travel = NORTH, role == "in" and NORTH or SOUTH end
            local block_port = {
                port_id = source.port_id or source.id or ((role or "port") .. ":" .. tostring(index)),
                role = role, kind = source.kind or (source.is_fluid and "fluid" or "item"),
                flow_id = source.flow_id or source.full_name or selected_port.flow_id,
                rate_per_second = source.rate_per_second,
                step_id = selected_port.step_id,
                attach_dx = x, attach_dy = y, normal_dir = actual_normal, travel_dir = actual_travel,
                member_id = selected_port.member_id, inserter_id = inserter_id,
            }
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

    -- Put the machines in a compact deterministic strip.  Beacon rows are built on both sides, so a shared
    -- beacon is genuinely offered as a shared strip instead of being added after arbitrary machine packing.
    local machine_specs = {}
    local machine_specs_by_id = {}
    local machines_by_id = {}
    local max_machine_h = 1
    local machine_w = 0
    for _, step in ipairs(steps) do
        local mw, mh = machine_size(step, catalog)
        local machine_spec = lookup_entity(catalog, step.machine, "machine")
        max_machine_h = math.max(max_machine_h, mh)
        local layout_w = mw
        local _, step_inserter_w = inserter_size(catalog, input and input.inserter)
        for _, entry in ipairs(step.inputs or {}) do layout_w = math.max(layout_w, step_inserter_w) end
        for _, entry in ipairs(step.outputs or {}) do layout_w = math.max(layout_w, step_inserter_w) end
        for ordinal = 1, step.machine_count do
            local spec = {step = step, ordinal = ordinal, w = mw, h = mh, layout_w = layout_w,
                machine_spec = machine_spec}
            spec.id = member_id("machine", step.step_id, ordinal)
            machine_specs[#machine_specs + 1] = spec
            machine_specs_by_id[spec.id] = spec
            machine_w = machine_w + layout_w
            if #machine_specs > 1 then machine_w = machine_w + 1 end
        end
    end

    -- Every requested signature has a row on each side of the machine strip.  Starting both rows at the
    -- configured requirement gives sharing a chance, while the loop below adds only the physical beacons that
    -- the source-frame collision boxes actually need.
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
            local top = {group = group, w = bw, h = bh, count = count, side = "top"}
            top_rows[#top_rows + 1] = top
            beacon_row_specs[#beacon_row_specs + 1] = top
            beacon_rows_h = beacon_rows_h + bh + 1
            if count > 2 then
                local bottom = {group = group, w = bw, h = bh, count = count, side = "bottom"}
                bottom_rows[#bottom_rows + 1] = bottom
                beacon_row_specs[#beacon_row_specs + 1] = bottom
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
                local supply = Geometry.supply_box(beacon_x, beacon_y, row.group.supply_w, row.group.supply_h)
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
    local machine_x0 = 0
    for _, row in ipairs(beacon_row_specs) do machine_x0 = math.max(machine_x0, row.w) end
    --Inputs occupy the machine's left face. Reserve that side margin even for a machine with no beacons,
    --otherwise the first input inserter would start outside the block envelope.
    for _, step in ipairs(steps) do
        for _, entry in ipairs(step.inputs or {}) do
            if not flow_is_fluid(entry, flows) then
                local _, input_w = inserter_size(catalog, input and input.inserter)
                machine_x0 = math.max(machine_x0, input_w)
                break
            end
        end
    end
    local x = machine_x0
    for _, spec in ipairs(machine_specs) do
        local machine = {
            id = spec.id,
            kind = "machine", type = "machine", name = spec.step.machine, entity = spec.step.machine,
            quality = spec.step.machine_quality, step_id = spec.step.step_id, ordinal = spec.ordinal,
            x = x, y = machine_y, w = spec.w, h = spec.h,
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
        x = x + spec.layout_w + 1
    end
    -- All machines are known before any transfer is solved.  That matters for an explicit machine-to-machine
    -- obligation: the inserter at the producer and the inserter at the consumer must each see the other machine
    -- as a real endpoint, even when the producer appears first in step order.
    for _, spec in ipairs(machine_specs) do
        append_inserters(block, spec.step, machines_by_id[spec.id], catalog, input, flows)
    end

    -- Inserter rows belonging to different machines have disjoint x ranges because machine_specs reserves the
    -- widest inserter footprint for each machine strip.  Rows belonging to one machine were accumulated above,
    -- so variable inserter heights cannot overlap either.
    local inserter_bottom = machine_y + max_machine_h
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
    for _, row in ipairs(bottom_rows) do
        row.y = bottom_row_y
        bottom_row_y = bottom_row_y + row.h + 1
    end

    --Anchored at the machine strip, never centred in a width the row itself sets. Centring made the block
    --widen as the row grew, which re-centred the row and moved beacons AWAY from the machine that still
    --needed one, so coverage was not monotone in row.count and the old loop could never converge.
    local function row_x(row)
        return 0
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
    w = math.max(1, machine_x0 + machine_w, rows_width(), input_count, output_count, input_count + output_count)

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

    -- Ports are stored in the block's own frame, but the validator checks their attachment against the placed
    -- envelope. Reserve the total top-row width in both dimensions: after a quarter-turn the source x range
    -- is still bounded by the placed width, and the source top edge is still the placed top edge.
    if input_count + output_count > 0 then
        local port_count = input_count + output_count
        block.w = math.max(block.w, port_count)
        block.h = math.max(block.h, port_count)
    end
    block.envelope = {x = 0, y = 0, w = block.w, h = block.h}
    block.beacon_count = block.physical_beacon_count
    block_ports(block, steps, ports, flows)

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
    return block
end

local function partition_specs(steps, limit)
    local result, buckets = {}, {}
    local function emit()
        local groups = {}
        for index, bucket in ipairs(buckets) do
            local ids = {}
            for _, step in ipairs(bucket) do ids[#ids + 1] = step.step_id end
            groups[#groups + 1] = {steps = list_copy(bucket), id = table.concat(ids, "+"), ordinal = index}
        end
        result[#result + 1] = groups
    end
    local function visit(index)
        if #result >= limit then return end
        if index > #steps then emit() return end
        local step = steps[index]
        for bucket_index = 1, #buckets do
            local bucket = buckets[bucket_index]
            local allowed = true
            for _, other in ipairs(bucket) do
                if not step_can_join(step, other) then allowed = false break end
            end
            if allowed then
                bucket[#bucket + 1] = step
                visit(index + 1)
                bucket[#bucket] = nil
            end
        end
        buckets[#buckets + 1] = {step}
        visit(index + 1)
        buckets[#buckets] = nil
    end
    visit(1)
    return result
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
                port.port_id = entry.port_id or ("in:" .. tostring(entry.flow_id or entry.full_name))
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
                port.port_id = entry.port_id or ("out:" .. tostring(entry.flow_id or entry.full_name))
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

local function make_candidates(input)
    local _, catalog, steps, flows = normalize_plan(input)
    local ports = step_ports(steps, catalog, flows)
    local limits = input and input.limits or {}
    local max_candidates = math.max(1, math.floor(finite(limits.max_candidates or input.max_candidates, 128)))
    local specs = partition_specs(steps, max_candidates * 2)
    local candidates, failures = {}, {}
    local seen = {}
    for _, spec in ipairs(specs) do
        local blocks = {}
        local valid = true
        for _, group in ipairs(spec) do
            local block_id = "block:" .. group.id
            local block = build_block(group.steps, catalog, relevant_ports(group.steps, ports, flows), flows, input, block_id)
            if block.invalid_coverage or block.failure then
                valid = false
                failures[#failures + 1] = block.failure or {
                    name = "beacon-split", code = "BP_P_NO_FIT", detail = "configured beacon coverage cannot be split",
                }
                break
            end
            blocks[#blocks + 1] = block
        end
        if valid then
            table.sort(blocks, function(a, b) return a.id < b.id end)
            local ids = {}
            local beacon_count = 0
            for _, block in ipairs(blocks) do
                ids[#ids + 1] = block.id
                beacon_count = beacon_count + block.physical_beacon_count
            end
            local id = table.concat(ids, "|")
            if not seen[id] then
                seen[id] = true
                candidates[#candidates + 1] = {
                    id = id, candidate_id = id, blocks = blocks,
                    physical_beacon_count = beacon_count, beacon_count = beacon_count,
                }
            end
        end
        if #candidates >= max_candidates then break end
    end
    table.sort(candidates, function(a, b)
        if a.physical_beacon_count == b.physical_beacon_count then return a.id < b.id end
        return a.physical_beacon_count < b.physical_beacon_count
    end)
    return candidates, failures
end

function Groups.begin(input)
    local candidates, failures = make_candidates(input or {})
    return {
        done = false, ok = nil, cursor = {candidate_index = 1},
        progress = {phase = "grouping", done_units = 0, total_units = #candidates},
        work = {candidates = candidates, failures = failures, emitted = {}},
    }
end

function Groups.step(state, budget)
    if state.done then return state end
    budget = budget or {ops = 1}
    local ops = finite(budget.ops, 1)
    while ops > 0 and state.cursor.candidate_index <= #state.work.candidates do
        local candidate = state.work.candidates[state.cursor.candidate_index]
        state.work.emitted[#state.work.emitted + 1] = candidate
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.progress.done_units = state.progress.done_units + 1
        ops = ops - 1
    end
    budget.ops = ops
    if state.cursor.candidate_index > #state.work.candidates then
        state.result = {candidates = state.work.emitted, failures = list_copy(state.work.failures)}
        state.done, state.ok = true, #state.work.emitted > 0
    end
    return state
end

--A placed block's entities, ids prefixed "m:", rotated through Grid.place_member and Grid.place_port only
function Groups.materialize(block, placement)
    placement = placement or {x = 0, y = 0, dir = NORTH}
    local px, py, dir = finite(placement.x, 0), finite(placement.y, 0), placement.dir or NORTH
    local placed = {entities = {}, ports = {}, envelope = nil}
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
    table.sort(placed.entities, function(a, b) return a.id < b.id end)
    table.sort(placed.ports, function(a, b) return tostring(a.port_id) < tostring(b.port_id) end)
    return placed
end

return Groups

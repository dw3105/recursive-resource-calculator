--The second opinion: everything a finished candidate claims, checked again from the exact prototype geometry.
--
--Owned by lane W3-validate.  This module deliberately does not call any producer.  The candidate is already
--finished; this pass uses the catalog and the candidate's provenance to independently check it.
--
--  state.result = {score = {beacon_count, footprint_area, pole_count, route_length, entity_count, coord_key},
--                  metrics = {beacon_effects_by_step_id, peak_power_w, pollution_per_min, achieved_rate_by_port_id}}
--  state.errors = {{code = "BP_V_...", ids = {string}, detail = table}}
local Validate = {}

local Grid = require "logic.bp.grid"

local EPSILON = 1e-9
local INF = math.huge

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

local function corners_box(box, dir)
    if type(box) ~= "table" or type(box.left_top) ~= "table" or type(box.right_bottom) ~= "table" then return nil end
    local left, top = finite(box.left_top.x), finite(box.left_top.y)
    local right, bottom = finite(box.right_bottom.x), finite(box.right_bottom.y)
    if not left or not top or not right or not bottom then return nil end
    local points = {{x = left, y = top}, {x = left, y = bottom}, {x = right, y = top}, {x = right, y = bottom}}
    local min_x, min_y, max_x, max_y = INF, INF, -INF, -INF
    for _, point in ipairs(points) do
        local x, y = Grid.rotate_vector(point.x, point.y, dir or Grid.NORTH)
        min_x, min_y = math.min(min_x, x), math.min(min_y, y)
        max_x, max_y = math.max(max_x, x), math.max(max_y, y)
    end
    return {left = min_x, top = min_y, right = max_x, bottom = max_y}
end

local function entity_center(entity, spec)
    if entity.position and type(entity.position) == "table" then
        local x, y = finite(entity.position.x), finite(entity.position.y)
        if x and y then return x, y end
    end
    local w = finite(entity.w, spec and spec.tile_w or 1)
    local h = finite(entity.h, spec and spec.tile_h or 1)
    return finite(entity.x, 0) + w / 2, finite(entity.y, 0) + h / 2
end

local function physical_info(entity, catalog, ordinal)
    local spec = catalog_entity(catalog, entity) or {}
    local cx, cy = entity_center(entity, spec)
    local dir = finite(entity.dir or entity.direction, Grid.NORTH)
    local box = corners_box(spec.collision_box or entity.collision_box, dir)
    if not box then
        local w, h = finite(entity.w, spec.tile_w or 1), finite(entity.h, spec.tile_h or 1)
        box = {left = -w / 2, top = -h / 2, right = w / 2, bottom = h / 2}
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

local function boxes_overlap(a, b)
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end

local function point_in_area(info, centre_x, centre_y, supply_w, supply_h)
    return info.cx >= centre_x - supply_w - EPSILON and info.cx <= centre_x + supply_w + EPSILON
        and info.cy >= centre_y - supply_h - EPSILON and info.cy <= centre_y + supply_h + EPSILON
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
        if id == nil or seen[id] then return end
        seen[id] = true; local copy = copy_table(port); copy.port_id = id; result[#result + 1] = copy
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

local function connector_ids(input)
    local ids = {pole_copper = 0, power_switch_left_copper = 1, power_switch_right_copper = 2, circuit_red = 3, circuit_green = 4}
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
                local dx, dy = finite(port.attach_dx), finite(port.attach_dy)
                local bounded = dx and dy and (((dx == -1 or dx == width) and dy >= 0 and dy < height)
                    or ((dy == -1 or dy == height) and dx >= 0 and dx < width))
                local id = port.port_id or port.id
                if not bounded then error_record(errors, "BP_V_PORT_EDGE_WRONG", {tostring(id)}, {reason = "attachment is not on the block boundary"}) end
                local nx, ny = Grid.dir_vector(port.normal_dir or Grid.NORTH)
                local inward = bounded and ((dx == -1 and nx == 1) or (dx == width and nx == -1) or (dy == -1 and ny == 1) or (dy == height and ny == -1))
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
    local ports = collect_ports(root); local port_by_id = map_by_id(ports)
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
    return {input = input, root = root, plan = plan, catalog = catalog, entities = entities, infos = infos, info_by_id = info_by_id,
        grid_w = grid_w, grid_h = grid_h, wires = wires, flows = flows, ports = ports, port_by_id = port_by_id,
        segments = segments, segment_by_id = segment_by_id, bindings = bindings, steps = steps, placements = placements,
        machines = machines, beacons = beacons, poles = poles, power_nodes = power_nodes, roboports = roboports, inserters = inserters,
        consumers = consumers, ids = connector_ids(input), errors = {}, legal_wires = {}, power_parent = {},
        metrics = {beacon_effects_by_step_id = {}, achieved_rate_by_port_id = {}, peak_power_w = 0, pollution_per_min = 0}}
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
            if (port.flow_id or port.full_name) == flow_id_of(flow) and (port.role == role or port.direction == role) then return "port:" .. tostring(port.port_id) end
        end
        return nil
    end
    return step and "step:" .. tostring(step) or nil
end

local function segment_capacity(work, segment, kind)
    if segment.capacity_per_second ~= nil then return finite(segment.capacity_per_second, 0) end
    if kind == "pipe" then return finite(work.catalog.pipe and work.catalog.pipe.throughput_per_second, INF) end
    if kind == "inserter" then return finite(work.catalog.inserter and work.catalog.inserter.items_per_second, INF) end
    if kind == "lane" then return finite(work.catalog.belt and work.catalog.belt.lane_items_per_second, finite(work.catalog.belt and work.catalog.belt.items_per_second, INF)) end
    return finite(work.catalog.belt and work.catalog.belt.items_per_second, INF)
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
            local reach_a = finite(a.entity.connection_distance, finite(a.spec.connection_distance,
                finite(work.catalog.robo and work.catalog.robo.connection_distance, 0)))
            local reach_b = finite(b.entity.connection_distance, finite(b.spec.connection_distance,
                finite(work.catalog.robo and work.catalog.robo.connection_distance, 0)))
            local dx, dy = a.cx - b.cx, a.cy - b.cy
            if math.sqrt(dx * dx + dy * dy) <= math.min(reach_a, reach_b) + tolerance(math.min(reach_a, reach_b)) then join(a.id, b.id) end
        end
    end
    local root = find(work.roboports[1].id); local disconnected = {}
    for _, robo in ipairs(work.roboports) do if find(robo.id) ~= root then disconnected[#disconnected + 1] = tostring(robo.id) end end
    if #disconnected > 0 then error_record(work.errors, "BP_V_ROBO_DISCONNECTED", disconnected) end
    return true
end

local function check_beacons(work)
    for _, machine in ipairs(work.machines) do
        local influencing, effects = {}, {speed = 0, consumption = 0, pollution = 0, quality = 0}
        for _, beacon in ipairs(work.beacons) do
            local projection = beacon_projection(beacon, work.catalog)
            if point_in_area(machine, beacon.cx, beacon.cy, projection.supply_w, projection.supply_h) then
                influencing[#influencing + 1] = beacon
                if machine.entity.forbids_speed_beacon or machine.entity.has_quality_module
                    or (work.steps[machine.entity.step_id] and (work.steps[machine.entity.step_id].forbids_speed_beacon
                        or work.steps[machine.entity.step_id].has_quality_module)) then
                    if has_speed_module(beacon, work.catalog) then error_record(work.errors, "BP_V_SPEED_BEACON_ON_QUALITY", {tostring(beacon.id), tostring(machine.id)}) end
                end
            end
        end
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
        if machine.entity.step_id ~= nil then work.metrics.beacon_effects_by_step_id[machine.entity.step_id] = effects end
    end
    return true
end

local function check_power_coverage(work)
    for _, consumer in ipairs(work.consumers) do
        local covered = false
        for _, pole in ipairs(work.poles) do
            local supply_w, supply_h = supply_size(pole, work.catalog)
            if point_in_area(consumer, pole.cx, pole.cy, supply_w, supply_h) then covered = true; break end
        end
        if not covered then error_record(work.errors, "BP_V_POWER_UNCOVERED", {tostring(consumer.id)}) end
        work.metrics.peak_power_w = work.metrics.peak_power_w + finite(consumer.entity.power_w, finite(consumer.spec.energy_usage_w, 0))
        work.metrics.pollution_per_min = work.metrics.pollution_per_min + finite(consumer.spec.pollution_per_min, 0)
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
    for _, segment in ipairs(work.segments) do
        local kind = segment.kind or "belt"; local capacity = segment_capacity(work, segment, kind); local total = 0; local flows_on_segment = {}
        for _, allocation in ipairs(segment.allocations or {}) do
            local amount = flow_share(allocation); total = total + amount; local flow_id = allocation.flow_id or segment.flow_id
            if flow_id ~= nil then
                flows_on_segment[flow_id] = true; allocation_by_flow_sink[flow_id] = allocation_by_flow_sink[flow_id] or {}
                if allocation.sink ~= nil then allocation_by_flow_sink[flow_id][allocation.sink] = (allocation_by_flow_sink[flow_id][allocation.sink] or 0) + amount end
            end
        end
        local code = kind == "pipe" and "BP_V_PIPE_CAPACITY" or kind == "inserter" and "BP_V_INSERTER_CAPACITY" or "BP_V_BELT_CAPACITY"
        if total > capacity + tolerance(capacity) then error_record(work.errors, code, {tostring(segment.segment_id)}, {capacity = capacity, allocated = total}) end
        local flow_count = 0; for _, _ in pairs(flows_on_segment) do flow_count = flow_count + 1 end
        if kind == "pipe" and flow_count > 1 then error_record(work.errors, "BP_V_FLUID_MIXING", {tostring(segment.segment_id)}) end
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
                    if reached + tolerance(required) < required then error_record(work.errors, "BP_V_TARGET_SHORTFALL", {tostring(flow_id), tostring(step_id_of(entry))}, {required = required, reached = reached, sink = sink}) end
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
    local underground = {}; for _, info in ipairs(work.infos) do if info.entity.ug_pair_id or info.entity.ug_role then underground[#underground + 1] = info end end
    for _, info in ipairs(underground) do
        local pair = work.info_by_id[info.entity.ug_pair_id]
        if not pair or not pair.entity.ug_pair_id or pair.entity.ug_pair_id ~= info.id or pair.entity.ug_role == info.entity.ug_role then
            error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(info.entity.ug_pair_id)})
        elseif pair.entity.flow_id and info.entity.flow_id and pair.entity.flow_id ~= info.entity.flow_id then
            error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "flow differs"})
        else
            local distance = math.abs(info.cx - pair.cx) + math.abs(info.cy - pair.cy); local first, second = connection_for(info), connection_for(pair)
            local kind = (info.kind == "pipe" or pair.kind == "pipe") and "pipe" or "belt"; local family = kind == "pipe" and work.catalog.pipe or work.catalog.belt
            local first_max = finite(first and first.max_underground_distance, finite(family and family.underground_max_distance, INF))
            local second_max = finite(second and second.max_underground_distance, finite(family and family.underground_max_distance, INF))
            if distance > first_max + tolerance(first_max) or distance > second_max + tolerance(second_max) then error_record(work.errors, "BP_V_UNDERGROUND_RANGE", {tostring(info.id), tostring(pair.id)}, {distance = distance, first_max = first_max, second_max = second_max}) end
            if first and second and first.direction and second.direction then
                local dx, dy = pair.cx - info.cx, pair.cy - info.cy; local expected = Grid.dir_from_vector(dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1))
                if expected and (first.direction ~= expected or second.direction ~= Grid.dir_opposite(expected)) then error_record(work.errors, "BP_V_UNDERGROUND_UNPAIRED", {tostring(info.id), tostring(pair.id)}, {reason = "connections do not face each other"}) end
            end
        end
    end
    return true
end

local function check_ports(work)
    local bound_source, bound_sink = {}, {}
    for _, binding in ipairs(work.bindings) do
        local source_id, sink_id = binding.source_port_id or binding.source, binding.sink_port_id or binding.sink; local source, sink = work.port_by_id[source_id], work.port_by_id[sink_id]
        local source_ok = source and (source.role == "out" or (source.role == "in" and is_external_port(source)))
        local sink_ok = sink and (sink.role == "in" or (sink.role == "out" and is_external_port(sink)))
        local bad = not source or not sink or not source_ok or not sink_ok; local flow_id = binding.flow_id
        if not bad and flow_id then
            local source_flow, sink_flow = source.flow_id or source.full_name, sink.flow_id or sink.full_name
            if (source_flow and source_flow ~= flow_id) or (sink_flow and sink_flow ~= flow_id) then bad = true end
        end
        if bad then error_record(work.errors, "BP_V_PORT_EDGE_WRONG", {tostring(source_id), tostring(sink_id)}) end
        if source_id then bound_source[source_id] = true end; if sink_id then bound_sink[sink_id] = true end
        if binding.rate_per_second and source_id then work.metrics.achieved_rate_by_port_id[source_id] = (work.metrics.achieved_rate_by_port_id[source_id] or 0) + flow_share(binding) end
        if binding.rate_per_second and sink_id then work.metrics.achieved_rate_by_port_id[sink_id] = (work.metrics.achieved_rate_by_port_id[sink_id] or 0) + flow_share(binding) end
        if binding.segment_id and not work.segment_by_id[binding.segment_id] then error_record(work.errors, "BP_V_PORT_EDGE_WRONG", {tostring(binding.segment_id)}, {reason = "segment is missing"}) end
    end
    for _, port in ipairs(work.ports) do
        local rate = finite(port.rate_per_second, finite(port.rate, 0)); local role = port.role or port.direction
        local source_side = role == "out" or (role == "in" and is_external_port(port))
        local sink_side = role == "in" or (role == "out" and is_external_port(port))
        if rate > tolerance(rate) and ((source_side and not bound_source[port.port_id]) or (sink_side and not bound_sink[port.port_id])) then error_record(work.errors, "BP_V_PORT_UNREACHABLE", {tostring(port.port_id)}) end
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
            if step.modules and not module_lists_equal(machine.entity.modules or {}, step.modules) then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(machine.id)}, {step_id = step_id}) end
            if machine.spec.module_slots ~= nil and #expand_modules(machine.entity.modules or {}) > machine.spec.module_slots then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(machine.id)}, {reason = "machine module slots exceeded"}) end
        end
    end
    for step_id, step in pairs(work.steps) do if step.machine_count ~= nil and count_by_step[step_id] ~= finite(step.machine_count, 0) then error_record(work.errors, "BP_V_MACHINE_COUNT_MISMATCH", {tostring(step_id)}, {expected = step.machine_count, placed = count_by_step[step_id] or 0}) end end
    for _, info in ipairs(work.beacons) do if info.spec.module_slots ~= nil and #beacon_modules(info) > info.spec.module_slots then error_record(work.errors, "BP_V_MODULE_MISMATCH", {tostring(info.id)}, {reason = "beacon module slots exceeded"}) end end
    for _, info in ipairs(work.inserters) do
        local rate = finite(info.entity.rate_per_second, finite(info.entity.flow_rate, 0)); local capacity = finite(info.entity.items_per_second, finite(info.spec.items_per_second, work.catalog.inserter and work.catalog.inserter.items_per_second))
        if rate > capacity + tolerance(capacity) then error_record(work.errors, "BP_V_INSERTER_CAPACITY", {tostring(info.id)}, {capacity = capacity, requested = rate}) end
        local pickup, drop = info.entity.pickup_position or info.entity.pickup_offset, info.entity.drop_position or info.entity.drop_offset
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

local function coordinate_key(work)
    local parts = {}; for _, info in ipairs(work.infos) do parts[#parts + 1] = tostring(info.id) .. "@" .. tostring(info.cx) .. ":" .. tostring(info.cy) end
    table.sort(parts); return table.concat(parts, "|")
end

local function make_score(work)
    local min_x, min_y, max_x, max_y = INF, INF, -INF, -INF; local route_length, beacon_count, pole_count = 0, 0, 0
    for _, info in ipairs(work.infos) do
        local rect = rect_of_entity(info.entity, info.spec); min_x, min_y = math.min(min_x, rect.x), math.min(min_y, rect.y); max_x, max_y = math.max(max_x, rect.x + rect.w), math.max(max_y, rect.y + rect.h)
        if is_beacon(info) then beacon_count = beacon_count + 1 end; if is_pole(info) then pole_count = pole_count + 1 end
    end
    for _, segment in ipairs(work.segments) do route_length = route_length + finite(segment.length, 0) end
    local area = max_x == -INF and 0 or (max_x - min_x) * (max_y - min_y)
    return {beacon_count = beacon_count, footprint_area = area, pole_count = pole_count, route_length = route_length, entity_count = #work.infos, coord_key = coordinate_key(work)}
end

local function finish(work, state)
    block_port_geometry(work.errors, work.root, work.placements)
    if #work.errors == 0 then state.ok = true; state.result = {score = make_score(work), metrics = work.metrics}; state.errors = nil
    else state.ok = false; state.errors = work.errors; state.result = nil end
    state.done = true; state.cursor = {phase = "done"}; state.progress.phase = "done"; state.progress.done_units = state.progress.total_units
end

function Validate.begin(input)
    local work = make_work(input)
    return {done = false, ok = nil, cursor = {phase = "geometry", index = 1}, progress = {phase = "validating", done_units = 0, total_units = math.max(1, #work.infos + #work.wires + #work.segments + #work.flows)}, result = nil, errors = nil, ops_used = 0, _work = work}
end

function Validate.step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    budget = type(budget) == "table" and budget or {ops = 1}; local ops = math.max(0, math.floor(finite(budget.ops, 1))); local work = state._work
    while ops > 0 and not state.done do
        local phase = state.cursor.phase
        if phase == "geometry" then
            local index = state.cursor.index; check_geometry(work, index); state.cursor.index = index + 1
            if index >= #work.infos then state.cursor.phase, state.cursor.index = "robo", 1 end
        elseif phase == "robo" then check_robo(work); state.cursor.phase = "beacon"
        elseif phase == "beacon" then check_beacons(work); state.cursor.phase = "power_coverage"
        elseif phase == "power_coverage" then check_power_coverage(work); state.cursor.phase = "wire_legality"
        elseif phase == "wire_legality" then check_wire_legality(work); state.cursor.phase = "wire_connectivity"
        elseif phase == "wire_connectivity" then check_wire_connectivity(work); state.cursor.phase = "segments"
        elseif phase == "segments" then check_segments(work); state.cursor.phase = "underground"
        elseif phase == "underground" then check_underground(work); state.cursor.phase = "ports"
        elseif phase == "ports" then check_ports(work); state.cursor.phase = "machines"
        elseif phase == "machines" then check_machines(work); state.cursor.phase = "finish"
        elseif phase == "finish" then finish(work, state)
        end
        ops = ops - 1; state.ops_used = state.ops_used + 1; state.progress.done_units = math.min(state.progress.total_units, state.progress.done_units + 1)
    end
    budget.ops = ops; return state
end

--The only place the user's priority is expressed: fewer physical beacons, then smaller footprint, then fewer
--poles, then deterministic tie-breakers.  The packer's fit score never decides which layout wins.
function Validate.compare(a_score, b_score)
    a_score, b_score = a_score or {}, b_score or {}
    for _, key in ipairs({"beacon_count", "footprint_area", "pole_count", "route_length", "entity_count"}) do
        local a, b = finite(a_score[key], 0), finite(b_score[key], 0); if a < b then return -1 end; if a > b then return 1 end
    end
    local a_key, b_key = tostring(a_score.coord_key or ""), tostring(b_score.coord_key or "")
    if a_key < b_key then return -1 end; if a_key > b_key then return 1 end; return 0
end

return Validate

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
    for _, value in ipairs(values) do
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

local function machine_center(member)
    return member.x + member.w / 2, member.y + member.h / 2
end

local function rects_overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function rect_contains(a, b)
    return a.x <= b.x and a.y <= b.y and a.x + a.w >= b.x + b.w and a.y + a.h >= b.y + b.h
end

local function cover_area(beacon, supply_w, supply_h)
    return Grid.beacon_area(beacon, supply_w, supply_h)
end

local function covers(beacon, machine, supply_w, supply_h)
    local area = cover_area(beacon, supply_w, supply_h)
    local cx, cy = machine_center(machine)
    return cx >= area.x and cx <= area.x + area.w and cy >= area.y and cy <= area.y + area.h
end

local function append_inserters(block, step, machine, catalog, input)
    local name, iw, ih = inserter_size(catalog, input and input.inserter)
    local ports = {}
    for _, port in ipairs(step.inputs or {}) do ports[#ports + 1] = {role = "input", port = port} end
    for _, port in ipairs(step.outputs or {}) do ports[#ports + 1] = {role = "output", port = port} end
    -- The block owns the inserters, but their exact belt/pipe connection is completed by the route lane.  A
    -- separate row per connection keeps the opaque member rectangles disjoint without guessing route geometry.
    for index, entry in ipairs(ports) do
        block.inserters[#block.inserters + 1] = {
            id = member_id("inserter", step.step_id, machine.ordinal, entry.role .. ":" .. tostring(index)),
            kind = "inserter", type = "inserter", name = name,
            step_id = step.step_id, machine_id = machine.id, role = entry.role,
            flow_id = entry.port.flow_id or entry.port.full_name,
            x = machine.x + math.min(machine.w - iw, math.max(0, index - 1)),
            y = machine.y + machine.h + index - 1, w = iw, h = ih,
            dir = entry.role == "input" and NORTH or SOUTH,
        }
    end
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
    --Every attach tile sits one row above the block or one row below it, never on the left or the right. A port
    --pushed onto a side column used to land at x = -1, which is outside the grid whenever the block touches the
    --left edge, and routing then refuses it. A block whose port list is wider than the block is widened instead,
    --so the row always has room, and the packer only has to keep those two rows free (see block.port_sides).
    local function place_side(list, role, side, normal, travel)
        if #list > block.w then
            block.w = #list
            block.envelope = {x = 0, y = 0, w = block.w, h = block.h}
        end
        if #list > 0 then
            block.port_sides = block.port_sides or {}
            block.port_sides[side] = true
        end
        for index, selected_port in ipairs(list) do
            local x = index - 1
            local y = side == "top" and -1 or block.h
            local source = selected_port.port
            block.ports[#block.ports + 1] = {
                port_id = source.port_id or source.id or ((role or "port") .. ":" .. tostring(index)),
                role = role, kind = source.kind or (source.is_fluid and "fluid" or "item"),
                flow_id = source.flow_id or source.full_name or selected_port.flow_id,
                rate_per_second = source.rate_per_second,
                step_id = selected_port.step_id,
                attach_dx = x, attach_dy = y, normal_dir = normal, travel_dir = travel,
                member_id = selected_port.member_id,
            }
        end
    end
    place_side(inputs, "in", "top", SOUTH, SOUTH)
    place_side(outputs, "out", "bottom", NORTH, SOUTH)
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
                existing.count = 0
                beacon_groups[group.signature] = existing
            end
            existing.count = math.max(existing.count, group.count_per_machine)
            existing.has_speed_module = existing.has_speed_module or group.has_speed_module
            seen_groups[group.signature] = true
        end
    end
    local ordered_groups = {}
    for _, group in pairs(beacon_groups) do ordered_groups[#ordered_groups + 1] = group end
    table.sort(ordered_groups, function(a, b) return a.signature < b.signature end)

    -- Put the machines in a compact deterministic strip.  Beacon rows are above it, so a shared beacon is
    -- genuinely offered as a shared strip instead of being added after an arbitrary machine packing.
    local machine_specs = {}
    local max_machine_h = 1
    local machine_w = 0
    for _, step in ipairs(steps) do
        local mw, mh = machine_size(step, catalog)
        max_machine_h = math.max(max_machine_h, mh)
        for ordinal = 1, step.machine_count do
            machine_specs[#machine_specs + 1] = {step = step, ordinal = ordinal, w = mw, h = mh}
            machine_w = machine_w + mw
            if #machine_specs > 1 then machine_w = machine_w + 1 end
        end
    end

    local beacon_rows_h, max_beacon_row_w = 0, 0
    local beacon_row_specs = {}
    for _, group in ipairs(ordered_groups) do
        local bw, bh = dimensions(catalog, group.name, "beacon", 3, 3)
        local row_w = math.max(1, group.count) * bw + math.max(0, group.count - 1)
        max_beacon_row_w = math.max(max_beacon_row_w, row_w)
        beacon_row_specs[#beacon_row_specs + 1] = {group = group, w = bw, h = bh, y = beacon_rows_h}
        beacon_rows_h = beacon_rows_h + bh + 1
    end
    if beacon_rows_h > 0 then beacon_rows_h = beacon_rows_h - 1 end

    local input_count, output_count = 0, 0
    for _, port in ipairs(ports or {}) do
        if port.role == "out" then output_count = output_count + 1 else input_count = input_count + 1 end
    end
    local w = math.max(1, machine_w, max_beacon_row_w, input_count, output_count)
    local machine_y = beacon_rows_h > 0 and beacon_rows_h + 1 or 0
    local x = 0
    for _, spec in ipairs(machine_specs) do
        local machine = {
            id = member_id("machine", spec.step.step_id, spec.ordinal),
            kind = "machine", type = "machine", name = spec.step.machine, entity = spec.step.machine,
            quality = spec.step.machine_quality, step_id = spec.step.step_id, ordinal = spec.ordinal,
            x = x, y = machine_y, w = spec.w, h = spec.h,
            modules = list_copy(spec.step.modules), forbids_speed_beacon = spec.step.forbids_speed_beacon,
        }
        block.machines[#block.machines + 1] = machine
        block.members[#block.members + 1] = machine
        x = x + spec.w + 1
        append_inserters(block, spec.step, machine, catalog, input)
    end

    local inserter_bottom = machine_y + max_machine_h
    for _, inserter in ipairs(block.inserters) do
        block.members[#block.members + 1] = inserter
    end

    for _, row in ipairs(beacon_row_specs) do
        local group = row.group
        local row_x = math.max(0, math.floor((w - (math.max(1, group.count) * row.w + math.max(0, group.count - 1))) / 2))
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
        for beacon_index = 1, math.max(0, group.count) do
            local beacon_x = row_x + (beacon_index - 1) * (row.w + 1)
            local beacon = {
                id = member_id("beacon", group.signature, beacon_index),
                kind = "beacon", type = "beacon", name = group.name, quality = group.quality,
                signature = group.signature, group_signature = group.signature,
                has_speed_module = group.has_speed_module, modules = list_copy(group.modules),
                x = beacon_x, y = row.y, w = row.w, h = row.h,
                supply_w = group.supply_w, supply_h = group.supply_h,
            }
            local covered = {}
            for _, machine_id in ipairs(required) do
                for _, machine in ipairs(block.machines) do
                    if machine.id == machine_id and covers(beacon, machine, group.supply_w, group.supply_h) then
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

    -- The inset rows belong to the block too.  They are placed after machines and never share an occupancy
    -- cell with a machine, another inserter, or a beacon.
    local max_inserter_bottom = inserter_bottom
    for _, inserter in ipairs(block.inserters) do
        max_inserter_bottom = math.max(max_inserter_bottom, inserter.y + inserter.h)
    end
    block.w = w
    block.h = math.max(machine_y + max_machine_h, max_inserter_bottom, beacon_rows_h)
    block.envelope = {x = 0, y = 0, w = block.w, h = block.h}
    block.beacon_count = block.physical_beacon_count
    block_ports(block, steps, ports, flows)

    -- A speed beacon is never allowed to claim a quality machine, even if a malformed plan uses a speed
    -- group on that step.  Such a block remains inspectable but is not offered as a candidate below because
    -- it cannot satisfy both the configured minimum and the hard isolation rule.
    for _, beacon in ipairs(block.beacons) do
        if beacon.has_speed_module then
            local safe = {}
            for _, machine_id in ipairs(beacon.required_for) do
                local machine
                for _, candidate in ipairs(block.machines) do if candidate.id == machine_id then machine = candidate break end end
                if not machine or not machine.forbids_speed_beacon then safe[#safe + 1] = machine_id end
            end
            beacon.required_for = safe
            beacon.covered_members = list_copy(safe)
            beacon.member_ids = list_copy(safe)
            beacon.members = list_copy(safe)
        end
    end
    for _, machine in ipairs(block.machines) do
        block.beacon_coverage[machine.id] = {}
        for _, beacon in ipairs(block.beacons) do
            local required = false
            for _, member_id_value in ipairs(beacon.required_for) do
                if member_id_value == machine.id then required = true break end
            end
            if required then block.beacon_coverage[machine.id][#block.beacon_coverage[machine.id] + 1] = beacon.id end
        end
    end
    for _, machine in ipairs(block.machines) do
        for _, group in ipairs(ordered_groups) do
            local required = false
            local step
            for _, candidate in ipairs(steps) do if candidate.step_id == machine.step_id then step = candidate break end end
            for _, entry in ipairs(step and step._groups or {}) do
                if entry.signature == group.signature and entry.count_per_machine > 0 then required = true break end
            end
            if required then
                local got = 0
                for _, beacon_id in ipairs(block.beacon_coverage[machine.id]) do
                    for _, beacon in ipairs(block.beacons) do
                        if beacon.id == beacon_id and beacon.signature == group.signature then got = got + 1 end
                    end
                end
                if got < group.count then block.invalid_coverage = true end
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

local function step_ports(steps)
    local ports = {}
    for _, step in ipairs(steps) do
        for _, entry in ipairs(step.inputs or {}) do
            if entry.external ~= false then
                ports[#ports + 1] = {
                    port_id = entry.port_id or ("in:" .. tostring(entry.flow_id or entry.full_name)),
                    role = "in", kind = entry.kind or (entry.is_fluid and "fluid" or "item"),
                    flow_id = entry.flow_id or entry.full_name, rate_per_second = entry.rate_per_second,
                    step_id = step.step_id,
                }
            end
        end
        for _, entry in ipairs(step.outputs or {}) do
            if entry.external ~= false then
                ports[#ports + 1] = {
                    port_id = entry.port_id or ("out:" .. tostring(entry.flow_id or entry.full_name)),
                    role = "out", kind = entry.kind or (entry.is_fluid and "fluid" or "item"),
                    flow_id = entry.flow_id or entry.full_name, rate_per_second = entry.rate_per_second,
                    step_id = step.step_id,
                }
            end
        end
    end
    return ports
end

local function make_candidates(input)
    local _, catalog, steps, flows = normalize_plan(input)
    local ports = step_ports(steps)
    local limits = input and input.limits or {}
    local max_candidates = math.max(1, math.floor(finite(limits.max_candidates or input.max_candidates, 128)))
    local specs = partition_specs(steps, max_candidates * 2)
    local candidates = {}
    local seen = {}
    for _, spec in ipairs(specs) do
        local blocks = {}
        local valid = true
        for _, group in ipairs(spec) do
            local block_id = "block:" .. group.id
            local block = build_block(group.steps, catalog, relevant_ports(group.steps, ports, flows), flows, input, block_id)
            if block.invalid_coverage then valid = false break end
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
    return candidates
end

function Groups.begin(input)
    local candidates = make_candidates(input or {})
    return {
        done = false, ok = nil, cursor = {candidate_index = 1},
        progress = {phase = "grouping", done_units = 0, total_units = #candidates},
        work = {candidates = candidates, emitted = {}},
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
        state.result = {candidates = state.work.emitted}
        state.done, state.ok = true, #state.work.emitted > 0
    end
    return state
end

--A placed block's entities, ids prefixed "m:", rotated through Grid.place_member and Grid.place_port only
function Groups.materialize(block, placement)
    placement = placement or {x = 0, y = 0, dir = NORTH}
    local px, py, dir = finite(placement.x, 0), finite(placement.y, 0), placement.dir or NORTH
    local placed = {entities = {}, ports = {}, envelope = nil}
    local oriented_w, oriented_h = Grid.rotate_size(block.w, block.h, dir)
    placed.envelope = {x = px, y = py, w = oriented_w, h = oriented_h, dir = dir}
    for _, member in ipairs(block.members or {}) do
        local geometry = Grid.place_member(block, {x = px, y = py, dir = dir}, member)
        local entity = copy(member)
        entity.id = "m:" .. tostring(member.id)
        if entity.machine_id then entity.machine_id = "m:" .. tostring(entity.machine_id) end
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
        placed.entities[#placed.entities + 1] = entity
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
        if slot then
            source = copy(port)
            source.attach_dx, source.attach_dy = slot.attach_dx, slot.attach_dy
            source.normal_dir, source.travel_dir = slot.normal_dir, slot.travel_dir
        end
        local geometry = Grid.place_port(block, {x = px, y = py, dir = dir}, source)
        local placed_port = copy(source)
        placed_port.x, placed_port.y = geometry.x, geometry.y
        if placed_port.member_id then placed_port.member_id = "m:" .. tostring(placed_port.member_id) end
        placed_port.normal_dir = geometry.dir
        placed_port.dir = geometry.dir
        placed_port.travel_dir = Grid.rotate_dir(source.travel_dir or NORTH, dir)
        placed.ports[#placed.ports + 1] = placed_port
    end
    table.sort(placed.entities, function(a, b) return a.id < b.id end)
    table.sort(placed.ports, function(a, b) return tostring(a.port_id) < tostring(b.port_id) end)
    return placed
end

return Groups

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

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function number_text(value)
    value = finite(value, 0)
    if value == math.floor(value) then return string.format("%d", value) end
    return string.format("%.17g", value)
end

--The serializer is a pure boundary.  Copying here prevents a malformed fixture from making a function, userdata or
--metatable reachable from a job that might later be saved.
local function copy(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then return value end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = copy(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function sorted_keys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function list_or_map(source)
    local result = {}
    if type(source) ~= "table" then return result end
    if #source > 0 then
        for index, value in ipairs(source) do result[#result + 1] = value end
    else
        for _, key in ipairs(sorted_keys(source)) do
            if type(source[key]) == "table" then result[#result + 1] = source[key] end
        end
    end
    return result
end

local function quality_name(value)
    if type(value) == "table" then value = value.name or value.id end
    if type(value) ~= "string" or value == "" then return "normal" end
    return value
end

local function position(value)
    if type(value) ~= "table" then return nil end
    local x, y = finite(value.x), finite(value.y)
    if x ~= nil and y ~= nil then return {x = x, y = y} end
    x, y = finite(value[1]), finite(value[2])
    if x ~= nil and y ~= nil then return {x = x, y = y} end
    return nil
end

local function entity_position(entity)
    local result = position(entity and entity.position)
    if result then return result end
    local x, y = finite(entity and entity.x), finite(entity and entity.y)
    if x == nil or y == nil then return {x = 0, y = 0} end
    local width = finite(entity.w or entity.width)
    local height = finite(entity.h or entity.height)
    if width ~= nil and height ~= nil then
        return {x = x + width / 2, y = y + height / 2}
    end
    return {x = x, y = y}
end

local function entity_id(entity, fallback)
    if type(entity) ~= "table" then return fallback end
    return entity.id or entity.entity_id or entity._id or entity.entity_number or fallback
end

local function catalog_entity(catalog, entity)
    if type(catalog) ~= "table" or type(catalog.entity) ~= "table" then return nil end
    local name = entity and (entity.name or entity.prototype or entity.entity)
    if type(name) ~= "string" then return nil end
    return catalog.entity[name]
end

local function id_text(entity, fallback)
    return tostring(entity_id(entity, fallback))
end

local function append_entities(source, result, seen)
    for index, raw in ipairs(list_or_map(source)) do
        if type(raw) == "table" then
            local id = entity_id(raw, index)
            local key = type(id) .. ":" .. (type(id) == "string" and id or tostring(id))
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = raw
            end
        end
    end
end

local function block_entities(block, placement, result)
    if type(block) ~= "table" then return end
    local source = block.entities
    if type(source) ~= "table" then source = block.members end
    if type(source) ~= "table" then return end
    placement = placement or {}
    local px, py = finite(placement.x, 0), finite(placement.y, 0)
    for index, raw in ipairs(list_or_map(source)) do
        if type(raw) == "table" then
            local entity = copy(raw)
            entity.id = entity.id or entity.entity_id or ("m:" .. tostring(block.id or block.block_id or index) .. ":" .. tostring(index))
            if entity.position == nil then
                local x, y = finite(entity.x), finite(entity.y)
                if x ~= nil and y ~= nil then
                    local width, height = finite(entity.w, 1), finite(entity.h, 1)
                    entity.position = {x = px + x + width / 2, y = py + y + height / 2}
                end
            end
            result[#result + 1] = entity
        end
    end
end

local function candidate_entities(candidate)
    candidate = type(candidate) == "table" and candidate or {}
    local root = candidate.candidate or candidate
    local blueprint = type(root.blueprint) == "table" and root.blueprint or root
    local result, seen = {}, {}
    append_entities(blueprint.entities, result, seen)
    append_entities(root.placed_entities, result, seen)
    append_entities(root.layout and root.layout.entities, result, seen)
    append_entities(root.route and root.route.entities, result, seen)
    append_entities(root.routing and root.routing.entities, result, seen)
    append_entities(root.power and root.power.entities, result, seen)
    append_entities(root.infrastructure and root.infrastructure.entities, result, seen)
    append_entities(root.result and root.result.entities, result, seen)

    local blocks = list_or_map(root.blocks)
    local placements = root.placements or root.layout and root.layout.placements or {}
    for _, block in ipairs(blocks) do
        local block_id = block.id or block.block_id
        local placement = placements[block_id]
        if placement == nil then
            for _, candidate_placement in ipairs(list_or_map(placements)) do
                if candidate_placement.block_id == block_id or candidate_placement.id == block_id then
                    placement = candidate_placement
                    break
                end
            end
        end
        local materialized = {}
        block_entities(block, placement, materialized)
        append_entities(materialized, result, seen)
    end
    return result
end

local function sort_entities(entities)
    local ordered = {}
    for index, entity in ipairs(entities or {}) do
        ordered[index] = copy(entity) or {}
        ordered[index]._serialize_index = index
    end
    --Same comparisons as before; each entity's position and id text built once (round 56 gate Tick cost).
    local pos, ids = {}, {}
    for _, entity in ipairs(ordered) do pos[entity] = entity_position(entity); ids[entity] = id_text(entity, entity._serialize_index) end
    table.sort(ordered, function(a, b)
        local pa, pb = pos[a], pos[b]
        if pa.y ~= pb.y then return pa.y < pb.y end
        if pa.x ~= pb.x then return pa.x < pb.x end
        local ia, ib = ids[a], ids[b]
        if ia ~= ib then return ia < ib end
        return a._serialize_index < b._serialize_index
    end)
    return ordered
end

--Text of small whole numbers, built once (entity numbers repeat in every serialize; pure memo).
local integer_text = {}
local function add_reference(map, value, number)
    if value == nil then return end
    map[value] = number
    --A string is its own text: same map without a tostring per reference (round 56 gate, magenta success tick).
    if type(value) == "string" then return end
    local text
    if type(value) == "number" and value >= 1 and value <= 1000000 and value == math.floor(value) then
        text = integer_text[value]
        if not text then text = tostring(value); integer_text[value] = text end
    else text = tostring(value) end
    map[text] = number
end

local function order_and_map(entities)
    local ordered = sort_entities(entities)
    local references = {}
    for number, entity in ipairs(ordered) do
        local old_number = entity.entity_number
        entity.entity_number = number
        add_reference(references, entity.id, number)
        add_reference(references, entity.entity_id, number)
        add_reference(references, entity._id, number)
        add_reference(references, entity._serialize_index, number)
        add_reference(references, old_number, number)
        add_reference(references, entity.entity_number, number)
    end
    for _, entity in ipairs(ordered) do entity._serialize_index = nil end
    return ordered, references
end

local function remap(references, value)
    if value == nil then return nil end
    return references[value] or references[tostring(value)] or value
end

local function map_position(value)
    local point = position(value)
    return point and {x = point.x, y = point.y} or nil
end

local function normalized_module(module)
    local id = module
    local quality = "normal"
    local count = 1
    local slot
    local inventory
    if type(module) == "table" then
        id = module.name or module.id or module.prototype
        if type(id) == "table" then
            quality = quality_name(id.quality)
            id = id.name or id.id
        else
            quality = quality_name(module.quality)
        end
        count = math.max(1, math.floor(finite(module.count, 1)))
        slot = module.slot or module.index
        inventory = finite(module.inventory or module.inventory_index)
    end
    if type(id) ~= "string" or id == "" then return nil end
    return {name = id, quality = quality, count = count, slot = slot, inventory = inventory}
end

local function module_inventory(entity)
    local value = entity.module_inventory or entity.inventory
    if type(value) == "table" then value = value.index or value.inventory end
    value = finite(value)
    if value ~= nil then return value end
    if entity.type == "beacon" or entity.kind == "beacon" or entity.name == "beacon" then return 1 end
    return 4
end

local function preformatted_items(items)
    if type(items) ~= "table" then return false end
    for _, item in ipairs(items) do
        if type(item) ~= "table" or type(item.id) ~= "table" or type(item.items) ~= "table" then return false end
    end
    return #items > 0
end

local function normalize_items(items)
    local result = {}
    for _, entry in ipairs(items or {}) do
        local item = copy(entry)
        if type(item.id) == "table" then
            item.id.name = item.id.name or item.id.id
            if quality_name(item.id.quality) == "normal" then item.id.quality = nil end
        end
        if item.items and item.items.in_inventory then
            local slots = {}
            for _, slot in ipairs(item.items.in_inventory) do
                local normalized = copy(slot)
                normalized.inventory = finite(normalized.inventory, 1)
                normalized.stack = finite(normalized.stack, 0)
                slots[#slots + 1] = normalized
            end
            item.items.in_inventory = slots
        end
        result[#result + 1] = item
    end
    return result
end

local function make_items(entity)
    if preformatted_items(entity.items) then return normalize_items(entity.items) end
    local source = entity.modules or entity.module_requests or entity.module_set or (entity.setup and entity.setup.modules)
    if type(source) ~= "table" then return nil end
    local modules, next_slot = {}, 0
    for _, raw in ipairs(source) do
        local module = normalized_module(raw)
        if module then
            local first_slot = module.slot
            for count = 1, module.count do
                local slot = first_slot and first_slot + count - 1 or next_slot
                modules[#modules + 1] = {name = module.name, quality = module.quality,
                    inventory = finite(module.inventory, module_inventory(entity)), stack = slot}
                if not first_slot then next_slot = next_slot + 1 end
            end
            if first_slot then next_slot = math.max(next_slot, first_slot + module.count) end
        end
    end
    if #modules == 0 then return nil end

    local result = {}
    for _, module in ipairs(modules) do
        local previous = result[#result]
        if previous and previous.id.name == module.name and quality_name(previous.id.quality) == module.quality
            and previous.items.in_inventory[#previous.items.in_inventory].inventory == module.inventory then
            previous.items.in_inventory[#previous.items.in_inventory + 1] = {inventory = module.inventory, stack = module.stack}
        else
            local id = {name = module.name}
            if module.quality ~= "normal" then id.quality = module.quality end
            result[#result + 1] = {id = id, items = {in_inventory = {
                {inventory = module.inventory, stack = module.stack},
            }}}
        end
    end
    return result
end

local function wire_tuple(edge)
    if type(edge) ~= "table" then return nil end
    if edge.a_id ~= nil or edge.b_id ~= nil then
        return {edge.a_id or edge.a or edge[1], edge.a_connector or edge.a_connection or edge[2],
            edge.b_id or edge.b or edge[3], edge.b_connector or edge.b_connection or edge[4]}
    end
    if type(edge[1]) == "table" and type(edge[2]) == "table" then
        return {edge[1][1] or edge[1].entity_id or edge[1].id, edge[1][2] or edge[1].connector_id or edge[1].connector,
            edge[2][1] or edge[2].entity_id or edge[2].id, edge[2][2] or edge[2].connector_id or edge[2].connector}
    end
    if edge[1] ~= nil and edge[3] ~= nil then return {edge[1], edge[2], edge[3], edge[4]} end
    return nil
end

local function wire_key(wire)
    return table.concat({tostring(wire[1]), tostring(wire[2]), tostring(wire[3]), tostring(wire[4])}, "\31")
end

local function normalize_wires(source, references)
    local result, seen = {}, {}
    for _, raw in ipairs(list_or_map(source)) do
        local wire = wire_tuple(raw)
        if wire then
            wire[1], wire[3] = remap(references, wire[1]), remap(references, wire[3])
            wire[2], wire[4] = finite(wire[2], wire[2]), finite(wire[4], wire[4])
            local key = wire_key(wire)
            if not seen[key] then seen[key] = true; result[#result + 1] = wire end
        end
    end
    table.sort(result, function(a, b)
        for index = 1, 4 do
            if a[index] ~= b[index] then
                if type(a[index]) == "number" and type(b[index]) == "number" then return a[index] < b[index] end
                return tostring(a[index]) < tostring(b[index])
            end
        end
        return false
    end)
    return result
end

local function global_wires(candidate, references)
    local result = {}
    local root = candidate.candidate or candidate
    local function add(source)
        local wires = normalize_wires(source, references)
        for _, wire in ipairs(wires) do result[#result + 1] = wire end
    end
    add(root.wires)
    add(root.power and root.power.wires)
    add(root.route and root.route.wires)
    add(root.routing and root.routing.wires)
    for _, entity in ipairs(candidate_entities(root)) do add(entity.wires) end
    local unique, seen = {}, {}
    for _, wire in ipairs(result) do
        local key = wire_key(wire)
        if not seen[key] then seen[key] = true; unique[#unique + 1] = wire end
    end
    table.sort(unique, function(a, b) return wire_key(a) < wire_key(b) end)
    return unique
end

--A BLUEPRINT's inserter direction points at its PICKUP: the game takes from the tile the inserter faces and
--drops behind it.  Our internal frame is the prototype's, where `pickup_offset` is +y and `drop_offset` is
---y in the north frame, so internally an inserter with dir=NORTH DROPS north.  Publishing that number
--unchanged shipped every inserter 180 degrees wrong, and no item moved.
--
--Measured on the player's own working factory 2026-09-22, ~/share/RRC/red_science_1s_manual_bp.txt: its belt
--columns run 186.5 to 205.5 and then jump to an isolated 211.5, so nothing inside the factory can feed
--211.5.  Ingredients must therefore arrive at the science machines from 205.5, which makes the hand at
--(206.5, 1076.5) facing WEST the INPUT -- and that is only true when `direction` names the pickup.
--
--docs/feature-contracts.md:172-173 said so all along.  The code, the tests and the byte auditor each
--overrode it, and because all three shared the error nothing could see it.
local function published_direction(entity, direction, catalog)
    if direction == nil then return nil end
    local spec = catalog_entity(catalog, entity)
    local etype = (spec and spec.etype) or entity.etype or entity.kind
    local name = tostring(entity.name or entity.prototype or "")
    --A plain pipe has no direction; the route's travel heading leaked out as `direction` (draftsman flagged 44 on
    --player-inserter-10s, 2026-09-25).  Pipe-to-ground keeps its own.
    if etype == "pipe" or name == "pipe" then return nil end
    if etype ~= "inserter" and not name:find("inserter", 1, true) then return direction end
    return (direction + 8) % 16
end

--The game's own blueprint field for a hand (see serialize_entity): nil when the drop tile is the default one, the tile
--mirrored from the pickup tile through the hand; else the offset to the drop tile's centre plus the game's 0.2 far-lane
--overshoot along the main axis, floored to 1/256 as the engine stores it.
local function hand_drop_vector(at, entity)
    local drop, pickup = position(entity.drop_position), position(entity.pickup_position)
    if not (at and drop) then return nil end
    local tx, ty = math.floor(drop.x), math.floor(drop.y)
    if pickup then
        local mx, my = 2 * at.x - pickup.x, 2 * at.y - pickup.y
        if math.floor(mx) == tx and math.floor(my) == ty then return nil end
    else
        return nil
    end
    local vx, vy = tx + 0.5 - at.x, ty + 0.5 - at.y
    if math.abs(vx) >= math.abs(vy) then vx = vx + (vx < 0 and -0.2 or 0.2) else vy = vy + (vy < 0 and -0.2 or 0.2) end
    return {x = math.floor(vx * 256) / 256, y = math.floor(vy * 256) / 256}
end

local function serialize_entity(entity, references, catalog)
    local result = {entity_number = entity.entity_number, name = entity.name or entity.prototype}
    result.position = entity_position(entity)
    local direction = entity.direction
    if direction == nil then direction = entity.dir end
    direction = published_direction(entity, direction, catalog)
    if direction ~= nil then result.direction = direction end
    local quality = quality_name(entity.quality)
    if quality ~= "normal" then result.quality = quality end
    for _, field in ipairs({"type", "mirror", "tags", "request_filters", "burner_fuel_inventory"}) do
        if entity[field] ~= nil then result[field] = copy(entity[field]) end
    end
    -- The catalog's etype is the bound prototype fact. Never infer this from a vanilla entity name: mods may
    -- provide an assembler or furnace under any name. Standalone serializer fixtures without a catalog retain
    -- their explicit recipe fields for backwards-compatible canonicalization.
    local spec = catalog_entity(catalog, entity)
    local etype = (spec and spec.etype) or entity.etype
    if entity.recipe ~= nil and (etype == nil or etype == "assembling-machine") then
        result.recipe = copy(entity.recipe)
        if entity.recipe_quality ~= nil then result.recipe_quality = copy(entity.recipe_quality) end
    end
    if result.type == nil and (entity.ug_role == "input" or entity.ug_role == "output") then result.type = entity.ug_role end
    if result.recipe ~= nil and result.recipe_quality == nil then result.recipe_quality = "normal" end
    --A hand's drop_position is written exactly as the game writes it (engine probe, headless 2.0.77 player mods incl.
    --bobinserters, 2026-10-05): a hand dropping into its default tile carries NO drop_position; a custom drop is the
    --offset from the hand in world axes, floored to 1/256 ({0, 1.296875} for +1.3). Writing the generator's absolute
    --tile point sent every hand of player-red-science-1s 4-17 tiles away.
    local is_hand = etype == "inserter" or entity.pickup_position ~= nil
    if entity.drop_position ~= nil then
        if is_hand then
            result.drop_position = hand_drop_vector(result.position, entity)
        else
            result.drop_position = map_position(entity.drop_position)
        end
    end

    local items = make_items(entity)
    if items then result.items = items end

    for _, field in ipairs({"ug_pair_id", "partner_id", "port_id"}) do
        if entity[field] ~= nil then result[field] = remap(references, entity[field]) end
    end
    if entity.wires ~= nil then result.wires = normalize_wires(entity.wires, references) end
    return result
end

--A table has no stable text form: `tostring` on one yields its address, which changes every run. That
--address reached the canonical description through the infrastructure block, so the canonical digest of any
--sheet whose belt or inserter setting is a table differed on every single run -- the one number the golden
--suite compares and the release gate binds. Render a table by its own sorted contents instead.
local function stable_text(value, depth)
    if type(value) ~= "table" then return tostring(value) end
    if (depth or 0) > 4 then return "{...}" end
    local parts = {}
    for index, item in ipairs(value) do parts[#parts + 1] = stable_text(item, (depth or 0) + 1) end
    local listed = #value
    for _, key in ipairs(sorted_keys(value)) do
        local numeric = type(key) == "number" and key >= 1 and key <= listed and key % 1 == 0
        if not numeric then
            parts[#parts + 1] = tostring(key) .. "=" .. stable_text(value[key], (depth or 0) + 1)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function description_for(candidate)
    local root = candidate.candidate or candidate
    if type(root.description) == "string" then return root.description end
    if type(root.blueprint) == "table" and type(root.blueprint.description) == "string" then return root.blueprint.description end
    local lines = {"target rates:"}
    local rates = root.target_rates or root.rates or root.targets
    if type(rates) ~= "table" and root.plan then rates = root.plan.rates or root.plan.target_rates end
    if type(rates) == "table" then
        if #rates > 0 then
            local entries = {}
            for _, rate in ipairs(rates) do
                local name = rate.full_name or rate.flow_id or rate.item_name or rate.name
                if name then entries[#entries + 1] = {name = name, rate = finite(rate.rate_per_second or rate.rate, 0)} end
            end
            table.sort(entries, function(a, b) return a.name < b.name end)
            for _, rate in ipairs(entries) do lines[#lines + 1] = rate.name .. "=" .. number_text(rate.rate) .. "/s" end
        else
            for _, key in ipairs(sorted_keys(rates)) do
                local value = rates[key]
                if type(value) == "table" then value = value.rate_per_second or value.rate end
                lines[#lines + 1] = tostring(key) .. "=" .. number_text(value) .. "/s"
            end
        end
    end
    local ports = root.external_ports or root.ports or (root.plan and root.plan.ports) or {}
    lines[#lines + 1] = "external ports:"
    local port_list = list_or_map(ports)
    table.sort(port_list, function(a, b)
        return tostring(a.port_id or a.id or a.full_name or "") < tostring(b.port_id or b.id or b.full_name or "")
    end)
    for _, port in ipairs(port_list) do
        local id = port.port_id or port.id or port.full_name
        if id then lines[#lines + 1] = tostring(id) .. "=" .. number_text(port.rate_per_second or port.rate or 0) .. "/s" end
    end
    local infrastructure = root.infrastructure or (root.settings and root.settings.infrastructure) or root.options and root.options.infrastructure
    lines[#lines + 1] = "infrastructure:"
    if type(infrastructure) == "string" then
        lines[#lines + 1] = infrastructure
    elseif type(infrastructure) == "table" then
        for _, key in ipairs(sorted_keys(infrastructure)) do
            lines[#lines + 1] = tostring(key) .. "=" .. stable_text(infrastructure[key])
        end
    end
    return table.concat(lines, "\n")
end

local function metadata_for(candidate)
    local root = candidate.candidate or candidate
    local blueprint = type(root.blueprint) == "table" and root.blueprint or {}
    local label = root.label or blueprint.label
    local icons = root.icons or blueprint.icons
    local result = {label = label, icons = copy(icons), description = description_for(root)}
    if result.label == nil then result.label = "Recursive Resource Calculator" end
    if result.icons == nil then result.icons = {} end
    return result
end

--(y, x, id): the order entity numbers are handed out in.  The second return value is the old-id -> new-number map;
--callers that only need the ordered entities can ignore it.
function Serialize.entity_order(entities)
    return order_and_map(list_or_map(entities))
end

function Serialize.begin(input)
    input = type(input) == "table" and input or {}
    --No whole-input copy (round 56 gate: 2.9 M instructions in blue's success tick): every entity serialize writes is
    --a copy already (block_entities, sort_entities), and the rest is only read.
    local entities = candidate_entities(input)
    local ordered, references = Serialize.entity_order(entities)
    return {
        done = false, ok = nil,
        cursor = {entity_index = 1, phase = "serializing"},
        progress = {phase = "serializing", done_units = 0, total_units = #ordered},
        work = {candidate = input, entities = ordered, references = references, wires = global_wires(input, references), output = {}},
    }
end

function Serialize.step(state, budget)
    if state.done then return state end
    budget = type(budget) == "table" and budget or {ops = 1}
    local ops = finite(budget.ops, 1)
    if ops < 0 then ops = 0 end
    while ops > 0 and state.cursor.entity_index <= #state.work.entities do
        local entity = state.work.entities[state.cursor.entity_index]
        state.work.output[#state.work.output + 1] = serialize_entity(entity, state.work.references,
            state.work.candidate.catalog)
        state.cursor.entity_index = state.cursor.entity_index + 1
        state.progress.done_units = state.progress.done_units + 1
        if ops ~= math.huge then ops = ops - 1 end
    end
    budget.ops = ops
    if state.cursor.entity_index > #state.work.entities then
        local metadata = metadata_for(state.work.candidate)
        state.result = {entities = state.work.output, label = metadata.label, icons = metadata.icons,
            description = metadata.description}
        if #state.work.wires > 0 then state.result.wires = state.work.wires end
        state.done, state.ok = true, true
        state.cursor.phase, state.progress.phase = "done", "done"
    end
    return state
end

local function canonical_entities(entities)
    local ordered, references = Serialize.entity_order(entities)
    local minimum_x, minimum_y
    for _, entity in ipairs(ordered) do
        local point = entity_position(entity)
        minimum_x = minimum_x and math.min(minimum_x, point.x) or point.x
        minimum_y = minimum_y and math.min(minimum_y, point.y) or point.y
    end
    minimum_x, minimum_y = minimum_x or 0, minimum_y or 0
    local result = {}
    for _, entity in ipairs(ordered) do
        local normalized = serialize_entity(entity, references)
        normalized.position = {x = normalized.position.x - minimum_x, y = normalized.position.y - minimum_y}
        result[#result + 1] = normalized
    end
    return result, references
end

--The comparable form of a blueprint table, plus the version of these rules it was produced under.
function Serialize.canonical(blueprint)
    blueprint = type(blueprint) == "table" and blueprint or {}
    local wrapped = type(blueprint.blueprint) == "table" and blueprint.entities == nil
    local source = wrapped and blueprint.blueprint or blueprint
    local entities, references = canonical_entities(source.entities or {})
    local result = {entities = entities}
    if source.label ~= nil then result.label = copy(source.label) end
    if source.icons ~= nil then result.icons = copy(source.icons) end
    if source.description ~= nil then result.description = copy(source.description) end
    local wires = normalize_wires(source.wires, references)
    if #wires > 0 then result.wires = wires end
    if wrapped then result = {blueprint = result} end
    return result, Serialize.CANONICAL_VERSION
end

return Serialize

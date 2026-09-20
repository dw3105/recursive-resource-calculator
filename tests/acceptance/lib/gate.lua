--The delivery assertion: a chain must reach a successful, independently validated, non-empty blueprint.
--Nothing here stubs a stage. Validate and Serialize are wrapped only to observe which candidate passed the
--independent check and which candidate was published, so a success cannot come from an unchecked layout.
local H = require "tests.harness"

local M = {}

local function number_text(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return tostring(value)
    end
    if value == math.floor(value) then return string.format("%.0f", value) end
    return string.format("%.17g", value)
end

--The gate has to compare data, not table identity or iteration order. This encoder is deliberately local to the
--test instrumentation: it is a stable representation for the plain values that make up a blueprint's content.
local function stable_value(value, seen)
    local value_type = type(value)
    if value == nil then return "n" end
    if value_type == "boolean" then return value and "b1" or "b0" end
    if value_type == "number" then return "d" .. number_text(value) end
    if value_type == "string" then return "s" .. tostring(#value) .. ":" .. value end
    if value_type ~= "table" then return "t" .. value_type end

    seen = seen or {}
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key, _ in pairs(value) do
        if type(key) == "string" or type(key) == "number" or type(key) == "boolean" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right)
        local left_type, right_type = type(left), type(right)
        if left_type ~= right_type then return left_type < right_type end
        if left_type == "number" then return left < right end
        return tostring(left) < tostring(right)
    end)
    local parts = {"{"}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = stable_value(key, seen) .. "=" .. stable_value(value[key], seen) .. ";"
    end
    parts[#parts + 1] = "}"
    seen[value] = nil
    return table.concat(parts)
end

local function list_or_map(source)
    if type(source) ~= "table" then return {} end
    if #source > 0 then
        local result = {}
        for index, value in ipairs(source) do result[#result + 1] = {value = value, order = index} end
        return result
    end
    local keys = {}
    for key, _ in pairs(source) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local result = {}
    for index, key in ipairs(keys) do result[#result + 1] = {value = source[key], order = index} end
    return result
end

local function entity_id(entity, fallback)
    if type(entity) ~= "table" then return fallback end
    return entity.id or entity.entity_id or entity._id or entity.entity_number or fallback
end

local function entity_name(entity)
    local value = type(entity) == "table" and (entity.name or entity.prototype or entity.entity) or nil
    if type(value) == "table" then return value.name or value.id or value.prototype end
    return value
end

local function finite(value)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function entity_position(entity)
    local point = type(entity) == "table" and entity.position or nil
    if type(point) == "table" then
        local x, y = finite(point.x or point[1]), finite(point.y or point[2])
        if x ~= nil and y ~= nil then return {x = x, y = y} end
    end
    local x, y = finite(entity and entity.x), finite(entity and entity.y)
    if x == nil or y == nil then return nil end
    local width, height = finite(entity.w or entity.width), finite(entity.h or entity.height)
    if width ~= nil and height ~= nil then return {x = x + width / 2, y = y + height / 2} end
    return {x = x, y = y}
end

local function quality_name(value)
    if type(value) == "table" then value = value.name or value.id end
    return type(value) == "string" and value ~= "" and value or "normal"
end

local function append_entities(source, result, seen)
    for _, entry in ipairs(list_or_map(source)) do
        local entity = entry.value
        if type(entity) == "table" then
            local id = entity_id(entity, entry.order)
            local key = stable_value(id)
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = {entity = entity, id = id, order = #result + 1}
            end
        end
    end
end

local function candidate_root(candidate)
    if type(candidate) ~= "table" then return {} end
    if type(candidate.candidate) == "table" and candidate.entities == nil then return candidate.candidate end
    return candidate
end

local function candidate_entities(candidate)
    local root = candidate_root(candidate)
    local result, seen = {}, {}
    append_entities(root.entities, result, seen)
    append_entities(root.placed_entities, result, seen)
    append_entities(root.layout and root.layout.entities, result, seen)
    append_entities(root.route and root.route.entities, result, seen)
    append_entities(root.routing and root.routing.entities, result, seen)
    append_entities(root.power and root.power.entities, result, seen)
    append_entities(root.infrastructure and root.infrastructure.entities, result, seen)
    append_entities(root.result and root.result.entities, result, seen)
    table.sort(result, function(left, right)
        local left_key, right_key = stable_value(left.id), stable_value(right.id)
        if left_key ~= right_key then return left_key < right_key end
        return left.order < right.order
    end)
    return result
end

local function module_loadout(entity)
    if type(entity.items) == "table" and #entity.items > 0 then return entity.items end
    return entity.modules or entity.module_loadout or entity.module_requests or entity.module_set
        or (entity.setup and entity.setup.modules)
end

local function wire_tuple(edge)
    if type(edge) ~= "table" then return nil end
    if edge.a_id ~= nil or edge.b_id ~= nil then
        return {edge.a_id or edge.a or edge[1], edge.a_connector or edge.a_connection or edge[2],
            edge.b_id or edge.b or edge[3], edge.b_connector or edge.b_connection or edge[4]}
    end
    if type(edge[1]) == "table" and type(edge[2]) == "table" then
        return {edge[1][1] or edge[1].entity_id or edge[1].id,
            edge[1][2] or edge[1].connector_id or edge[1].connector,
            edge[2][1] or edge[2].entity_id or edge[2].id,
            edge[2][2] or edge[2].connector_id or edge[2].connector}
    end
    if edge[1] ~= nil and edge[3] ~= nil then return {edge[1], edge[2], edge[3], edge[4]} end
end

local function candidate_wires(candidate, entities)
    local root = candidate_root(candidate)
    local result, seen = {}, {}
    local function add(source)
        for _, entry in ipairs(list_or_map(source)) do
            local tuple = wire_tuple(entry.value)
            if tuple then
                local key = stable_value(tuple)
                if not seen[key] then
                    seen[key] = true
                    result[#result + 1] = {tuple = tuple, edge = entry.value}
                end
            end
        end
    end
    add(root.wires)
    add(root.power and root.power.wires)
    add(root.route and root.route.wires)
    add(root.routing and root.routing.wires)
    for _, entry in ipairs(entities) do add(entry.entity.wires) end
    table.sort(result, function(left, right) return stable_value(left.tuple) < stable_value(right.tuple) end)
    return result
end

local function content_digest(candidate)
    local entities = candidate_entities(candidate)
    local fields = {{name = "entity count", value = stable_value(#entities)}}
    for _, entry in ipairs(entities) do
        local entity, id = entry.entity, entry.id
        local label = "entity " .. tostring(id)
        fields[#fields + 1] = {name = label .. " id", value = stable_value(id)}
        fields[#fields + 1] = {name = label .. " name", value = stable_value(entity_name(entity))}
        fields[#fields + 1] = {name = label .. " position", value = stable_value(entity_position(entity))}
        fields[#fields + 1] = {name = label .. " direction", value = stable_value(entity.direction or entity.dir)}
        fields[#fields + 1] = {name = label .. " quality", value = stable_value(quality_name(entity.quality))}
        fields[#fields + 1] = {name = label .. " recipe", value = stable_value({value = entity.recipe,
            quality = entity.recipe_quality})}
        fields[#fields + 1] = {name = label .. " module loadout", value = stable_value(module_loadout(entity))}
    end
    local wires = candidate_wires(candidate, entities)
    fields[#fields + 1] = {name = "wire endpoints count", value = stable_value(#wires)}
    for index, wire in ipairs(wires) do
        fields[#fields + 1] = {name = "wire endpoints " .. tostring(index), value = stable_value(wire.tuple)}
    end
    local chunks = {}
    for _, field in ipairs(fields) do
        chunks[#chunks + 1] = tostring(#field.name) .. ":" .. field.name .. "="
            .. tostring(#field.value) .. ":" .. field.value
    end
    return {text = table.concat(chunks, "\30"), fields = fields}
end

local function first_difference(expected, actual)
    if type(expected) ~= "table" or type(actual) ~= "table" then return "content" end
    local length = math.max(#expected.fields, #actual.fields)
    for index = 1, length do
        local left, right = expected.fields[index], actual.fields[index]
        if left == nil then return right.name end
        if right == nil then return left.name end
        if left.name ~= right.name then return left.name end
        if left.value ~= right.value then return left.name end
    end
    return "content"
end

local function mutate_position(entity)
    local point = entity_position(entity) or {x = 0, y = 0}
    entity.position = {x = point.x + 1, y = point.y}
end

local function mutate_module(entity)
    local source = entity.modules or entity.module_loadout or entity.module_requests or entity.module_set
        or (entity.setup and entity.setup.modules)
    if type(source) ~= "table" or #source == 0 then return false end
    local module = source[1]
    if type(module) == "table" then
        if module.name ~= nil then module.name = tostring(module.name) .. "-digest" end
        if module.name == nil and module.id ~= nil then module.id = tostring(module.id) .. "-digest" end
        if module.name == nil and module.id == nil then module.quality = "uncommon" end
    else
        source[1] = tostring(module) .. "-digest"
    end
    return true
end

local function mutate_wire(edge)
    if type(edge) ~= "table" then return false end
    if edge.a_id ~= nil then edge.a_id = tostring(edge.a_id) .. "-digest"; return true end
    if edge.b_id ~= nil then edge.b_id = tostring(edge.b_id) .. "-digest"; return true end
    if type(edge[1]) == "table" and type(edge[2]) == "table" then
        local endpoint = edge[1]
        if endpoint.entity_id ~= nil then endpoint.entity_id = tostring(endpoint.entity_id) .. "-digest"
        elseif endpoint.id ~= nil then endpoint.id = tostring(endpoint.id) .. "-digest"
        else endpoint[1] = tostring(endpoint[1]) .. "-digest" end
        return true
    end
    if edge[1] ~= nil then edge[1] = tostring(edge[1]) .. "-digest"; return true end
    return false
end

local function mutate_candidate(candidate, kind)
    local entities = candidate_entities(candidate)
    if kind == "position" then
        if entities[1] then mutate_position(entities[1].entity); return true end
    elseif kind == "module" then
        for _, entry in ipairs(entities) do if mutate_module(entry.entity) then return true end end
    elseif kind == "wire" then
        for _, wire in ipairs(candidate_wires(candidate, entities)) do
            if mutate_wire(wire.edge) then return true end
        end
    end
    return false
end

--Observers stay installed for one run and are removed again, so one case never changes another's modules.
local function observe(options)
    local Validate = require "logic.bp.validate"
    local Serialize = require "logic.bp.serialize"
    local record = {validated_ok = {}, accepted = {}, serialized = nil, serialize_source = nil,
        serialized_digest = nil, validate_calls = 0, validate_ok = 0, validate_bad = 0, codes = {}}
    local validate_begin, validate_step = Validate.begin, Validate.step
    local serialize_begin = Serialize.begin

    Validate.begin = function(input)
        record.validate_calls = record.validate_calls + 1
        local state = validate_begin(input)
        local digest = content_digest(input and input.candidate)
        state.__gate_candidate = digest.text
        record.accepted[digest.text] = digest
        return state
    end
    Validate.step = function(state, budget)
        local out = validate_step(state, budget)
        if out and out.done and not out.__gate_counted then
            out.__gate_counted = true
            local result = out.result or {}
            local ok = out.ok ~= false and result.ok ~= false and #(result.errors or {}) == 0
            if ok then
                record.validate_ok = record.validate_ok + 1
                record.validated_ok[state.__gate_candidate or ""] = true
            else
                record.validate_bad = record.validate_bad + 1
                for _, error_record in ipairs(result.errors or out.errors or {}) do
                    local code = type(error_record) == "table" and error_record.code or error_record
                    record.codes[tostring(code)] = (record.codes[tostring(code)] or 0) + 1
                end
            end
        end
        return out
    end
    Serialize.begin = function(candidate)
        local source_digest = content_digest(candidate)
        record.serialize_source = source_digest.text
        if options and options.mutate_after_validation then
            mutate_candidate(candidate, options.mutate_after_validation)
        end
        record.serialized_digest = content_digest(candidate)
        record.serialized = record.serialized_digest.text
        return serialize_begin(candidate)
    end

    record.restore = function()
        Validate.begin, Validate.step = validate_begin, validate_step
        Serialize.begin = serialize_begin
    end
    return record
end

local function code_list(record)
    local names = {}
    for code in pairs(record.codes) do names[#names + 1] = code end
    table.sort(names)
    local parts = {}
    for _, code in ipairs(names) do parts[#parts + 1] = code .. "x" .. record.codes[code] end
    return table.concat(parts, ",")
end

--Drive the real generation service until it is terminal, then demand a delivered blueprint.
function M.demand_success(chain, options)
    options = options or {}
    local record = observe(options)
    local Generation = require "logic.bp.generation"
    local settings = require("logic.bp.settings").of_sheet(1, chain.sheet_id)
    local start = {player_index = 1, sheet_id = chain.sheet_id, settings = settings, deliver = true}
    if options.search_budget then start.options = {search_budget = options.search_budget} end
    local job_id = Generation.start(start)
    local result = Generation.status(1, job_id)
    local ticks = 0
    local limit = options.ticks or 1200
    while result.state == "pending" and ticks < limit do
        H.run_ticks(chain.world, 1)
        ticks = ticks + 1
        result = Generation.status(1, job_id)
    end
    record.restore()

    local detail = chain.name .. ": state=" .. tostring(result.state)
        .. " stage=" .. tostring(result.stage or result.phase)
        .. " codes=" .. table.concat(result.reason_codes or {}, ",")
        .. " ticks=" .. tostring(ticks)
        .. " validate calls=" .. tostring(record.validate_calls)
        .. " ok=" .. tostring(record.validate_ok) .. " rejected=" .. tostring(record.validate_bad)
        .. " rejections=" .. code_list(record)
    print("GATE " .. detail)

    H.equal(result.state, "success", "the chain reaches a delivered blueprint; " .. detail)
    H.equal(record.validate_calls > 0, true, "at least one candidate reached the independent validator")
    H.equal(record.validate_ok > 0, true, "an accepted candidate passed the independent validator")
    H.equal(record.serialized ~= nil, true, "a candidate was serialized")
    H.equal(record.validated_ok[record.serialized] == true, true,
        "the serialized candidate is the one the validator accepted; first differing field: "
        .. first_difference(record.accepted[record.serialize_source], record.serialized_digest))
    local stack = game.players[1].cursor_stack
    H.equal(stack.is_blueprint_setup(), true, "the blueprint is delivered to the player")
    local entities = stack.get_blueprint_entities()
    H.equal(entities ~= nil and #entities > 0, true, "the delivered blueprint carries entities")
    return result
end

return M

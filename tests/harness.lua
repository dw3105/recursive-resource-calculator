--Offline test harness: mocks just enough of the Factorio runtime API to drive the mod's logic and GUI code from plain Lua
--Mock strictness follows the engine: LuaObjects throw on unknown members, concept tables are plain Lua tables, custom tables return nil for unknown names
package.path = "./?.lua;" .. package.path

local H = {}

local TOLERANCE = 1e-9

local function set_of(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

--Factorio 2.0 LuaObjects (prototypes, players, GUI elements) are userdata, not tables, so type() reports "userdata" for every mocked one.
--The harness itself looks inside its mocks with raw_type.
local raw_type = type
local lua_objects = setmetatable({}, {__mode = "k"})
_G.type = function(value)
    if lua_objects[value] then return "userdata" end
    return raw_type(value)
end

--LuaObject: reading or writing a key outside its member list errors like the engine does.
--gates: member -> set of prototype types it can be used on; reading it unset on another type errors (conservative assumption, not established for every member)
--accessors: member -> {read = function(object), write = function(object, value)}; such members never live in the table, so every read and write reaches them
function H.lua_object(class, fields, members, gates, accessors)
    local allowed = set_of(members)
    for key, _ in pairs(fields) do
        if not allowed[key] then error("fixture sets non-member " .. class .. "." .. key, 2) end
        if accessors and accessors[key] then error("fixture sets accessor member " .. class .. "." .. key .. " directly", 2) end
    end
    lua_objects[fields] = true
    return setmetatable(fields, {
        __index = function(object, key)
            local accessor = accessors and accessors[key]
            if accessor and allowed[key] then
                if not accessor.read then error(class .. "::" .. key .. " is write-only", 2) end
                return accessor.read(object)
            end
            if allowed[key] then
                local types = gates and gates[key]
                if types and not types[rawget(object, "type")] then
                    error(class .. "::" .. key .. " can only be used if this is " .. types.names, 2)
                end
                return nil
            end
            error(class .. " doesn't contain key " .. tostring(key), 2)
        end,
        __newindex = function(object, key, value)
            if not allowed[key] then error(class .. " doesn't contain key " .. tostring(key), 2) end
            local accessor = accessors and accessors[key]
            if accessor then
                if not accessor.write then error(class .. "::" .. key .. " is read-only", 2) end
                accessor.write(object, value)
                return
            end
            rawset(object, key, value)
        end,
    })
end

local RECIPE_MEMBERS = {
    ["2.0"] = {"name", "valid", "object_name", "localised_name", "hidden", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "category", "additional_categories"},
    ["2.1"] = {"name", "valid", "object_name", "localised_name", "hidden", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "categories", "get_product_amount"},
    --shape the code at cb6b529 expects: 2.1 recipe members with 2.0 product fields (portal 1.1.9 on Factorio 2.0.77)
    ["hybrid"] = {"name", "valid", "object_name", "localised_name", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "category", "additional_categories", "categories"},
}

local ENTITY_MEMBERS = {"name", "type", "valid", "localised_name", "crafting_categories", "effect_receiver", "energy_usage", "allowed_effects",
    "get_crafting_speed", "get_max_energy_usage", "electric_energy_source_prototype", "burner_prototype", "heat_energy_source_prototype",
    "fluid_energy_source_prototype", "void_energy_source_prototype", "module_inventory_size", "get_inventory_size", "allowed_module_categories",
    "quality_affects_module_slots", "module_slots_quality_bonus", "distribution_effectivity", "distribution_effectivity_bonus_per_quality_level",
    "profile", "beacon_counter", "get_max_power_output", "items_to_place_this", "hidden",
    --round 8 geometry and infrastructure, every name taken from docs/api/*.members.json (see tests/test_api_shapes.lua):
    "collision_box", "collision_mask", "tile_width", "tile_height", "flags", "fluidbox_prototypes",
    "belt_speed", "related_underground_belt", "max_underground_distance",
    "inserter_pickup_position", "inserter_drop_position", "inserter_stack_size_bonus", "inserter_max_belt_stack_size",
    --Both are methods in the pinned extract, never attributes; a quality argument selects the value.
    "get_inserter_rotation_speed", "get_inserter_extension_speed",
    "logistic_radius", "construction_radius", "connection_distance",
    "quality_affects_supply_area_distance", "get_supply_area_distance", "get_max_wire_distance"}
local ITEM_MEMBERS = {"name", "type", "valid", "localised_name", "module_effects", "get_module_effects", "category",
    "fuel_value", "fuel_category", "burnt_result", "fuel_emissions_multiplier", "hidden", "parameter",
    --Spoilage: preflight reads spoil_result to refuse a spoiling ingredient or product. The tick count is a
    --method in the pinned extract (get_spoil_ticks), never an attribute.
    "spoil_result", "get_spoil_ticks"}
local QUALITY_MEMBERS = {"name", "valid", "localised_name", "level", "next", "next_probability", "crafting_machine_module_slots_bonus", "beacon_module_slots_bonus",
    "beacon_power_usage_multiplier", "hidden"}

local function gate(types)
    local set = set_of(types)
    set.names = table.concat(types, " or ")
    return set
end
local CRAFTING_MACHINE_TYPES = {"assembling-machine", "furnace", "rocket-silo"}
local ENTITY_GATES = {
    get_max_power_output = gate({"burner-generator", "generator"}),
    crafting_categories = gate(CRAFTING_MACHINE_TYPES),
    get_crafting_speed = gate(CRAFTING_MACHINE_TYPES),
    quality_affects_module_slots = gate({"beacon", "assembling-machine", "furnace", "rocket-silo", "mining-drill", "lab"}),
    --round 8: members only their own entity type carries, so code cannot read a belt speed off a machine
    belt_speed = gate({"transport-belt", "underground-belt", "splitter", "loader", "loader-1x1"}),
    related_underground_belt = gate({"underground-belt"}),
    max_underground_distance = gate({"underground-belt", "pipe-to-ground"}),
    inserter_pickup_position = gate({"inserter"}),
    inserter_drop_position = gate({"inserter"}),
    inserter_stack_size_bonus = gate({"inserter"}),
    inserter_max_belt_stack_size = gate({"inserter"}),
    logistic_radius = gate({"roboport"}),
    construction_radius = gate({"roboport"}),
    connection_distance = gate({"roboport"}),
    get_supply_area_distance = gate({"electric-pole", "beacon"}),
    quality_affects_supply_area_distance = gate({"electric-pole", "beacon"}),
    get_max_wire_distance = gate({"electric-pole", "power-switch"}),
}
local ITEM_GATES = {module_effects = gate({"module"}), get_module_effects = gate({"module"}), category = gate({"module"})}

local EFFECT_NAMES = {"consumption", "speed", "productivity", "pollution", "quality"}

--dictionary[effect -> boolean] over all five effects from a list of allowed ones; nil list gives nil unless every effect is the default
local function effect_dictionary(list, all_by_default)
    if list == nil and not all_by_default then return nil end
    local allowed = set_of(list or EFFECT_NAMES)
    local dictionary = {}
    for _, effect in ipairs(EFFECT_NAMES) do dictionary[effect] = allowed[effect] == true end
    return dictionary
end

--Prototype-doc rule for module slots at a quality: base slots, plus, when quality affects slots, the entity's own bonus for that quality or else the quality's bonus
local function module_slots_at(base, affected, own_bonus_by_quality, quality_bonus_member, quality)
    if not affected or quality == nil then return base end
    local quality_prototype = prototypes.quality[quality]
    if not quality_prototype then error("Unknown quality " .. tostring(quality), 3) end
    local own = own_bonus_by_quality and own_bonus_by_quality[quality]
    if own ~= nil then return base + own end
    return base + quality_prototype[quality_bonus_member]
end
--2.1 fluids carry a spent fluid specification; 2.0 fluids do not have the member
local FLUID_MEMBERS = {["2.0"] = {"name", "valid", "localised_name", "fuel_value", "emissions_multiplier"},
    ["2.1"] = {"name", "valid", "localised_name", "fuel_value", "emissions_multiplier", "spent_fluid"}}
FLUID_MEMBERS.hybrid = FLUID_MEMBERS["2.0"]
local ENERGY_SOURCE_MEMBERS = {"emissions_per_joule"}
local BURNER_MEMBERS = {"valid", "emissions_per_joule", "effectivity", "fuel_inventory_size", "burnt_inventory_size", "fuel_categories"}
--LuaFluidEnergySourcePrototype per 2.0.77 and 2.1.17: output_fluid_box and spent_fluid are new in 2.1
local FLUID_ENERGY_SOURCE_MEMBERS = {
    ["2.0"] = {"valid", "emissions_per_joule", "effectivity", "burns_fluid", "scale_fluid_usage", "fluid_usage_per_tick", "maximum_temperature", "fluid_box"},
    ["2.1"] = {"valid", "emissions_per_joule", "effectivity", "burns_fluid", "scale_fluid_usage", "fluid_usage_per_tick", "maximum_temperature", "fluid_box",
        "output_fluid_box", "spent_fluid"},
}
FLUID_ENERGY_SOURCE_MEMBERS.hybrid = FLUID_ENERGY_SOURCE_MEMBERS["2.0"]
--LuaFluidBoxPrototype: pipe_connections is where a machine's real fluid geometry lives. Its entries are concept
--tables (plain Lua tables), and at runtime each carries positions (one MapPosition per cardinal orientation),
--direction, connection_type and flow_direction. 2.1 adds alt_direction/alt_position. The data-stage singular
--"position" shape does not exist here, so code cannot read a field the engine never returns.
--2.0.77 carries volume; 2.1.19 dropped it, so a catalog that reads volume on 2.1 gets the engine's refusal here
local FLUID_BOX_MEMBERS = {
    ["2.0"] = {"valid", "filter", "index", "production_type", "volume", "pipe_connections", "minimum_temperature", "maximum_temperature"},
    ["2.1"] = {"valid", "filter", "index", "production_type", "pipe_connections", "minimum_temperature", "maximum_temperature"},
}
FLUID_BOX_MEMBERS.hybrid = FLUID_BOX_MEMBERS["2.0"]
local FORCE_RECIPE_MEMBERS = {"name", "valid", "productivity_bonus"}
local FORCE_MEMBERS = {"name", "valid", "recipes", "players", "is_quality_unlocked"}
local PLAYER_MEMBERS = {"index", "name", "valid", "force", "gui", "opened", "create_local_flying_text", "cursor_ghost", "cursor_stack", "clear_cursor",
    "is_cursor_empty", "cursor_record"}
--LuaItemStack per 2.0.77, the members the cursor stack mock serves; quality reads as LuaQualityPrototype
local ITEM_STACK_MEMBERS = {"valid", "valid_for_read", "name", "quality", "count", "prototype",
    --round 8 blueprint delivery; set_blueprint_entities and friends are LuaItemCommon members LuaItemStack inherits
    "set_stack", "clear", "is_blueprint", "is_blueprint_setup", "get_blueprint_entities", "set_blueprint_entities",
    "label", "label_color", "preview_icons", "default_icons", "blueprint_description"}
local HELPERS_MEMBERS = {"compare_versions", "is_valid_sprite_path", "table_to_json", "json_to_table", "encode_string", "decode_string"}

--------------------------------------------------------------------------------
--helpers.table_to_json / json_to_table / encode_string / decode_string
--
--The engine's encode_string is "compression plus Base64", not Base64 of the plain string, and the mod's debug export
--is specified to decode offline with python3 base64.b64decode + zlib.decompress. So this mock emits a real zlib
--stream: 0x78 0x01 header, deflate STORED blocks (BTYPE 00, byte aligned, max 65535 bytes each), adler32 trailer.
--Stored blocks compress nothing, which does not matter for a test: what matters is that the bytes a decoder gets
--are a zlib stream, so the documented offline decoder is exercised rather than assumed.
--------------------------------------------------------------------------------

local function adler32(data)
    local a, b = 1, 0
    for index = 1, #data do
        a = (a + data:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
    local out, length = {}, #data
    for index = 1, length, 3 do
        local b1, b2, b3 = data:byte(index), data:byte(index + 1), data:byte(index + 2)
        local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        local chunk = BASE64_ALPHABET:sub(c1 + 1, c1 + 1) .. BASE64_ALPHABET:sub(c2 + 1, c2 + 1)
        chunk = chunk .. (b2 and BASE64_ALPHABET:sub(c3 + 1, c3 + 1) or "=")
        chunk = chunk .. (b3 and BASE64_ALPHABET:sub(c4 + 1, c4 + 1) or "=")
        out[#out + 1] = chunk
    end
    return table.concat(out)
end

local BASE64_VALUES = {}
for index = 1, #BASE64_ALPHABET do BASE64_VALUES[BASE64_ALPHABET:sub(index, index)] = index - 1 end

local function base64_decode(text)
    text = text:gsub("%s", ""):gsub("=", "")
    local out, bits, count = {}, 0, 0
    for index = 1, #text do
        local value = BASE64_VALUES[text:sub(index, index)]
        if value == nil then return nil end
        bits, count = bits * 64 + value, count + 6
        if count >= 8 then
            count = count - 8
            local byte = math.floor(bits / 2 ^ count)
            bits = bits - byte * 2 ^ count
            out[#out + 1] = string.char(byte)
        end
    end
    return table.concat(out)
end

local function little_endian_16(value) return string.char(value % 256, math.floor(value / 256) % 256) end

local function zlib_deflate_stored(data)
    local parts = {string.char(0x78, 0x01)}
    local length, offset = #data, 0
    repeat
        local size = math.min(65535, length - offset)
        local final = (offset + size >= length) and 1 or 0
        parts[#parts + 1] = string.char(final)
        parts[#parts + 1] = little_endian_16(size)
        parts[#parts + 1] = little_endian_16(65535 - size)
        parts[#parts + 1] = data:sub(offset + 1, offset + size)
        offset = offset + size
    until offset >= length
    local sum = adler32(data)
    parts[#parts + 1] = string.char(math.floor(sum / 16777216) % 256, math.floor(sum / 65536) % 256,
        math.floor(sum / 256) % 256, sum % 256)
    return table.concat(parts)
end

local function zlib_inflate_stored(data)
    if #data < 6 or data:byte(1) ~= 0x78 then return nil end
    local out, position = {}, 3
    while position <= #data - 4 do
        local header = data:byte(position)
        local btype = math.floor(header / 2) % 4
        if btype ~= 0 then return nil end --this mock never emits compressed blocks
        local size = data:byte(position + 1) + data:byte(position + 2) * 256
        out[#out + 1] = data:sub(position + 5, position + 4 + size)
        position = position + 5 + size
        if header % 2 == 1 then break end
    end
    return table.concat(out)
end

--JSON writer matching what the export needs: arrays for 1..n tables, objects otherwise with sorted keys (so one
--unchanged payload always serializes to one string), full precision numbers, no NaN or infinity.
local function json_escape(text)
    local escaped = text:gsub('[%c"\\]', function(character)
        local known = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f"}
        return known[character] or string.format("\\u%04x", character:byte())
    end)
    return '"' .. escaped .. '"'
end

local function json_number(value)
    if value ~= value or value == math.huge or value == -math.huge then
        error("helpers.table_to_json cannot serialize " .. tostring(value), 3)
    end
    if value == math.floor(value) and math.abs(value) < 2 ^ 53 then return string.format("%d", value) end
    return string.format("%.17g", value)
end

local function json_write(value, out)
    local value_type = raw_type(value)
    if value == nil then out[#out + 1] = "null"
    elseif value_type == "boolean" then out[#out + 1] = tostring(value)
    elseif value_type == "number" then out[#out + 1] = json_number(value)
    elseif value_type == "string" then out[#out + 1] = json_escape(value)
    elseif value_type == "table" then
        local count = #value
        local is_array = count > 0
        if is_array then
            for key in pairs(value) do
                if raw_type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then is_array = false break end
            end
        end
        if is_array then
            out[#out + 1] = "["
            for index = 1, count do
                if index > 1 then out[#out + 1] = "," end
                json_write(value[index], out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = tostring(key) end
            table.sort(keys)
            out[#out + 1] = "{"
            for index, key in ipairs(keys) do
                if index > 1 then out[#out + 1] = "," end
                out[#out + 1] = json_escape(key) .. ":"
                json_write(value[key] ~= nil and value[key] or value[tonumber(key)], out)
            end
            out[#out + 1] = "}"
        end
    else
        error("helpers.table_to_json cannot serialize a " .. value_type, 3)
    end
end

local function table_to_json(value)
    local out = {}
    json_write(value, out)
    return table.concat(out)
end

--Small reader, enough for the round trips the tests make; objects come back with string keys, arrays as 1..n
local function json_to_table(text)
    local position = 1
    local parse_value

    local function skip_space() position = text:find("[^ \t\r\n]", position) or #text + 1 end

    local function parse_string()
        position = position + 1
        local out = {}
        while true do
            local character = text:sub(position, position)
            if character == "" then error("helpers.json_to_table: unterminated string", 4) end
            if character == '"' then position = position + 1 break end
            if character == "\\" then
                local escape = text:sub(position + 1, position + 1)
                local known = {n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/"}
                if escape == "u" then
                    out[#out + 1] = string.char(tonumber(text:sub(position + 2, position + 5), 16) % 256)
                    position = position + 6
                else
                    out[#out + 1] = known[escape] or escape
                    position = position + 2
                end
            else
                out[#out + 1] = character
                position = position + 1
            end
        end
        return table.concat(out)
    end

    parse_value = function()
        skip_space()
        local character = text:sub(position, position)
        if character == "{" then
            local object = {}
            position = position + 1
            skip_space()
            if text:sub(position, position) == "}" then position = position + 1 return object end
            while true do
                skip_space()
                local key = parse_string()
                skip_space()
                position = position + 1 --colon
                object[key] = parse_value()
                skip_space()
                local separator = text:sub(position, position)
                position = position + 1
                if separator == "}" then return object end
            end
        elseif character == "[" then
            local array = {}
            position = position + 1
            skip_space()
            if text:sub(position, position) == "]" then position = position + 1 return array end
            while true do
                array[#array + 1] = parse_value()
                skip_space()
                local separator = text:sub(position, position)
                position = position + 1
                if separator == "]" then return array end
            end
        elseif character == '"' then
            return parse_string()
        elseif text:sub(position, position + 3) == "true" then position = position + 4 return true
        elseif text:sub(position, position + 4) == "false" then position = position + 5 return false
        elseif text:sub(position, position + 3) == "null" then position = position + 4 return nil
        else
            local literal = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", position)
            if not literal then error("helpers.json_to_table: unexpected character " .. character, 4) end
            position = position + #literal
            return tonumber(literal)
        end
    end

    local ok, value = pcall(parse_value)
    if not ok then return nil end
    return value
end
local SCRIPT_MEMBERS = {"active_mods", "mod_name", "on_init", "on_load", "on_configuration_changed", "on_event", "on_nth_tick"}

local GUI_MEMBERS = set_of({"type", "name", "caption", "tooltip", "children", "parent", "style", "tags", "player_index", "enabled", "visible",
    "text", "elem_value", "elem_type", "elem_filters", "elem_tooltip", "selected_index", "items", "tabs", "selected_tab_index", "numeric",
    "allow_decimal", "allow_negative", "lose_focus_on_confirm", "direction", "column_count", "draw_horizontal_lines", "draw_vertical_lines",
    "sprite", "valid", "auto_center", "state", "quality", "locked", "toggled",
    --round 8: the progress bar's value, and the export box's reading keys
    "value", "read_only", "selectable", "word_wrap", "vertical_scroll_policy", "horizontal_scroll_policy",
    --a window's own title bar: the drag handle and the close button's three sprites
    "drag_target", "hovered_sprite", "clicked_sprite", "mouse_button_filter"})

--2.0.77 LuaGuiElement::add takes only the documented per-type parameters. For a text-box those are "text" and
--"icon_selector"; read_only, selectable and word_wrap are attributes, written after the element exists. The
--engine drops them from an add{} table without a word, which is how 1.1.47 shipped an editable export box.
local ADD_IGNORES = set_of({"read_only", "selectable", "word_wrap"})

--What a fresh text-box carries before the mod writes anything
local TEXT_BOX_DEFAULTS = {read_only = false, selectable = true, word_wrap = false}

--Members only some element types carry; reading or writing one elsewhere is what the engine refuses
local GUI_TYPE_GATES = {
    value = {progressbar = true, slider = true},
    read_only = {["text-box"] = true, textfield = true},
    selectable = {["text-box"] = true, textfield = true},
    word_wrap = {["text-box"] = true},
    vertical_scroll_policy = {["scroll-pane"] = true},
    horizontal_scroll_policy = {["scroll-pane"] = true},
}

local function check_gui_type(element, key, level)
    local gate = GUI_TYPE_GATES[key]
    if not gate then return end
    local element_type = rawget(element, "type")
    if not gate[element_type] then
        error("LuaGuiElement::" .. key .. " can only be used if this is " .. table.concat((function()
            local names = {}
            for name in pairs(gate) do names[#names + 1] = name end
            table.sort(names)
            return names
        end)(), " or "), (level or 2) + 1)
    end
end

local gui_methods = {}

--Utility sprites the mod uses, each checked in 2.0.77 core/prototypes/utility-sprites.lua; any other utility path is refused
local UTILITY_SPRITES = set_of({"check_mark_green", "close", "close_black", "empty_module_slot", "trash"})

--Core style names, read once from docs/api/2.0.77.styles.json. nil when the pin is unreadable, so a caller
--outside the repository is never blocked; false only for a name the pin does not carry.
local pinned_styles = nil
function H.style_valid(name)
    if pinned_styles == nil then
        local file = io.open("docs/api/2.0.77.styles.json")
        if not file then pinned_styles = false
        else
            local text = file:read("*a")
            file:close()
            pinned_styles = {}
            local list = text:match('"styles"%s*:%s*%[(.-)%]')
            for entry in tostring(list):gmatch('"([^"]+)"') do pinned_styles[entry] = true end
        end
    end
    if pinned_styles == false then return nil end
    return pinned_styles[name] == true
end

--A typed sprite path ("item/…", "fluid/…", "entity/…", "quality/…", "utility/…") checked against what exists: true or false; nil for an untyped name
function H.typed_sprite_valid(path)
    local sprite_type, sprite_name = tostring(path):match("^(%a+)/(.+)$")
    if sprite_type == "item" then return prototypes.item[sprite_name] ~= nil end
    if sprite_type == "fluid" then return prototypes.fluid[sprite_name] ~= nil end
    if sprite_type == "entity" then return prototypes.entity[sprite_name] ~= nil end
    if sprite_type == "quality" then return prototypes.quality[sprite_name] ~= nil end
    if sprite_type == "utility" then return UTILITY_SPRITES[sprite_name] == true end
    return nil
end

--Values a player can change; kept out of the element table so every script write goes through __newindex
local VALUE_KEYS = {elem_value = true, text = true, state = true, value = true}

--2.0.77 LuaGuiElement::value: "the value of this progressbar, in [0, 1]". Anything else is refused, so a bar cannot
--be driven with a percentage or a negative remainder. Being inside the range is not "honest progress": that a job
--below completion never writes 1 is a behaviour case, not this check.
local function check_progress_value(value)
    if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        error("LuaGuiElement::value must be a number in [0, 1], got " .. tostring(value), 4)
    end
end

--Conservative assumption (not established for the engine): choose-elem-buttons refuse names of prototypes that do not exist
local function check_elem_value(element, value)
    if value == nil then return end
    local elem_type = rawget(element, "_values").elem_type
    if elem_type == "item" and not prototypes.item[value] then
        error("Unknown item " .. tostring(value), 3)
    elseif elem_type == "fluid" and not prototypes.fluid[value] then
        error("Unknown fluid " .. tostring(value), 3)
    elseif elem_type == "item-with-quality" and type(value) ~= "table" then
        error("item-with-quality value must be a table with name and quality, got " .. tostring(value), 3)
    elseif elem_type == "item-with-quality" and not prototypes.item[value.name] then
        error("Unknown item " .. tostring(value.name), 3)
    elseif elem_type == "item-with-quality" and value.quality and not prototypes.quality[value.quality] then
        error("Unknown quality " .. tostring(value.quality), 3)
    elseif elem_type == "recipe-with-quality" and type(value) ~= "table" then
        error("recipe-with-quality value must be a table with name and quality, got " .. tostring(value), 3)
    elseif elem_type == "recipe-with-quality" and not prototypes.recipe[value.name] then
        error("Unknown recipe " .. tostring(value.name), 3)
    elseif elem_type == "recipe-with-quality" and value.quality and not prototypes.quality[value.quality] then
        error("Unknown quality " .. tostring(value.quality), 3)
    elseif elem_type == "entity-with-quality" and not prototypes.entity[value.name] then
        error("Unknown entity " .. tostring(value.name), 3)
    elseif elem_type == "entity-with-quality" and value.quality and not prototypes.quality[value.quality] then
        error("Unknown quality " .. tostring(value.quality), 3)
    end
end

--Filter names each choose-elem-button type accepts, from the 2.0.77 RecipePrototypeFilter, EntityPrototypeFilter and ItemPrototypeFilter pages (subset the mod uses)
local FILTER_NAMES_BY_ELEM_TYPE = {
    ["recipe"] = set_of({"has-product-item", "has-product-fluid", "has-ingredient-item", "has-ingredient-fluid", "hidden", "category"}),
    --not documented for with-quality types (P12); modelled as the recipe filters
    ["recipe-with-quality"] = set_of({"has-product-item", "has-product-fluid", "has-ingredient-item", "has-ingredient-fluid", "hidden", "category"}),
    --2.0.77 EntityPrototypeFilter, every filter name the page lists; "type" is what a picker needs to offer one
    --category alone, and the harness refused it until a player saw every entity in the game in one picker.
    ["entity-with-quality"] = set_of({
        "flying-robot", "robot-with-logistics-interface", "rail", "ghost", "explosion", "vehicle",
        "crafting-machine", "rolling-stock", "turret", "transport-belt-connectable", "wall-connectable",
        "buildable", "placable-in-editor", "clonable", "selectable", "hidden", "entity-with-health", "building",
        "fast-replaceable", "uses-direction", "minable", "circuit-connectable", "autoplace", "blueprintable",
        "item-to-place", "name", "type", "collision-mask", "flag", "build-base-evolution-requirement",
        "selection-priority", "emissions-per-second", "crafting-category",
    }),
    ["item-with-quality"] = set_of({"name"}),
}
--Nested item and fluid filters of has-product/has-ingredient filters match by name here
local NESTED_FILTER_ELEM_TYPE = {["has-product-item"] = "item", ["has-product-fluid"] = "fluid", ["has-ingredient-item"] = "item", ["has-ingredient-fluid"] = "fluid"}

local function check_elem_filters(params)
    if params.type ~= "choose-elem-button" or params.elem_filters == nil then return end
    local allowed = FILTER_NAMES_BY_ELEM_TYPE[params.elem_type]
    if not allowed then error("harness does not know filters for elem_type " .. tostring(params.elem_type), 3) end
    for _, filter in ipairs(params.elem_filters) do
        if not allowed[filter.filter] then
            error("Unknown " .. params.elem_type .. " filter " .. tostring(filter.filter), 3)
        end
        --mode and invert are common to every prototype filter (2.0.77 RecipePrototypeFilter page)
        if filter.mode ~= nil and filter.mode ~= "or" and filter.mode ~= "and" then
            error("Unknown filter mode " .. tostring(filter.mode), 3)
        end
        if filter.invert ~= nil and type(filter.invert) ~= "boolean" then
            error("filter invert must be a boolean", 3)
        end
        if filter.filter == "category" and not prototypes.recipe_category[filter.category] then
            error("category filter names unknown recipe category " .. tostring(filter.category), 3)
        end
        local nested = NESTED_FILTER_ELEM_TYPE[filter.filter]
        if nested then
            if type(filter.elem_filters) ~= "table" or #filter.elem_filters == 0 then
                error(filter.filter .. " filter needs nested elem_filters", 3)
            end
            for _, inner in ipairs(filter.elem_filters) do
                if inner.filter ~= "name" or not prototypes[nested][inner.name] then
                    error(filter.filter .. " filter names unknown " .. nested .. " " .. tostring(inner.name), 3)
                end
            end
        end
    end
end

--Conservative assumptions: only a sprite-button shows a quality, and it must name an existing one
local function check_quality(element, quality_name)
    if quality_name == nil then return end
    if rawget(element, "type") ~= "sprite-button" then
        error("quality is only used on a sprite-button, not " .. tostring(rawget(element, "type")), 4)
    end
    if not prototypes.quality[quality_name] then error("Unknown quality " .. tostring(quality_name), 4) end
end

local function normalize_value(key, value)
    if key == "text" and type(value) == "number" then return tostring(value) end
    return value
end

H.refire_on_script_set = false
local refire_depth = 0

--Re-fire mode: a script write raises the element's handler, as the engine might; a restore that is not idempotent then loops
local function refire(element, key)
    if not H.refire_on_script_set then return end
    local handlers = (key == "elem_value" and event_handlers.on_gui_elem_changed)
        or (key == "state" and event_handlers.on_gui_checked_state_changed)
        or event_handlers.on_gui_confirmed
    local handler = handlers[rawget(element, "name")]
    if not handler then return end
    refire_depth = refire_depth + 1
    if refire_depth > 5 then
        refire_depth = 0
        error("event re-fire loop", 3)
    end
    local ok, err = pcall(handler, {element = element, player_index = rawget(element, "player_index")})
    refire_depth = refire_depth - 1
    if not ok then error(err, 0) end
end

--LuaStyle of an element: a plain writable table, except column_alignments (2.0.77: tables only; read-only property, its entries writable by index)
local function new_style(element_type, fields)
    local data = fields or {}
    local alignments = {}
    return setmetatable({}, {
        __index = function(_, key)
            if key == "column_alignments" then
                if element_type ~= "table" then error("LuaStyle::column_alignments can only be used if this is table", 2) end
                return alignments
            end
            return data[key]
        end,
        __newindex = function(_, key, value)
            if key == "column_alignments" then error("LuaStyle::column_alignments is read-only", 2) end
            data[key] = value
        end,
    })
end

local function new_gui_element(params, parent, player_index)
    local element = {children = {}, tabs = {}, valid = true, enabled = true, visible = true, tags = {}, _values = {style = new_style(params.type)}}
    for key, value in pairs(params) do
        if key ~= "index" and key ~= "quality" and key ~= "elem_type" and key ~= "style" and GUI_MEMBERS[key]
            and not VALUE_KEYS[key] and not ADD_IGNORES[key] then element[key] = value end
    end
    --a style given by name (add{style = "slot_button"}) reads back as a style table carrying that name, so style.width = ... still works
    if type(params.style) == "string" then element._values.style = new_style(params.type, {name = params.style}) end
    if params.enabled == false then element.enabled = false end
    if params.visible == false then element.visible = false end
    --elem_type is read-only, so it is kept where only reads reach it
    element._values.elem_type = params.elem_type
    if params.elem_type then
        check_elem_value(element, params[params.elem_type])
        element._values.elem_value = params[params.elem_type]
    end
    element._values.text = normalize_value("text", params.text)
    for key in pairs(GUI_TYPE_GATES) do
        if params[key] ~= nil then
            check_gui_type(element, key, 3)
            if key == "value" then check_progress_value(params[key]) end
            element._values[key] = params[key]
        end
    end
    if params.type == "text-box" then
        for key, value in pairs(TEXT_BOX_DEFAULTS) do element[key] = value end
    end
    if params.type == "progressbar" and element._values.value == nil then element._values.value = 0 end
    element._values.state = params.state
    check_quality(element, params.quality)
    element._values.quality = params.quality
    element.parent = parent
    element.player_index = parent and parent.player_index or player_index
    lua_objects[element] = true
    return setmetatable(element, {
        __index = function(self, key)
            --2.0.77: elem_value "can only be used if this is choose-elem-button"
            if key == "elem_value" and rawget(self, "type") ~= "choose-elem-button" then
                error("LuaGuiElement::elem_value can only be used if this is choose-elem-button", 2)
            end
            if VALUE_KEYS[key] or key == "elem_type" or key == "style" then
                check_gui_type(self, key)
                return rawget(self, "_values")[key]
            end
            if GUI_TYPE_GATES[key] then
                check_gui_type(self, key)
                return rawget(self, "_values")[key]
            end
            --a sprite-button's quality is written as a name and read as the quality prototype
            if key == "quality" then
                local quality_name = rawget(self, "_values").quality
                return quality_name and prototypes.quality[quality_name]
            end
            --the engine binds methods, so mod code calls element.add{...} without self; accept both call styles
            local method = gui_methods[key]
            if method then
                return function(first, ...)
                    if first == self then return method(self, ...) end
                    return method(self, first, ...)
                end
            end
            for _, child in ipairs(rawget(self, "children")) do
                if child.name == key then return child end
            end
            if GUI_MEMBERS[key] then return nil end
            error("LuaGuiElement doesn't contain key " .. tostring(key), 2)
        end,
        __newindex = function(self, key, value)
            if VALUE_KEYS[key] then
                if key == "elem_value" and rawget(self, "type") ~= "choose-elem-button" then
                    error("LuaGuiElement::elem_value can only be used if this is choose-elem-button", 2)
                end
                if key == "elem_value" then check_elem_value(self, value) end
                check_gui_type(self, key)
                if key == "value" then check_progress_value(value) end
                rawget(self, "_values")[key] = normalize_value(key, value)
                refire(self, key)
                return
            end
            if key == "quality" then
                check_quality(self, value)
                rawget(self, "_values").quality = value
                return
            end
            if key == "elem_type" then error("LuaGuiElement::elem_type is read-only", 2) end
            if not GUI_MEMBERS[key] then error("LuaGuiElement doesn't contain key " .. tostring(key), 2) end
            if GUI_TYPE_GATES[key] then
                check_gui_type(self, key)
                rawget(self, "_values")[key] = value
                return
            end
            if key == "style" then
                rawget(self, "_values").style = type(value) == "string" and new_style(rawget(self, "type"), {name = value}) or value
                return
            end
            rawset(self, key, value)
        end,
    })
end

function gui_methods.add(self, params)
    --the engine refuses a second child with the same name under one parent (Factorio 2.0.77: "Gui element with name X already present in the parent element.")
    if params.name and params.name ~= "" then
        for _, sibling in ipairs(self.children) do
            if sibling.name == params.name then
                error("Gui element with name " .. params.name .. " already present in the parent element.", 3)
            end
        end
    end
    --typed sprites need their prototype, utility sprites must be one core defines (see H.typed_sprite_valid)
    for _, key in ipairs({"sprite", "hovered_sprite", "clicked_sprite"}) do
        if params[key] and H.typed_sprite_valid(params[key]) == false then
            error("Unknown sprite " .. params[key], 3)
        end
    end
    --2.0.77 refuses a style the core prototypes never defined: 1.1.47 crashed on open with
    --"Unknown style draggable_space_with_no_left_margin". The pinned list is what refuses one here.
    if type(params.style) == "string" and H.style_valid(params.style) == false then
        error("Unknown style " .. params.style, 3)
    end
    check_elem_filters(params)
    local child = new_gui_element(params, self)
    if params.index then
        table.insert(self.children, params.index, child)
    else
        table.insert(self.children, child)
    end
    return child
end

function gui_methods.get_index_in_parent(self)
    for index, child in ipairs(self.parent.children) do
        if child == self then return index end
    end
end

--The engine invalidates a removed element together with everything under it
local function invalidate_subtree(element)
    rawset(element, "valid", false)
    for _, child in ipairs(rawget(element, "children")) do invalidate_subtree(child) end
end

function gui_methods.destroy(self)
    if self.parent then table.remove(self.parent.children, self:get_index_in_parent()) end
    invalidate_subtree(self)
end

function gui_methods.clear(self)
    for _, child in ipairs(self.children) do invalidate_subtree(child) end
    self.children = {}
end

function gui_methods.add_tab(self, tab, content)
    table.insert(self.tabs, {tab = tab, content = content})
end

function gui_methods.remove_tab(self, tab)
    for index, tab_and_content in ipairs(self.tabs) do
        if tab_and_content.tab == tab then table.remove(self.tabs, index) return end
    end
end

function gui_methods.swap_children(self, a, b)
    self.children[a], self.children[b] = self.children[b], self.children[a]
end

function gui_methods.force_auto_center() end

--2.0.77: select_all and focus exist on textfield and text-box; the export dialog uses them for its Select all action
local TEXT_INPUT_TYPES = {textfield = true, ["text-box"] = true}
local function check_text_input(self, method)
    if not TEXT_INPUT_TYPES[rawget(self, "type")] then
        error("LuaGuiElement::" .. method .. " can only be used if this is textfield or text-box", 3)
    end
end
function gui_methods.select_all(self)
    check_text_input(self, "select_all")
    rawget(self, "_values").selected_all = true
end
function gui_methods.focus(self)
    check_text_input(self, "focus")
    rawget(self, "_values").focused = true
end
--What a test reads back after the dialog's Select all ran; not an engine member
function H.text_selected(element) return rawget(element, "_values").selected_all == true end
function H.text_focused(element) return rawget(element, "_values").focused == true end

function H.gui_root(params, player_index)
    return new_gui_element(params, nil, player_index or 1)
end

local function compare_versions(a, b)
    local function parts(version)
        local numbers = {}
        for number in version:gmatch("%d+") do numbers[#numbers + 1] = tonumber(number) end
        return numbers
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

--Product concept table in the shape of the given API version; spec: {type, name, amount | min+max, p, e, ignored, ignored_by_stats, shared, no_shared, percent_spoiled}
function H.product(shape, spec)
    local product = {type = spec.type or "item", name = spec.name, amount = spec.amount, amount_min = spec.min, amount_max = spec.max,
        extra_count_fraction = spec.e, ignored_by_productivity = spec.ignored, ignored_by_stats = spec.ignored_by_stats, percent_spoiled = spec.percent_spoiled}
    if shape == "2.1" then
        product.independent_probability = spec.p or 1
        if not spec.no_shared then product.shared_probability = spec.shared or {min = 0, max = 1} end
    else
        product.probability = spec.p or 1
    end
    return product
end

local MOD_MODULE_PREFIXES = {"gui.", "logic.", "control", "updates"}

--Fresh runtime globals and module cache. shape: "2.0", "2.1" or "hybrid"
function H.new_world(shape)
    for module_name, _ in pairs(package.loaded) do
        for _, prefix in ipairs(MOD_MODULE_PREFIXES) do
            if module_name:sub(1, #prefix) == prefix then package.loaded[module_name] = nil end
        end
    end

    local world = {shape = shape, flying_texts = {}, handlers = {events = {}}}
    local base_version = shape == "2.1" and "2.1.17" or "2.0.77"

    _G.storage = {}
    _G.event_handlers = {on_gui_click = {}, on_gui_confirmed = {}, on_gui_elem_changed = {}, on_gui_checked_state_changed = {}, on_gui_selection_state_changed = {}}
    _G.async_calls = nil
    _G.defines = {events = {on_player_created = "on_player_created", on_player_removed = "on_player_removed", on_gui_closed = "on_gui_closed",
        on_research_finished = "on_research_finished", on_gui_click = "on_gui_click", on_gui_elem_changed = "on_gui_elem_changed",
        on_gui_confirmed = "on_gui_confirmed", on_gui_checked_state_changed = "on_gui_checked_state_changed",
        on_gui_selection_state_changed = "on_gui_selection_state_changed", on_tick = "on_tick",
        on_runtime_mod_setting_changed = "on_runtime_mod_setting_changed", on_player_cursor_stack_changed = "on_player_cursor_stack_changed"},
        inventory = {beacon_modules = 1, crafter_modules = 4},
        --distinct values only: the mod compares against this table and never relies on the engine's numbers
        mouse_button_type = {none = 1, left = 2, right = 4, middle = 3},
        --2.0 serializes directions on the 16-step scale; a blueprint only ever uses the four cardinals
        direction = {north = 0, northeast = 2, east = 4, southeast = 6, south = 8, southwest = 10, west = 12, northwest = 14},
        --copper carries power, the circuit connectors never do; a wire edge is legal only between copper connectors
        wire_connector_id = {pole_copper = 0, power_switch_left_copper = 1, power_switch_right_copper = 2,
            circuit_red = 3, circuit_green = 4},
        wire_type = {copper = 0, red = 1, green = 2}}
    --named sprite prototypes the data stage defined; item, fluid and entity paths are checked against their prototypes
    world.sprite_prototypes = {hxrrc_recycling = true}
    function world.remove_sprite(name) world.sprite_prototypes[name] = nil end
    local function is_valid_sprite_path(path)
        local typed = H.typed_sprite_valid(path)
        if typed ~= nil then return typed end
        return world.sprite_prototypes[path] == true
    end
    --One failed encode on demand: the export has to say so rather than hand out a truncated string it calls valid
    local encode_fails_next = false
    function world.fail_next_encode() encode_fails_next = true end

    _G.helpers = H.lua_object("LuaHelpers", {
        compare_versions = compare_versions,
        is_valid_sprite_path = is_valid_sprite_path,
        table_to_json = function(value) return table_to_json(value) end,
        json_to_table = function(text) return json_to_table(text) end,
        --2.0.77 LuaHelpers::encode_string returns "the string encoded, or nil if the encoding failed"
        encode_string = function(text)
            if encode_fails_next then encode_fails_next = false return nil end
            return base64_encode(zlib_deflate_stored(text))
        end,
        decode_string = function(text)
            local raw = base64_decode(text)
            if raw == nil then return nil end
            return zlib_inflate_stored(raw)
        end,
    }, HELPERS_MEMBERS)
    _G.script = H.lua_object("LuaBootstrap", {
        active_mods = {base = base_version, ["RRC-Fork"] = "1.1.10"},
        mod_name = "RRC-Fork",
        on_init = function(handler) world.handlers.on_init = handler end,
        on_configuration_changed = function(handler) world.handlers.on_configuration_changed = handler end,
        on_event = function(event, handler) world.handlers.events[event] = handler end,
    }, SCRIPT_MEMBERS)
    _G.settings = {get_player_settings = function() return {["hxrrc-displayed-floating-point-precision"] = {value = 12}} end}

    local machines = {}
    local beacons = {}
    local modules = {}
    H.refire_on_script_set = false
    refire_depth = 0

    local qualities = {}
    world.locked_qualities = {}
    --specs in chain order: {name, level, next_probability (default 0.1, 0 on the last)}; each quality's next is the one after it
    local function build_quality_chain(specs)
        for name, _ in pairs(qualities) do qualities[name] = nil end
        local previous
        for index, spec in ipairs(specs) do
            local next_probability = spec.next_probability or (index < #specs and 0.1 or 0)
            local quality = H.lua_object("LuaQualityPrototype", {name = spec.name, valid = true, localised_name = {"quality-name." .. spec.name},
                level = spec.level, next_probability = next_probability, crafting_machine_module_slots_bonus = spec.level,
                beacon_module_slots_bonus = spec.level, beacon_power_usage_multiplier = 1, hidden = spec.hidden == true}, QUALITY_MEMBERS)
            qualities[spec.name] = quality
            if previous then previous.next = quality end
            previous = quality
        end
    end
    build_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}, {name = "epic", level = 3},
        {name = "legendary", level = 5}})

    --2.0 runtime-api.json lists prototypes as the global object of class LuaPrototypes, so in the game
    --type(prototypes) is "userdata", never "table". Code guarding itself with type(prototypes) == "table"
    --therefore refuses every prototype in the game while passing offline: exactly how 1.1.27 shipped a broken
    --paste. The table below is registered as a LuaObject so its type reads the way the engine reads.
    _G.prototypes = {
        recipe = {}, item = {}, fluid = {}, entity = {}, recipe_category = {},
        quality = qualities,
        get_entity_filtered = function(filters)
            local filter = filters[1]
            if filter.filter == "crafting-machine" then return machines end
            if filter.filter == "type" and filter.type ~= "beacon" then
                --a type filter takes one type or a list of them and matches every entity of those types
                local types = set_of(type(filter.type) == "table" and filter.type or {filter.type})
                local found = {}
                for name, entity in pairs(prototypes.entity) do
                    if types[rawget(entity, "type")] then found[name] = entity end
                end
                return found
            end
            if filter.filter == "type" and filter.type == "beacon" then return beacons end
            error("harness does not support entity filter " .. tostring(filter.filter))
        end,
        get_item_filtered = function(filters)
            local filter = filters[1]
            if filter.filter == "type" and filter.type == "module" then return modules end
            error("harness does not support item filter " .. tostring(filter.filter))
        end,
    }
    lua_objects[_G.prototypes] = true --the engine's prototypes is a LuaPrototypes object, so type() must say userdata
    lua_objects[_G.settings] = true --LuaSettings, likewise

    _G.game = {players = {}, get_player = function(index) return game.players[index] end}

    --A staging inventory, so a finished blueprint can be built without touching whatever the player already holds:
    --BP-18 requires failure and cancellation to leave the cursor item untouched, which is only testable off-cursor.
    function _G.game.create_inventory(size)
        local slots = {}
        for slot = 1, size do
            local held
            slots[slot] = H.lua_object("LuaItemStack", {valid = true}, ITEM_STACK_MEMBERS, nil, {
                valid_for_read = {read = function() return held ~= nil end},
                name = {read = function()
                    if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    return held.name
                end},
                count = {read = function() return held and held.count or 0 end},
                quality = {read = function()
                    if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    return prototypes.quality[held.quality or "normal"]
                end},
                prototype = {read = function()
                    if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    return prototypes.item[held.name]
                end},
                is_blueprint = {read = function() return held ~= nil and held.name == "blueprint" end},
                is_blueprint_setup = {read = function() return function() return held ~= nil and held.name == "blueprint" and held.entities ~= nil end end},
                blueprint_description = {read = function() return held and held.description end,
                    write = function(_, value) if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end held.description = value end},
                label = {read = function() return held and held.label end,
                    write = function(_, value) if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end held.label = value end},
                preview_icons = {read = function() return held and held.icons end,
                    write = function(_, value) if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end held.icons = value end},
                set_stack = {read = function() return function(spec)
                    if spec == nil then held = nil return true end
                    local name = raw_type(spec) == "table" and spec.name or spec
                    if not prototypes.item[name] then error("Unknown item name " .. tostring(name), 3) end
                    held = {name = name, count = raw_type(spec) == "table" and spec.count or 1, quality = raw_type(spec) == "table" and spec.quality or nil}
                    return true
                end end},
                clear = {read = function() return function() held = nil return true end end},
                set_blueprint_entities = {read = function() return function(entities)
                    if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    if held.name ~= "blueprint" then error("LuaItemStack::set_blueprint_entities can only be used if this is a blueprint", 3) end
                    held.entities = entities
                end end},
                get_blueprint_entities = {read = function() return function()
                    if not held then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    if held.name ~= "blueprint" then error("LuaItemStack::get_blueprint_entities can only be used if this is a blueprint", 3) end
                    return held.entities
                end end},
            })
        end
        return slots
    end

    --The blueprint item itself, which set_stack{name = "blueprint"} needs to exist
    function world.add_blueprint_item()
        world.add_item("blueprint")
        return prototypes.item.blueprint
    end

    --fuel (optional): {value (J), category, emissions_multiplier (default 1)}; items without it have fuel value 0 and no fuel category
    --spoil: {result = "<item name>", ticks = <number>}; absent means the item never spoils, as in vanilla
    function world.add_item(name, fuel, spoil)
        prototypes.item[name] = H.lua_object("LuaItemPrototype", {name = name, type = "item", valid = true, localised_name = {"item-name." .. name},
            fuel_value = fuel and fuel.value or 0, fuel_category = fuel and fuel.category, fuel_emissions_multiplier = fuel and fuel.emissions_multiplier or 1,
            spoil_result = spoil and spoil.result,
            get_spoil_ticks = function(quality)
                local per_quality = spoil and spoil.ticks_by_quality and spoil.ticks_by_quality[quality or "normal"]
                return per_quality or (spoil and spoil.ticks) or 0
            end,
            hidden = false, parameter = false},
            ITEM_MEMBERS, ITEM_GATES)
    end

    --flags: {hidden = boolean, parameter = boolean}, as LuaPrototypeBase reads them
    function world.set_item_flags(name, flags)
        for key, value in pairs(flags) do prototypes.item[name][key] = value end
    end

    --The item left after burning an item, e.g. a spent fuel cell; set separately so two items may name each other
    function world.set_burnt_result(name, result_name)
        prototypes.item[name].burnt_result = result_name and prototypes.item[result_name]
    end

    --effects_by_quality: {[quality name] = effects} for qualities whose effects differ; the engine's scaling is not modelled, fixtures give values
    function world.add_module(name, category, module_effects, effects_by_quality)
        local module = H.lua_object("LuaItemPrototype", {name = name, type = "module", valid = true, localised_name = {"item-name." .. name},
            category = category, module_effects = module_effects, hidden = false, parameter = false,
            get_module_effects = function(quality)
                if quality ~= nil and not prototypes.quality[quality] then error("Unknown quality " .. tostring(quality), 2) end
                return (effects_by_quality and effects_by_quality[quality or "normal"]) or module_effects
            end}, ITEM_MEMBERS, ITEM_GATES)
        prototypes.item[name] = module
        modules[name] = module
    end

    --A mod swap turning a module into a plain item under the same name
    function world.replace_module_with_item(name)
        modules[name] = nil
        world.add_item(name)
    end

    function world.remove_module(name)
        prototypes.item[name] = nil
        modules[name] = nil
    end

    --A mod removing a recipe: the prototype object turns invalid and disappears from prototypes; its product item stays
    function world.remove_recipe(name)
        prototypes.recipe[name].valid = false
        prototypes.recipe[name] = nil
    end

    --Prototypes reload after a mod change, so no remaining quality keeps the removed one as its next
    function world.remove_quality(name)
        local removed = prototypes.quality[name]
        prototypes.quality[name] = nil
        for _, quality in pairs(prototypes.quality) do
            if rawget(quality, "next") == removed then quality.next = nil end
        end
    end

    --Replaces every quality with a modded chain; specs in chain order: {name, level, next_probability}
    function world.set_quality_chain(specs)
        build_quality_chain(specs)
    end

    --A quality that exists but that no quality's next leads to, as a mod could add
    function world.add_unlinked_quality(name, level)
        prototypes.quality[name] = H.lua_object("LuaQualityPrototype", {name = name, valid = true, localised_name = {"quality-name." .. name},
            level = level, next_probability = 0.1, crafting_machine_module_slots_bonus = level, beacon_module_slots_bonus = level,
            beacon_power_usage_multiplier = 1, hidden = false}, QUALITY_MEMBERS)
    end

    function world.lock_quality(name) world.locked_qualities[name] = true end
    function world.unlock_quality(name) world.locked_qualities[name] = nil end

    --fields: LuaQualityPrototype members to change, e.g. {beacon_power_usage_multiplier = 2}
    function world.set_quality(name, fields)
        for key, value in pairs(fields) do prototypes.quality[name][key] = value end
    end

    --fuel (optional): {value (J per unit), emissions_multiplier (default 1), spent_fluid (2.1 shape only)}
    function world.add_fluid(name, fuel)
        local fields = {name = name, valid = true, localised_name = {"fluid-name." .. name},
            fuel_value = fuel and fuel.value or 0, emissions_multiplier = fuel and fuel.emissions_multiplier or 1}
        if fuel and fuel.spent_fluid then fields.spent_fluid = fuel.spent_fluid end
        prototypes.fluid[name] = H.lua_object("LuaFluidPrototype", fields, FLUID_MEMBERS[shape])
    end

    --spec: {name, type ("reactor", "boiler", "burner-generator", or any other type for entities that must not be offered), energy_kw (full-load usage),
    --  energy_kw_by_quality, max_power_kw (burner generators), emissions_per_joule (table, default {pollution = 0}), and one energy source:
    --  burner = {fuel_categories (list), effectivity (default 1), burnt_inventory_size (default 0)} or
    --  fluid = {burns_fluid (default true), filter (fluid name), scale_fluid_usage (default false), fluid_usage_per_tick (default 0), effectivity (default 1),
    --    output_fluid_box (2.1: true), spent_fluid (2.1)}}
    function world.add_burner(spec)
        local emissions = spec.emissions_per_joule or {pollution = 0}
        local function usage(kw_by_quality, kw, quality)
            if quality ~= nil and not prototypes.quality[quality] then error("Unknown quality " .. tostring(quality), 3) end
            return ((kw_by_quality or {})[quality or "normal"] or kw) * 1000 / 60 --joules per tick
        end
        local fields = {name = spec.name, type = spec.type, valid = true, localised_name = {"entity-name." .. spec.name},
            energy_usage = (spec.energy_kw or 0) * 1000 / 60,
            get_max_energy_usage = function(quality) return usage(spec.energy_kw_by_quality, spec.energy_kw or 0, quality) end}
        if spec.max_power_kw then
            fields.get_max_power_output = function(quality) return usage(nil, spec.max_power_kw, quality) end
        end
        if spec.burner then
            fields.burner_prototype = H.lua_object("LuaBurnerPrototype", {valid = true, emissions_per_joule = emissions,
                effectivity = spec.burner.effectivity or 1, fuel_inventory_size = 1, burnt_inventory_size = spec.burner.burnt_inventory_size or 0,
                fuel_categories = set_of(spec.burner.fuel_categories)}, BURNER_MEMBERS)
        elseif spec.fluid then
            local fluid = spec.fluid
            local source = {valid = true, emissions_per_joule = emissions, effectivity = fluid.effectivity or 1,
                burns_fluid = fluid.burns_fluid ~= false, scale_fluid_usage = fluid.scale_fluid_usage == true,
                fluid_usage_per_tick = fluid.fluid_usage_per_tick or 0, maximum_temperature = 0,
                fluid_box = H.lua_object("LuaFluidBoxPrototype", {valid = true, filter = fluid.filter and prototypes.fluid[fluid.filter]}, FLUID_BOX_MEMBERS[shape])}
            if shape == "2.1" then
                source.output_fluid_box = fluid.output_fluid_box and H.lua_object("LuaFluidBoxPrototype", {valid = true}, FLUID_BOX_MEMBERS[shape]) or nil
                source.spent_fluid = fluid.spent_fluid
            elseif fluid.output_fluid_box or fluid.spent_fluid then
                error("fixture gives a 2.0 fluid energy source 2.1-only members", 2)
            end
            fields.fluid_energy_source_prototype = H.lua_object("LuaFluidEnergySourcePrototype", source, FLUID_ENERGY_SOURCE_MEMBERS[shape])
        end
        prototypes.entity[spec.name] = H.lua_object("LuaEntityPrototype", fields, ENTITY_MEMBERS, ENTITY_GATES)
    end

    --spec: {name, type (default assembling-machine), categories, speed, energy_kw, pollution_per_minute, base_productivity, base_quality, no_effect_receiver, speeds_by_quality,
    --  module_slots (default 4), quality_affects_module_slots, module_slots_quality_bonus, allowed_effects (list), allowed_module_categories (list),
    --  uses_module_effects, uses_beacon_effects}
    function world.add_machine(spec)
        local energy_usage = (spec.energy_kw or 210) * 1000 / 60 --joules per tick
        local pollution_per_second = (spec.pollution_per_minute or 4) / 60
        local categories = {}
        for _, category in ipairs(spec.categories) do
            categories[category] = true
            prototypes.recipe_category[category] = prototypes.recipe_category[category] or {name = category, valid = true}
        end
        local module_slots = spec.module_slots or 4
        local fields = {
            name = spec.name, type = spec.type or "assembling-machine", valid = true, localised_name = {"entity-name." .. spec.name},
            crafting_categories = categories,
            energy_usage = energy_usage,
            allowed_effects = effect_dictionary(spec.allowed_effects, true),
            allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories),
            module_inventory_size = module_slots,
            quality_affects_module_slots = spec.quality_affects_module_slots,
            module_slots_quality_bonus = spec.module_slots_quality_bonus,
            get_inventory_size = function(index, quality)
                if index ~= defines.inventory.crafter_modules then return nil end
                return module_slots_at(module_slots, spec.quality_affects_module_slots, spec.module_slots_quality_bonus, "crafting_machine_module_slots_bonus", quality)
            end,
            get_crafting_speed = function(quality) return (spec.speeds_by_quality or {})[quality or "normal"] or spec.speed or 1 end,
            get_max_energy_usage = function() return energy_usage end,
            electric_energy_source_prototype = H.lua_object("LuaElectricEnergySourcePrototype",
                {emissions_per_joule = spec.emissions_per_joule or {pollution = pollution_per_second / (energy_usage * 60)}}, ENERGY_SOURCE_MEMBERS),
        }
        if not spec.no_effect_receiver then
            fields.effect_receiver = {base_effect = {productivity = spec.base_productivity, quality = spec.base_quality}, uses_module_effects = spec.uses_module_effects ~= false,
                uses_beacon_effects = spec.uses_beacon_effects ~= false, uses_surface_effects = spec.uses_surface_effects ~= false}
            --2.1 exposes local effects and per-effect limits; 2.0 has neither, and a fixture may never invent
            --them for 2.0. The field names come from concepts.EffectReceiver in docs/api/2.1.19.members.json.
            if shape == "2.1" then
                fields.effect_receiver.uses_local_effects = spec.uses_local_effects ~= false
                fields.effect_receiver.quality_limits = spec.quality_limits
                fields.effect_receiver.speed_limits = spec.speed_limits
                fields.effect_receiver.productivity_limits = spec.productivity_limits
                fields.effect_receiver.consumption_limits = spec.consumption_limits
                fields.effect_receiver.pollution_limits = spec.pollution_limits
            end
        end
        --vanilla machines are placed by an item of their own name, which exists
        if not prototypes.item[spec.name] then world.add_item(spec.name) end
        fields.items_to_place_this = {{name = spec.name, count = 1}}
        fields.hidden = false
        local machine = H.lua_object("LuaEntityPrototype", fields, ENTITY_MEMBERS, ENTITY_GATES)
        prototypes.entity[spec.name] = machine
        machines[spec.name] = machine
    end

    --A mod swap turning a crafting machine into another entity type under the same name
    function world.replace_machine_with_entity(name, entity_type)
        machines[name] = nil
        prototypes.entity[name] = H.lua_object("LuaEntityPrototype",
            {name = name, type = entity_type, valid = true, localised_name = {"entity-name." .. name}}, ENTITY_MEMBERS, ENTITY_GATES)
    end

    --list: array of {name, count} (items_to_place_this is optional in 2.0.77), an empty list, or nil
    function world.set_placing_items(entity_name, list)
        prototypes.entity[entity_name].items_to_place_this = list
    end

    --flags: {hidden = boolean}, as LuaPrototypeBase reads it
    function world.set_entity_flags(name, flags)
        for key, value in pairs(flags) do prototypes.entity[name][key] = value end
    end

    function world.remove_machine(name)
        machines[name] = nil
        prototypes.entity[name] = nil
    end

    --spec: {name, module_slots (default 2), quality_affects_module_slots, energy_kw (default 480), distribution_effectivity (default 1.5),
    --  bonus_per_quality_level (default 0.2), profile (default none), beacon_counter (default "same_type"),
    --  allowed_effects (list, default consumption, speed, pollution), allowed_module_categories (list)}
    function world.add_beacon(spec)
        local module_slots = spec.module_slots or 2
        if not prototypes.item[spec.name] then world.add_item(spec.name) end
        local beacon = H.lua_object("LuaEntityPrototype", {
            name = spec.name, type = "beacon", valid = true, localised_name = {"entity-name." .. spec.name},
            module_inventory_size = module_slots,
            quality_affects_module_slots = spec.quality_affects_module_slots,
            get_inventory_size = function(index, quality)
                if index ~= defines.inventory.beacon_modules then return nil end
                return module_slots_at(module_slots, spec.quality_affects_module_slots, nil, "beacon_module_slots_bonus", quality)
            end,
            energy_usage = (spec.energy_kw or 480) * 1000 / 60,
            distribution_effectivity = spec.distribution_effectivity == nil and 1.5 or spec.distribution_effectivity,
            distribution_effectivity_bonus_per_quality_level = spec.bonus_per_quality_level == nil and 0.2 or spec.bonus_per_quality_level,
            profile = spec.profile,
            beacon_counter = spec.beacon_counter or "same_type",
            allowed_effects = effect_dictionary(spec.allowed_effects or {"consumption", "speed", "pollution"}),
            allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories),
            items_to_place_this = {{name = spec.name, count = 1}},
            hidden = false,
        }, ENTITY_MEMBERS, ENTITY_GATES)
        prototypes.entity[spec.name] = beacon
        beacons[spec.name] = beacon
    end

    function world.remove_beacon(name)
        beacons[name] = nil
        prototypes.entity[name] = nil
    end

    --A mod swap turning a beacon into another entity type under the same name
    function world.replace_beacon_with_entity(name, entity_type)
        beacons[name] = nil
        prototypes.entity[name] = H.lua_object("LuaEntityPrototype",
            {name = name, type = entity_type, valid = true, localised_name = {"entity-name." .. name}}, ENTITY_MEMBERS, ENTITY_GATES)
    end

    --spec: {name, category, additional_categories, energy, ingredients = {{type, name, amount}}, products = {product specs}, maximum_productivity,
    --  allowed_effects (list), allowed_module_categories (list), hidden}
    function world.add_recipe(spec)
        local products = {}
        for index, product_spec in ipairs(spec.products) do products[index] = H.product(shape, product_spec) end
        local ingredients = {}
        for index, ingredient in ipairs(spec.ingredients) do
            ingredients[index] = {type = ingredient.type or "item", name = ingredient.name, amount = ingredient.amount}
        end
        local fields = {name = spec.name, valid = true, object_name = "LuaRecipePrototype", localised_name = {"recipe-name." .. spec.name}, products = products, ingredients = ingredients,
            energy = spec.energy or 1, maximum_productivity = spec.maximum_productivity or 3, hidden = spec.hidden == true,
            allowed_effects = effect_dictionary(spec.allowed_effects), allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories)}
        for _, category in ipairs({spec.category, table.unpack(spec.additional_categories or {})}) do
            prototypes.recipe_category[category] = prototypes.recipe_category[category] or {name = category, valid = true}
        end
        if shape == "2.1" then
            fields.categories = {spec.category, table.unpack(spec.additional_categories or {})}
        else
            fields.category = spec.category
            fields.additional_categories = spec.additional_categories or {}
            if shape == "hybrid" then fields.categories = {spec.category} end
        end
        prototypes.recipe[spec.name] = H.lua_object("LuaRecipePrototype", fields, RECIPE_MEMBERS[shape])
    end

    --The tick stamped on cursor notifications and passed to H.press
    world.tick = 0
    function world.advance_tick(n) world.tick = world.tick + (n or 1) end

    --Cursor per player: ghost {name, quality} and stack {name, quality, count}, names only; quality nil is normal
    world.cursors = {}
    world.cursor_events = {}
    world.suppressed_cursor_events = {}
    world.merge_cursor_events = false
    --Vanilla Q emptying a hand that already holds what is under the cursor (see H.press); false is a defensive no-clear profile for tests
    world.vanilla_pipette_clears = true
    world.cursor_ghost_needs_empty_cursor = false
    local function cursor_of(index)
        world.cursors[index] = world.cursors[index] or {}
        return world.cursors[index]
    end
    --2.0.77: on_player_cursor_stack_changed is raised in the tick of the change, not instantly; tests deliver with world.flush_cursor_events
    local function queue_cursor_event(index)
        if (world.suppressed_cursor_events[index] or 0) > 0 then
            world.suppressed_cursor_events[index] = world.suppressed_cursor_events[index] - 1
            return
        end
        table.insert(world.cursor_events, {player_index = index, tick = world.tick})
    end
    --Negative capability: the next cursor write of this player raises no notification
    function world.suppress_next_cursor_event(index)
        world.suppressed_cursor_events[index] = (world.suppressed_cursor_events[index] or 0) + 1
    end
    --Delivers queued notifications in order, each with its own tick; merge mode delivers one per player per tick. Nothing records what the cursor held.
    function world.flush_cursor_events()
        local queued = world.cursor_events
        world.cursor_events = {}
        local handler = world.handlers.events[defines.events.on_player_cursor_stack_changed]
        local seen = {}
        for _, notification in ipairs(queued) do
            local key = notification.player_index .. "@" .. notification.tick
            if not (world.merge_cursor_events and seen[key]) then
                seen[key] = true
                if handler then
                    handler({name = defines.events.on_player_cursor_stack_changed, player_index = notification.player_index, tick = notification.tick})
                end
            end
        end
    end
    local function item_name_of(value)
        return raw_type(value) == "table" and value.name or value
    end
    local function check_cursor_item(name, quality)
        if type(name) ~= "string" or not prototypes.item[name] then error("Unknown item " .. tostring(name), 4) end
        if quality ~= nil and (type(quality) ~= "string" or not prototypes.quality[quality]) then error("Unknown quality " .. tostring(quality), 4) end
    end
    function world.hold_ghost(index, name, quality)
        check_cursor_item(name, quality)
        cursor_of(index).ghost = {name = name, quality = quality ~= "normal" and quality or nil}
        queue_cursor_event(index)
    end
    function world.hold_item(index, name, quality, count)
        check_cursor_item(name, quality)
        cursor_of(index).stack = {name = name, quality = quality ~= "normal" and quality or nil, count = count or 1}
        queue_cursor_event(index)
    end
    function world.empty_hand(index)
        world.cursors[index] = {}
        queue_cursor_event(index)
    end
    --A blueprint picked from the blueprint library: 2.0.77 LuaControl::cursor_record, held with no cursor stack item and no ghost
    function world.hold_record(index)
        cursor_of(index).record = H.lua_object("LuaRecord", {valid = true}, {"valid"})
        queue_cursor_event(index)
    end
    --Another GUI (inventory, map, another mod) takes player.opened
    function world.open_other_gui(index)
        game.players[index].opened = H.gui_root({type = "frame", name = "other_gui"}, index)
    end

    function world.add_player(index, research_bonus_by_recipe_name)
        world.research_bonus_by_recipe_name = research_bonus_by_recipe_name or {}
        local force = H.lua_object("LuaForce", {name = "player", valid = true, recipes = {}, players = {},
            --takes a quality name or prototype, as QualityID does
            is_quality_unlocked = function(quality)
                local quality_name = raw_type(quality) == "table" and quality.name or quality
                if not prototypes.quality[quality_name] then error("Unknown quality " .. tostring(quality_name), 2) end
                return not world.locked_qualities[quality_name]
            end}, FORCE_MEMBERS)
        local opened
        local closing = false --inside the on_gui_closed an opened assignment raised
        local cursor_stack = H.lua_object("LuaItemStack", {valid = true}, ITEM_STACK_MEMBERS, nil, {
            valid_for_read = {read = function() return cursor_of(index).stack ~= nil end},
            name = {read = function()
                local stack = cursor_of(index).stack
                if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                return stack.name
            end},
            quality = {read = function()
                local stack = cursor_of(index).stack
                if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                return prototypes.quality[stack.quality or "normal"]
            end},
            count = {read = function() local stack = cursor_of(index).stack return stack and stack.count or 0 end},
            prototype = {read = function()
                local stack = cursor_of(index).stack
                if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                return prototypes.item[stack.name]
            end},
            --A blueprint delivered to the cursor: is_blueprint reads the held item, the entity list lives on the stack
            is_blueprint = {read = function()
                local stack = cursor_of(index).stack
                return stack ~= nil and stack.name == "blueprint"
            end},
            --pinned API: is_blueprint_setup() is a method, is_blueprint an attribute
            is_blueprint_setup = {read = function()
                return function()
                    local stack = cursor_of(index).stack
                    return stack ~= nil and stack.name == "blueprint" and stack.entities ~= nil
                end
            end},
            blueprint_description = {read = function() local stack = cursor_of(index).stack return stack and stack.description end,
                write = function(_, value)
                    local stack = cursor_of(index).stack
                    if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    stack.description = value
                end},
            label = {read = function() local stack = cursor_of(index).stack return stack and stack.label end,
                write = function(_, value)
                    local stack = cursor_of(index).stack
                    if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    stack.label = value
                end},
            preview_icons = {read = function() local stack = cursor_of(index).stack return stack and stack.icons end,
                write = function(_, value)
                    local stack = cursor_of(index).stack
                    if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    stack.icons = value
                end},
            set_stack = {read = function()
                return function(spec)
                    --2.0.77: set_stack replaces what the stack holds; the mod must have released the old item first
                    if spec == nil then world.cursors[index] = {} queue_cursor_event(index) return true end
                    local name = raw_type(spec) == "table" and spec.name or spec
                    if not prototypes.item[name] then error("Unknown item name " .. tostring(name), 3) end
                    world.cursors[index] = {stack = {name = name, count = raw_type(spec) == "table" and spec.count or 1,
                        quality = raw_type(spec) == "table" and spec.quality or nil}}
                    queue_cursor_event(index)
                    return true
                end
            end},
            clear = {read = function()
                return function() world.cursors[index] = {} queue_cursor_event(index) return true end
            end},
            set_blueprint_entities = {read = function()
                return function(entities)
                    local stack = cursor_of(index).stack
                    if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    if stack.name ~= "blueprint" then error("LuaItemStack::set_blueprint_entities can only be used if this is a blueprint", 3) end
                    stack.entities = entities
                end
            end},
            get_blueprint_entities = {read = function()
                return function()
                    local stack = cursor_of(index).stack
                    if not stack then error("LuaItemStack API call when LuaItemStack was invalid for read", 3) end
                    if stack.name ~= "blueprint" then error("LuaItemStack::get_blueprint_entities can only be used if this is a blueprint", 3) end
                    return stack.entities
                end
            end},
        })
        local player = H.lua_object("LuaPlayer", {
            index = index, name = "player" .. index, valid = true, force = force,
            gui = {screen = H.gui_root({type = "empty-widget", name = "screen"}, index)},
            create_local_flying_text = function(params) table.insert(world.flying_texts, params.text) end,
            clear_cursor = function()
                world.cursors[index] = {}
                queue_cursor_event(index)
                return true
            end,
            --its 2.0.77 description contradicts its name, so the harness refuses to pick a meaning
            is_cursor_empty = function() error("is_cursor_empty is not modelled: its documented description contradicts its name", 2) end,
        }, PLAYER_MEMBERS, nil, {
            --2.0.77: reads give ItemIDAndQualityIDPair with prototypes; writes take ItemWithQualityID with names or prototypes
            cursor_ghost = {
                read = function()
                    local ghost = cursor_of(index).ghost
                    return ghost and {name = prototypes.item[ghost.name], quality = prototypes.quality[ghost.quality or "normal"]}
                end,
                write = function(_, value)
                    local cursor = cursor_of(index)
                    if value == nil then
                        cursor.ghost = nil
                    else
                        local name, quality
                        if type(value) == "string" then
                            name = value
                        elseif raw_type(value) == "table" and getmetatable(value) ~= nil then --an item prototype given as ItemID
                            name = value.name
                        elseif raw_type(value) == "table" then --{name, quality} with names or prototypes
                            name, quality = item_name_of(value.name), item_name_of(value.quality)
                        else
                            error("cursor_ghost must be an ItemWithQualityID", 2)
                        end
                        check_cursor_item(name, quality)
                        if world.cursor_ghost_needs_empty_cursor and cursor.stack then error("cursor is not empty", 2) end
                        cursor.ghost = {name = name, quality = quality ~= "normal" and quality or nil}
                    end
                    queue_cursor_event(index)
                end,
            },
            cursor_stack = {read = function() return cursor_stack end},
            cursor_record = {read = function() return cursor_of(index).record end},
            --reads nil once the opened element is gone; assigning another value first raises on_gui_closed for the open GUI (order is an in-game check)
            opened = {
                read = function()
                    if raw_type(opened) == "table" and opened.valid == false then return nil end
                    return opened
                end,
                write = function(_, value)
                    --2.0.77 on_gui_closed: a GUI opened during the event is force closed without notice, so the harness refuses it outright
                    if closing and value ~= nil then
                        error("a GUI was opened during on_gui_closed; Factorio force closes it", 2)
                    end
                    local previous = opened
                    if previous ~= nil and previous ~= value and not (raw_type(previous) == "table" and previous.valid == false) then
                        local handler = world.handlers.events[defines.events.on_gui_closed]
                        if handler then
                            closing = true
                            local ok, err = pcall(handler, {name = defines.events.on_gui_closed, player_index = index, tick = world.tick, element = previous})
                            closing = false
                            if not ok then error(err, 0) end
                        end
                    end
                    opened = value
                end,
            },
        })
        table.insert(force.players, player)
        game.players[index] = player
        return player
    end

    --Runs the mod's own indexing and per-player initialization over the fixture prototypes
    --------------------------------------------------------------------------------
    --Infrastructure fixtures: the entities a blueprint is built out of. One builder each, so the geometry lanes
    --read prototype members instead of inventing constants, and every lane shares one set of fixtures.
    --Geometry conventions: tile_width/tile_height are the north footprint; collision_box is the exact box in
    --tiles relative to the entity centre; positions in a fluid box connection are MapPositions relative to that
    --same centre, one per cardinal orientation, in the engine's north/east/south/west order.
    --------------------------------------------------------------------------------

    local function box(width, height)
        return {left_top = {x = -width / 2 + 0.05, y = -height / 2 + 0.05}, right_bottom = {x = width / 2 - 0.05, y = height / 2 - 0.05}}
    end

    --spec: {name, tile_width, tile_height, type, collision_box (exact box, default derived), flags, energy_kw, ...}
    local function infrastructure(spec, extra)
        local fields = {
            name = spec.name, type = spec.type, valid = true, localised_name = {"entity-name." .. spec.name},
            tile_width = spec.tile_width or 1, tile_height = spec.tile_height or 1,
            collision_box = spec.collision_box or box(spec.tile_width or 1, spec.tile_height or 1),
            collision_mask = spec.collision_mask or {layers = {object = true, player = true, water_tile = true}},
            flags = spec.flags or {["player-creation"] = true},
            energy_usage = (spec.energy_kw or 0) * 1000 / 60,
            items_to_place_this = {{name = spec.name, count = 1}},
            hidden = false,
        }
        for key, value in pairs(extra or {}) do fields[key] = value end
        local entity = H.lua_object("LuaEntityPrototype", fields, ENTITY_MEMBERS, ENTITY_GATES)
        prototypes.entity[spec.name] = entity
        if prototypes.item[spec.name] == nil then world.add_item(spec.name) end
        return entity
    end

    --spec: {name, items_per_second (both lanes, default 15)}
    function world.add_transport_belt(spec)
        return infrastructure({name = spec.name, type = "transport-belt"},
            {belt_speed = (spec.items_per_second or 15) / 480}) --2.0.77: belt_speed is tiles per tick
    end

    --spec: {name, items_per_second, max_distance (default 5), related (the matching surface belt's name)}
    function world.add_underground_belt(spec)
        return infrastructure({name = spec.name, type = "underground-belt"},
            {belt_speed = (spec.items_per_second or 15) / 480,
             max_underground_distance = spec.max_distance or 5,
             related_underground_belt = spec.related and prototypes.entity[spec.related] or nil})
    end

    --spec: {name, items_per_second}
    function world.add_splitter(spec)
        return infrastructure({name = spec.name, type = "splitter", tile_width = 2, tile_height = 1},
            {belt_speed = (spec.items_per_second or 15) / 480})
    end

    --spec: {name, items_per_second (default 4.62), pickup (vector, default one tile behind), drop (vector, default one tile ahead),
    --  stack_bonus (default 0), max_belt_stack (default 1), energy_kw}
    function world.add_inserter(spec)
        --rotation and extension speed are methods in the pinned extract and take a quality name.
        --speeds_by_quality: {[quality] = {rotation = <number>, extension = <number>}}
        local function speed_for(field, fallback)
            return function(quality)
                local per_quality = (spec.speeds_by_quality or {})[quality or "normal"]
                if per_quality and per_quality[field] ~= nil then return per_quality[field] end
                return spec[field] or fallback
            end
        end
        return infrastructure({name = spec.name, type = "inserter", energy_kw = spec.energy_kw or 13},
            {inserter_pickup_position = spec.pickup or {x = 0, y = 1},
             inserter_drop_position = spec.drop or {x = 0, y = -1.203125},
             inserter_stack_size_bonus = spec.stack_bonus or 0,
             inserter_max_belt_stack_size = spec.max_belt_stack or 1,
             get_inserter_rotation_speed = speed_for("rotation_speed", 0.014),
             get_inserter_extension_speed = speed_for("extension_speed", 0.0343),
             --the mod reads a rate from its own model; the prototype only carries geometry and bonuses
             energy_usage = (spec.energy_kw or 13) * 1000 / 60})
    end

    --Builds the four rotated MapPositions of one connection tile offset, in north/east/south/west order
    local function rotated_positions(offset)
        return {{x = offset.x, y = offset.y}, {x = -offset.y, y = offset.x}, {x = -offset.x, y = -offset.y}, {x = offset.y, y = -offset.x}}
    end

    --connections: list of {offset = {x=, y=}, direction (defines.direction value), connection_type ("normal"|"underground"),
    --  flow_direction ("input"|"output"|"input-output"), max_underground_distance}
    function world.fluid_box(spec)
        local connections = {}
        for index, connection in ipairs(spec.connections or {}) do
            local entry = {
                positions = rotated_positions(connection.offset),
                direction = connection.direction,
                connection_type = connection.connection_type or "normal",
                flow_direction = connection.flow_direction or "input-output",
                connection_category = connection.connection_category or {"default"},
            }
            if connection.max_underground_distance then entry.max_underground_distance = connection.max_underground_distance end
            if shape == "2.1" then
                entry.alt_direction = connection.alt_direction
                entry.alt_position = connection.alt_position
            elseif connection.alt_direction or connection.alt_position then
                error("fixture gives a 2.0 pipe connection 2.1-only members", 2)
            end
            connections[index] = entry
        end
        local fields = {valid = true, index = spec.index or 1,
            production_type = spec.production_type or "input-output",
            minimum_temperature = spec.minimum_temperature or 0,
            maximum_temperature = spec.maximum_temperature or 1000,
            filter = spec.filter and prototypes.fluid[spec.filter] or nil,
            pipe_connections = connections}
        if shape ~= "2.1" then fields.volume = spec.volume or 100 end
        return H.lua_object("LuaFluidBoxPrototype", fields, FLUID_BOX_MEMBERS[shape])
    end

    --Gives an existing machine its fluid boxes; boxes are world.fluid_box(...) results in prototype order
    function world.set_fluid_boxes(machine_name, boxes)
        local machine = prototypes.entity[machine_name]
        if not machine then error("no such machine " .. tostring(machine_name), 2) end
        machine.fluidbox_prototypes = boxes
    end

    --spec: {name, max_distance (default 10), underground (name of the matching pipe-to-ground)}
    function world.add_pipe(spec)
        return infrastructure({name = spec.name, type = "pipe"},
            {fluidbox_prototypes = {world.fluid_box({connections = {
                {offset = {x = 0, y = -1}, direction = defines.direction.north},
                {offset = {x = 1, y = 0}, direction = defines.direction.east},
                {offset = {x = 0, y = 1}, direction = defines.direction.south},
                {offset = {x = -1, y = 0}, direction = defines.direction.west},
            }})}})
    end

    --spec: {name, max_distance (default 10)}
    function world.add_pipe_to_ground(spec)
        local distance = spec.max_distance or 10
        return infrastructure({name = spec.name, type = "pipe-to-ground"},
            {max_underground_distance = distance,
             --vanilla: the exposed connection faces north in the default orientation, the underground one faces south
             fluidbox_prototypes = {world.fluid_box({connections = {
                {offset = {x = 0, y = -1}, direction = defines.direction.north, connection_type = "normal"},
                {offset = {x = 0, y = 1}, direction = defines.direction.south, connection_type = "underground",
                 max_underground_distance = distance},
             }})}})
    end

    --spec: {name, tile_width, supply_area (half-width in tiles at normal quality), wire_distance, quality_affects_supply_area,
    --  supply_bonus_per_level (default 0), wire_bonus_per_level (default 0)}
    function world.add_electric_pole(spec)
        local supply, wire = spec.supply_area or 2, spec.wire_distance or 7.5
        return infrastructure({name = spec.name, type = "electric-pole", tile_width = spec.tile_width or 1, tile_height = spec.tile_height or spec.tile_width or 1},
            {quality_affects_supply_area_distance = spec.quality_affects_supply_area == true,
             get_supply_area_distance = function(quality)
                 local level = quality and prototypes.quality[quality] and prototypes.quality[quality].level or 0
                 if not spec.quality_affects_supply_area then return supply end
                 return supply + level * (spec.supply_bonus_per_level or 0)
             end,
             get_max_wire_distance = function(quality)
                 local level = quality and prototypes.quality[quality] and prototypes.quality[quality].level or 0
                 return wire + level * (spec.wire_bonus_per_level or 0)
             end})
    end

    --spec: {name, tile_width (default 4), logistic_radius (default 25), construction_radius (default 55), connection_distance (default 50)}
    function world.add_roboport(spec)
        return infrastructure({name = spec.name, type = "roboport", tile_width = spec.tile_width or 4, tile_height = spec.tile_height or spec.tile_width or 4,
                energy_kw = spec.energy_kw or 50},
            {logistic_radius = spec.logistic_radius or 25,
             construction_radius = spec.construction_radius or 55,
             connection_distance = spec.connection_distance or 50})
    end

    --The vanilla-shaped set every blueprint fixture starts from: one belt family, inserter, pipes, pole, roboport
    function world.add_default_infrastructure()
        world.add_transport_belt({name = "transport-belt", items_per_second = 15})
        world.add_underground_belt({name = "underground-belt", items_per_second = 15, max_distance = 5, related = "transport-belt"})
        world.add_splitter({name = "splitter", items_per_second = 15})
        world.add_inserter({name = "inserter"})
        world.add_pipe({name = "pipe"})
        world.add_pipe_to_ground({name = "pipe-to-ground", max_distance = 10})
        world.add_electric_pole({name = "medium-electric-pole", supply_area = 3.5, wire_distance = 9,
            quality_affects_supply_area = true, supply_bonus_per_level = 0.5, wire_bonus_per_level = 0})
        world.add_roboport({name = "roboport"})
        return world
    end

    function world.init()
        for _, player in pairs(game.players) do
            for recipe_name, _ in pairs(prototypes.recipe) do
                player.force.recipes[recipe_name] = H.lua_object("LuaRecipe",
                    {name = recipe_name, valid = true, productivity_bonus = world.research_bonus_by_recipe_name[recipe_name] or 0}, FORCE_RECIPE_MEMBERS)
            end
        end
        require("logic.indexer").run()
        storage.computation_stack = {}
        for index, _ in pairs(game.players) do
            require("logic.player_data").initialize_player_data(index)
        end
    end

    --One recipe serves one product, as the recipe button enforces; a fixture breaking that would test a state the mod never stores
    function world.bind(product_full_name, recipe_name, player_index)
        local player_storage = storage[player_index or 1]
        local bound_product = player_storage.product_full_names_by_recipe_name[recipe_name]
        if bound_product and bound_product ~= product_full_name then
            error("fixture binds recipe " .. recipe_name .. " to " .. product_full_name .. " while it serves " .. bound_product, 2)
        end
        player_storage.recipes_by_product_full_name[product_full_name] = prototypes.recipe[recipe_name]
        player_storage.product_full_names_by_recipe_name[recipe_name] = product_full_name
    end

    --Binds a product to a recipe that consumes it, as a pick from a consumer control stores it
    function world.bind_consumer(product_full_name, recipe_name, player_index)
        world.bind(product_full_name, recipe_name, player_index)
        storage[player_index or 1].consumer_product_full_names[product_full_name] = true
    end

    return world
end

--Raises a custom input as the engine would: a plain CustomInputEvent. params: {player_index (default 1), element, in_gui, selected_prototype}.
--Never invents what the cursor hovers and never runs the vanilla action linked to the same key.
function H.press(world, input_name, params)
    params = params or {}
    local handler = world.handlers.events[input_name]
    if not handler then error("no handler registered for custom input " .. tostring(input_name), 2) end
    local player_index = params.player_index or 1
    local element = params.element
    local in_gui = params.in_gui
    if in_gui == nil then in_gui = element ~= nil end
    if element ~= nil then
        if in_gui == false then error("a custom input over a GUI element has in_gui true", 2) end
        if element.valid ~= true then error("custom input element is not valid", 2) end
        if element.player_index ~= player_index then error("custom input element belongs to another player", 2) end
        --assumed engine rule (in-game check G18): Factorio pipettes a choose-elem-button itself, and the linked custom input does not fire there
        if input_name == "hxrrc_pipette" and element.type == "choose-elem-button" then
            error("Factorio 2.0.77 pipettes choose-elem-buttons itself; the custom input never fires there", 2)
        end
    end
    local selected = params.selected_prototype
    if selected ~= nil and not (type(selected) == "table" and type(selected.base_type) == "string" and type(selected.derived_type) == "string"
        and type(selected.name) == "string") then
        error("selected_prototype must be {base_type, derived_type, name}", 2)
    end
    --Vanilla Q runs after the mod's input (CustomInputPrototype consuming = "none"). Observed in game 2026-09-16 on machine sprite-buttons, assumed for
    --beacons: when the hand already holds the ghost of the item placing the entity the button shows, vanilla Q empties the hand. Decided from the
    --hand before the mod's handler, so a ghost the handler itself writes (a copy) is never cleared. Quality is not compared; real stacks not modelled.
    local clears = false
    if input_name == "hxrrc_pipette" and world.vanilla_pipette_clears and element ~= nil and element.type == "sprite-button" then
        local entity_name = type(element.sprite) == "string" and element.sprite:match("^entity/(.+)$") or nil
        local entity = entity_name and prototypes.entity[entity_name] or nil
        local items = entity and entity.items_to_place_this or nil
        local cursor = world.cursors[player_index] or {}
        if items and items[1] and cursor.stack == nil and cursor.ghost and cursor.ghost.name == items[1].name then
            clears = true
        end
    end
    local result = handler({name = input_name, tick = world.tick, player_index = player_index, input_name = input_name,
        cursor_position = {x = 0, y = 0}, cursor_display_location = {x = 0, y = 0}, element = element, in_gui = in_gui, selected_prototype = selected})
    if clears then
        game.players[player_index].clear_cursor()
    end
    return result
end

--The module a slot shows as {name, quality}, quality nil for normal: read from a slot sprite-button, or from a chooser slot built by 1.1.23/1.1.24
function H.slot_value(slot_button)
    if slot_button.type ~= "sprite-button" then
        return slot_button.elem_value
    end
    if not slot_button.sprite then
        return nil
    end
    local quality = slot_button.quality and slot_button.quality.name
    return {name = slot_button.sprite:match("^item/(.+)$"), quality = quality ~= "normal" and quality or nil}
end

--Picks through the picker window the way a player does: nil right-clicks the button; a value left-clicks it, then clicks the choice, its quality
--(normal when none) and the tick. Works for module slots, machine buttons and beacon buttons (all sprite-buttons). Returns false when no picker
--opened (a stale button); errors when the picker does not offer the choice or quality, since a player could not pick it.
function H.pick_choice(button, value, tick)
    if button.type ~= "sprite-button" then error("H.pick_choice drives sprite-buttons, got " .. tostring(button.type), 2) end
    local player_index = button.player_index
    tick = tick or 0
    local function click(element, mouse_button, at)
        event_handlers.on_gui_click[element.name]({element = element, player_index = player_index, tick = at or tick,
            button = mouse_button or defines.mouse_button_type.left})
    end
    if value == nil then
        click(button, defines.mouse_button_type.right)
        return true
    end
    click(button)
    local state = storage[player_index].module_picker
    if not state then return false end
    local function find(root, name, key, wanted)
        if root.name == name and root.tags[key] == wanted then return root end
        for _, child in ipairs(root.children) do
            local found = find(child, name, key, wanted)
            if found then return found end
        end
    end
    local choice_button = find(state.frame, "hxrrc_picker_choice_button", "choice", value.name)
    if not choice_button then error("the picker does not offer " .. tostring(state.kind) .. " " .. tostring(value.name), 2) end
    local quality_button = find(state.frame, "hxrrc_picker_quality_button", "quality", value.quality or "normal")
    if not quality_button then error("the picker does not offer quality " .. tostring(value.quality), 2) end
    click(choice_button, nil, tick)
    click(quality_button, nil, tick + 100)
    click(state.frame.picker_footer.hxrrc_picker_confirm_button, nil, tick + 200)
    return true
end

--A module slot pick through the picker window (see H.pick_choice)
function H.pick_module(slot_button, value, tick)
    if slot_button.type ~= "sprite-button" then error("H.pick_module drives slot sprite-buttons, got " .. tostring(slot_button.type), 2) end
    return H.pick_choice(slot_button, value, tick)
end

--Builds a sheet and types the targets into it without computing. targets: {{item | fluid, quality (items only), rate, unit = "/s" | "/m"}}
function H.fill_sheet(targets, player_index)
    local Sheet = require "gui.sheet"
    local sheet_pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, player_index or 1)
    Sheet.new(sheet_pane)
    sheet_pane.selected_tab_index = 1
    local sheet_flow = sheet_pane.tabs[1].content
    for index, target in ipairs(targets) do
        local row = sheet_flow.input_container.children[index]
        row.rate_textfield.text = string.format("%.17g", target.rate) --17 significant digits round-trip a double; tostring keeps 14
        row.time_unit_dropdown.selected_index = target.unit == "/m" and 1 or 2
        local button_name = target.fluid and "hxrrc_desired_fluid_button" or "hxrrc_desired_item_button"
        local value = target.fluid or target.item
        if not target.fluid and row[button_name].elem_type == "item-with-quality" then
            value = {name = target.item, quality = target.quality}
        elseif target.quality then
            error("fixture gives a quality to a button of elem_type " .. tostring(row[button_name].elem_type), 2)
        end
        row[button_name].elem_value = value
        event_handlers.on_gui_elem_changed[button_name]({element = row[button_name], player_index = player_index or 1})
    end
    return sheet_pane, sheet_flow
end

--Builds a sheet, types the targets into it and presses Compute. options: {round_up = true} ticks the sheet's round-up checkbox first
function H.run_sheet(targets, player_index, options)
    local sheet_pane, sheet_flow = H.fill_sheet(targets, player_index)
    if options and options.round_up then
        require("gui.sheet").round_up_checkbox_of(sheet_flow).state = true
    end
    require("gui.sheet").calculate(require("gui.sheet").compute_button_of(sheet_flow))
    return H.parse_report(sheet_flow.output_flow), sheet_pane
end

local function number_in(caption)
    return tonumber(caption:match("(-?[%d%.]+)"))
end

--Localised captions read back as their key, plain captions as themselves
local function caption_key(caption)
    return type(caption) == "table" and caption[1] or caption
end

--The entity a machine or beacon button shows: a sprite-button keeps it in its tags, a choose-elem-button (burners, reports built before 1.1.27)
--in its value
local function shown_entity(button)
    if button.type == "sprite-button" then
        return button.tags.name and {name = button.tags.name, quality = button.tags.quality}
    end
    return button.elem_value
end

--The machine cell's lines of a quality loop row: {[stage] = {machine_button, machine, machine_sprite, machines, reason, caption, tooltip}}
local function parse_loop_lines(machine_cell)
    local lines = {}
    for _, line in ipairs(machine_cell.children) do
        local entry = {}
        local label = line.children[#line.children]
        for _, child in ipairs(line.children) do
            if child.name == "hxrrc_choose_loop_machine_button" then
                entry.machine_button, entry.machine = child, shown_entity(child)
            elseif child.type == "sprite-button" then
                entry.machine_sprite = child
            end
        end
        if type(label.caption) == "table" then
            entry.reason = label.caption[1]
        else
            entry.machines = number_in(label.caption)
        end
        entry.caption, entry.tooltip = label.caption, label.tooltip
        lines[line.tags.stage] = entry
    end
    return lines
end

--Reads the report table back into {energy_mw, pollution_per_minute, energy_caption, pollution_caption, rows = {[product_full_name] = row}, row_count,
--  loops = {[loop key] = loop}, loop_row_count}.
--row: {rate, kind, machines, machine_caption, machine_tooltip, machine, machine_button, reason, module_cell, recipe_button}; numbers are nil where the report shows none.
--Rows of items above normal are keyed by QualityId.encode(item, quality) read from the sprite and its quality badge.
--loop: {tiers = {{quality, rate, craft = line, recycle = line, module_flow}} in row order, tiers_by_quality, reason (first tier's craft line),
--  recipe_button (the loop recipe button, or in 2.1 the item's recipe button), pool = {craft? no: recycle = line, module_flow, recycle_button}}
function H.parse_report(output_flow)
    local QualityId = require "logic.quality_id"
    local report
    for _, child in ipairs(output_flow.children) do
        if child.name == "report" then report = child end
    end
    if not report then return nil end
    local cells = report.children
    local energy_caption, pollution_caption = cells[2].caption, cells[4].children[1].caption
    local parsed = {energy_caption = caption_key(energy_caption), pollution_caption = caption_key(pollution_caption), rows = {}, row_count = 0,
        loops = {}, loop_row_count = 0}
    parsed.energy_mw = type(energy_caption) == "string" and number_in(energy_caption) or nil
    parsed.pollution_per_minute = type(pollution_caption) == "string" and number_in(pollution_caption) or nil
    local HEADER_CELLS = 8
    assert((#cells - HEADER_CELLS) % 4 == 0, "report cell count " .. #cells .. " is not header + whole rows")
    local function loop_of(key)
        local loop = parsed.loops[key] or {tiers = {}, tiers_by_quality = {}}
        parsed.loops[key] = loop
        return loop
    end
    for first = HEADER_CELLS + 1, #cells, 4 do
        local item_cell, machine_cell, module_cell, recipe_cell = cells[first], cells[first + 1], cells[first + 2], cells[first + 3]
        local icon = item_cell.children[1]
        --the pool and assist rows show an icon where other rows show their rate
        local rate_caption = item_cell.children[2].type == "label" and item_cell.children[2].caption or nil
        local rate = type(rate_caption) == "string" and number_in(rate_caption) or nil
        local quality = icon.type == "sprite-button" and icon.quality and icon.quality.name or nil
        if item_cell.tags.assist then
            local loop = loop_of(item_cell.tags.loop_key)
            loop.assist = parse_loop_lines(machine_cell).assist or {}
            loop.assist.item_button, loop.assist.icon = item_cell.children[1], item_cell.children[2]
            loop.assist.module_flow = module_cell
            loop.assist.recipe_button = recipe_cell.children[1]
            loop.assist.row_index = parsed.loop_row_count + 1
            parsed.loop_row_count = parsed.loop_row_count + 1
        elseif item_cell.tags.pool then
            local loop = loop_of(item_cell.tags.loop_key)
            loop.pool = parse_loop_lines(machine_cell)
            loop.pool.icon = item_cell.children[1]
            loop.pool.module_flow = module_cell
            loop.pool.recycle_button = recipe_cell.children[1]
            parsed.loop_row_count = parsed.loop_row_count + 1
        elseif icon.type == "sprite-button" and icon.tags.loop_key then
            local loop = loop_of(icon.tags.loop_key)
            local tier = parse_loop_lines(machine_cell)
            tier.quality, tier.rate, tier.module_flow, tier.rate_tooltip = quality or "normal", rate, module_cell, item_cell.children[2].tooltip
            loop.tiers[#loop.tiers + 1] = tier
            loop.tiers_by_quality[tier.quality] = tier
            if #loop.tiers == 1 then
                loop.reason = tier.craft and tier.craft.reason
            end
            if recipe_cell.type == "flow" then
                for _, child in ipairs(recipe_cell.children) do
                    if child.name == "hxrrc_choose_loop_recipe_button" or child.name == "hxrrc_choose_recipe_button" then loop.recipe_button = child end
                end
            end
            parsed.loop_row_count = parsed.loop_row_count + 1
        else
            local product_full_name = icon.sprite
            if quality then
                product_full_name = QualityId.encode(icon.sprite:match("^item/(.+)$"), quality)
            end
            local row = {rate = rate, quality = quality}
            local machine_button_name = machine_cell.type == "flow" and machine_cell.children[1] and machine_cell.children[1].name
            if machine_button_name == "hxrrc_choose_crafting_machine_button" or machine_button_name == "hxrrc_choose_burner_entity_button" then
                row.kind = machine_button_name == "hxrrc_choose_burner_entity_button" and "burner" or "solved"
                local label = machine_cell.children[2]
                if type(label.caption) == "table" then
                    row.reason = label.caption[1]
                else
                    row.machines = number_in(label.caption)
                end
                row.machine_caption = label.caption
                row.machine_tooltip = label.tooltip
                row.machine = shown_entity(machine_cell.children[1])
                row.machine_button = machine_cell.children[1]
                row.module_cell = module_cell
            else
                row.kind = machine_cell.caption[1]
                if row.kind ~= "hxrrc.byproduct" and row.kind ~= "hxrrc.unselected_recipe" and row.kind ~= "hxrrc.not_automatically_craftable" then
                    row.reason = row.kind
                end
            end
            row.recipe_cell = recipe_cell
            row.recipe_button = recipe_cell.type == "flow" and recipe_cell.children[1] or nil
            row.burner_button = recipe_cell.type == "flow" and recipe_cell.children[2] or nil
            assert(not parsed.rows[product_full_name], "report has two rows for " .. product_full_name)
            parsed.rows[product_full_name] = row
            parsed.row_count = parsed.row_count + 1
        end
    end
    return parsed
end

--Names of the recipes a choose-elem-button of elem_type recipe lists with these filters, sorted. Documented 2.0.77 rules: a filter joins the one
--before it with its mode ("or" by default), "and" binds tighter than "or", invert negates one filter. Supports the filters the mod uses.
function H.recipes_matching(elem_filters)
    local function matches(recipe, filter)
        local result
        if filter.filter == "category" then
            result = (rawget(recipe, "category") or (rawget(recipe, "categories") or {})[1]) == filter.category
        elseif filter.filter == "hidden" then
            result = recipe.hidden == true
        else
            local list_name, kind = filter.filter:match("^has%-(%a+)%-(%a+)$")
            local list = list_name == "ingredient" and recipe.ingredients or recipe.products
            local names = {}
            for _, inner in ipairs(filter.elem_filters) do names[inner.name] = true end
            result = false
            for _, entry in ipairs(list) do
                if entry.type == kind and names[entry.name] then result = true end
            end
        end
        if filter.invert then result = not result end
        return result
    end
    local found = {}
    for name, recipe in pairs(prototypes.recipe) do
        local any, run = false, nil
        for index, filter in ipairs(elem_filters) do
            local value = matches(recipe, filter)
            if index > 1 and filter.mode == "and" then
                run = run and value
            else
                if run then any = true end
                run = value
            end
        end
        if run then any = true end
        if any then found[#found + 1] = name end
    end
    table.sort(found)
    return found
end

local results = {passed = 0, failed = 0, names = {}}

--A failure the assertion helpers raised, versus anything else that went wrong (nil index, a refused mocked member, a fixture blowing up).
--Gates read the tag: a red proof and a killed mutant need [assert]; [error] means the case never reached its assertion.
H.ASSERT_MARK = "RRC-ASSERT: "

function H.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
        local tag = tostring(err):find(H.ASSERT_MARK, 1, true) and "[assert]" or "[error]"
        print("FAIL " .. name .. " " .. tag .. "\n  " .. tostring(err):gsub("\n", "\n  "))
    end
end

--NaN compares false with everything, so a plain tolerance check would let it pass
local function check_finite(actual, what)
    if type(actual) ~= "number" or actual ~= actual or actual == math.huge or actual == -math.huge then
        error(H.ASSERT_MARK .. string.format("%s: expected a finite number, got %s", what, tostring(actual)), 3)
    end
end

function H.near(actual, expected, what)
    check_finite(actual, what)
    if math.abs(actual - expected) > TOLERANCE then
        error(H.ASSERT_MARK .. string.format("%s: expected %.12g, got %s", what, expected, tostring(actual)), 2)
    end
end

--Relative tolerance for large magnitudes, where one unit of rounding already exceeds the absolute tolerance
function H.near_relative(actual, expected, what)
    check_finite(actual, what)
    if math.abs(actual - expected) > TOLERANCE * math.max(1, math.abs(expected)) then
        error(H.ASSERT_MARK .. string.format("%s: expected %.12g, got %s", what, expected, tostring(actual)), 2)
    end
end

function H.equal(actual, expected, what)
    if actual ~= expected then
        error(H.ASSERT_MARK .. string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end

--Tables equal key by key, recursively
function H.deep_equal(actual, expected, what)
    local function compare(a, b, path)
        if type(a) ~= "table" or type(b) ~= "table" then
            if a ~= b then error(H.ASSERT_MARK .. string.format("%s: at %s expected %s, got %s", what, path, tostring(b), tostring(a)), 4) end
            return
        end
        for key, value in pairs(b) do compare(a[key], value, path .. "." .. tostring(key)) end
        for key, value in pairs(a) do
            if b[key] == nil then error(H.ASSERT_MARK .. string.format("%s: at %s unexpected %s", what, path .. "." .. tostring(key), tostring(value)), 4) end
        end
    end
    compare(actual, expected, "")
end

function H.errors(fn, pattern, what)
    local ok, err = pcall(fn)
    if ok then error(H.ASSERT_MARK .. what .. ": expected an error matching '" .. pattern .. "', got none", 2) end
    if not tostring(err):find(pattern, 1, true) then error(H.ASSERT_MARK .. what .. ": error '" .. tostring(err) .. "' does not contain '" .. pattern .. "'", 2) end
end

--Advances the tick and fires the mod's registered on_tick that many times, the way the game does. Every incremental
--job is driven through this, so a test cannot accidentally prove progress by calling a step function directly.
function H.run_ticks(world, count)
    local handler = world.handlers.events[defines.events.on_tick]
    for _ = 1, count or 1 do
        world.advance_tick(1)
        world.flush_cursor_events()
        if handler then handler({name = defines.events.on_tick, tick = world.tick}) end
    end
    return world.tick
end

--Decodes what the mod's export action produced: base64 -> zlib -> JSON -> table. The offline acceptance check is
--python3 base64.b64decode + zlib.decompress, so a test that reads this is reading the same bytes that decoder gets.
function H.decode_export(encoded)
    local json = helpers.decode_string((encoded or ""):gsub("%s", ""))
    if json == nil then return nil, "not a zlib stream" end
    local payload = helpers.json_to_table(json)
    if payload == nil then return nil, "not JSON" end
    return payload, json
end

--Shapes to run version-parametrized cases against; RRC_SHAPES overrides (e.g. "hybrid" for a red run on cb6b529)
function H.shapes()
    local shapes = {}
    for shape in (os.getenv("RRC_SHAPES") or "2.0,2.1"):gmatch("[^,]+") do shapes[#shapes + 1] = shape end
    return shapes
end

function H.done(file)
    print(string.format("%s [%s]: %d cases, %d passed, %d failed", file, _VERSION, results.passed + results.failed, results.passed, results.failed))
    os.exit(results.failed == 0 and 0 or 1)
end

return H

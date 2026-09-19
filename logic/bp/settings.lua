--What the player picked to build with, kept per sheet.
--
--Owned by lane W3-infra. A belt choice carries its family: the matching underground belt and splitter at the same
--quality. A modded belt with no known family is refused rather than quietly replaced with a vanilla tier.
--
--  {roboport = {name, quality}, pole = {...}, belt = {...}, inserter = {...}, pipe = {...}, underground_pipe = {...},
--   input_edge = "left"|"right"|"top"|"bottom", output_edge = same, surface = string}
--
--Defaults: left in, top out, as in the reference layout. The two edges must differ. New sheets start from the
--player's last choices; changing one sheet never changes another.
local Settings = {}

Settings.EDGES = {"left", "right", "top", "bottom"}
Settings.DEFAULT_INPUT_EDGE = "left"
Settings.DEFAULT_OUTPUT_EDGE = "top"

local INFRASTRUCTURE = {
    {key = "roboport", catalog_key = "robo", default = "roboport"},
    {key = "pole", catalog_key = "pole", default = "medium-electric-pole"},
    {key = "belt", catalog_key = "belt", default = "transport-belt"},
    {key = "inserter", catalog_key = "inserter", default = "inserter"},
    {key = "pipe", catalog_key = "pipe", default = "pipe"},
    {key = "underground_pipe", catalog_key = "underground_pipe", default = "pipe-to-ground"},
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function name_of(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    if type(value) == "table" then return value.name or value.prototype or value.id or value.belt end
    local ok, name = pcall(function() return value.name end)
    return ok and name or nil
end

local function quality_of(value)
    if type(value) ~= "table" then return "normal" end
    local quality = value.quality
    local name = name_of(quality)
    return name or "normal"
end

local function entity_name(value)
    local name = name_of(value)
    if type(name) == "string" then
        local kind, bare = name:match("^([^/]+)/(.+)$")
        if kind == "entity" then return bare end
    end
    return name
end

local function entity_is(prototype, entity_type)
    if not prototype then return false end
    local ok, value = pcall(function() return prototype.valid end)
    if ok and value == false then return false end
    local type_ok, actual = pcall(function() return prototype.type end)
    return type_ok and actual == entity_type
end

local function prototype_named(name, entity_type)
    if not rawget(_G, "prototypes") then return nil end
    local prototype = prototypes.entity[name]
    return entity_is(prototype, entity_type) and prototype or nil
end

local function related_underground(belt_name)
    if not rawget(_G, "prototypes") then return nil end
    local names = {}
    for name, _ in pairs(prototypes.entity) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local prototype = prototypes.entity[name]
        if entity_is(prototype, "underground-belt") then
            local ok, related = pcall(function() return prototype.related_underground_belt end)
            local related_name = ok and name_of(related) or nil
            if related_name == belt_name then return name end
        end
    end
end

local function belt_prefix(belt_name)
    if belt_name == "transport-belt" then return "" end
    local prefix = belt_name:match("^(.*)%-transport%-belt$")
    if prefix ~= nil then return prefix end
    prefix = belt_name:match("^(.*)%-belt$")
    if prefix ~= nil then return prefix end
    return nil
end

--The engine has no splitter-to-belt relation. The stable family convention is the same one used by the base game:
--<prefix>-transport-belt, <prefix>-underground-belt and <prefix>-splitter. A related underground belt is accepted
--when a mod uses a different underground name, but the splitter still has to use the belt's own prefix.
local function known_splitter(belt_name)
    local prefix = belt_prefix(belt_name)
    if prefix == nil then return nil end
    local names
    if prefix == "" then
        names = {"splitter"}
    else
        names = {prefix .. "-splitter"}
    end
    for _, name in ipairs(names) do
        if prototype_named(name, "splitter") then return name end
    end
end

local function conventional_underground(belt_name)
    local prefix = belt_prefix(belt_name)
    if prefix == nil then return nil end
    local name = prefix == "" and "underground-belt" or prefix .. "-underground-belt"
    return prototype_named(name, "underground-belt") and name or nil
end

local function normalize_choice(value)
    if value == false then return false end
    local name = entity_name(value)
    if not name then return nil end
    local result = {name = name, quality = quality_of(value)}
    if type(value) == "table" then
        if type(value.underground) == "string" then result.underground = value.underground end
        if type(value.splitter) == "string" then result.splitter = value.splitter end
        if type(value.underground_name) == "string" then result.underground = value.underground_name end
        if type(value.splitter_name) == "string" then result.splitter = value.splitter_name end
    end
    return result
end

local function add_belt_family(choice)
    if not choice or choice == false or choice.name == nil then return choice end
    local family = Settings.belt_family(choice.name, choice.quality)
    if family then
        choice.underground = family.underground
        choice.splitter = family.splitter
    end
    return choice
end

local function defaults()
    local settings = {
        roboport = {name = "roboport", quality = "normal"},
        pole = {name = "medium-electric-pole", quality = "normal"},
        belt = {name = "transport-belt", quality = "normal"},
        inserter = {name = "inserter", quality = "normal"},
        pipe = {name = "pipe", quality = "normal"},
        underground_pipe = {name = "pipe-to-ground", quality = "normal"},
        input_edge = Settings.DEFAULT_INPUT_EDGE,
        output_edge = Settings.DEFAULT_OUTPUT_EDGE,
    }
    add_belt_family(settings.belt)
    return settings
end

local function normalized_settings(settings)
    settings = rawget(_G, "settings") and settings or {}
    local infrastructure = type(settings.infrastructure) == "table" and settings.infrastructure or settings
    local result = {}
    for _, definition in ipairs(INFRASTRUCTURE) do
        local value = infrastructure[definition.key]
        if value == nil and definition.key == "roboport" then value = infrastructure.robo end
        result[definition.key] = normalize_choice(value)
    end
    add_belt_family(result.belt)
    result.input_edge = settings.input_edge or settings.input or Settings.DEFAULT_INPUT_EDGE
    result.output_edge = settings.output_edge or settings.output or Settings.DEFAULT_OUTPUT_EDGE
    if settings.surface ~= nil then result.surface = settings.surface end
    return result
end

local function storage_of(player_index)
    return type(storage) == "table" and storage[player_index] or nil
end

function Settings.of_sheet(player_index, sheet_id)
    local player_storage = storage_of(player_index)
    if not player_storage then return defaults() end

    player_storage.blueprint_settings = player_storage.blueprint_settings or {}
    local stored = player_storage.blueprint_settings[sheet_id]
    if stored == nil then
        stored = player_storage.blueprint_last_settings or player_storage.last_blueprint_settings
        stored = stored and normalized_settings(stored) or defaults()
        player_storage.blueprint_settings[sheet_id] = copy(stored)
    else
        stored = normalized_settings(stored)
        player_storage.blueprint_settings[sheet_id] = copy(stored)
    end
    return copy(stored)
end

function Settings.store(player_index, sheet_id, settings)
    local normalized = normalized_settings(settings)
    local player_storage = storage_of(player_index)
    if player_storage and sheet_id ~= nil then
        player_storage.blueprint_settings = player_storage.blueprint_settings or {}
        player_storage.blueprint_settings[sheet_id] = copy(normalized)
        player_storage.blueprint_last_settings = copy(normalized)
    end
    return copy(normalized)
end

local function subject(kind, choice)
    local name = entity_name(choice) or kind
    return {kind = kind, name = name, quality = quality_of(choice)}
end

local function catalog_entry(catalog, definition, choice)
    local name = entity_name(choice)
    if not name then return nil end
    local projected = catalog and catalog[definition.catalog_key]
    if definition.key == "roboport" then projected = projected or (catalog and catalog.roboport) end
    if definition.key == "underground_pipe" then
        projected = catalog and catalog.underground_pipe
        if not projected and catalog and catalog.pipe and catalog.pipe.underground == name then
            projected = {name = name, quality = catalog.pipe.quality}
        end
    end
    if definition.key == "belt" and projected and projected.belt and projected.belt ~= name then projected = nil end
    if definition.key == "pipe" and projected and projected.pipe and projected.pipe ~= name then projected = nil end
    if projected and projected.name and projected.name ~= name then projected = nil end
    if not projected and catalog and catalog.entity then projected = catalog.entity[name] end
    return projected
end

local function quality_available(catalog, quality, player_index)
    if quality == "normal" then return true end
    if catalog and catalog.unlocked_qualities and catalog.unlocked_qualities[quality] == false then return false end
    if catalog and catalog.quality then
        local data = catalog.quality[quality]
        if data == nil then return false end
        if data.unlocked == false or data.available == false then return false end
    elseif rawget(_G, "prototypes") and prototypes.quality and not prototypes.quality[quality] then
        return false
    end

    local player = rawget(_G, "game") and game.players and game.players[player_index or 1]
    local force = player and player.force
    if force and type(force.is_quality_unlocked) == "function" then
        local ok, unlocked = pcall(force.is_quality_unlocked, quality)
        if ok and not unlocked then return false end
    end
    return true
end

local function family_matches(choice, catalog)
    if not choice or choice == false then return false end
    local family = Settings.belt_family(choice.name, choice.quality)
    if not family then return false end
    if choice.underground ~= nil and choice.underground ~= family.underground then return false end
    if choice.splitter ~= nil and choice.splitter ~= family.splitter then return false end
    local projected = catalog and catalog.belt
    if projected and projected.belt == choice.name then
        if projected.underground ~= nil and projected.underground ~= family.underground then return false end
        if projected.splitter ~= nil and projected.splitter ~= family.splitter then return false end
    end
    return true
end

--Checks one choice against the game: returns ok, reason code, subject
function Settings.validate(settings, catalog, player_index)
    settings = normalized_settings(settings)
    catalog = catalog or {}

    if settings.input_edge == settings.output_edge then
        return false, "BP_REJ_EDGES_EQUAL", {kind = "edge", name = "input/output", quality = "normal"}
    end

    for _, definition in ipairs(INFRASTRUCTURE) do
        local choice = settings[definition.key]
        if not choice or choice == false or not entity_name(choice) then
            return false, "BP_REJ_OPTION_PROTOTYPE_MISSING", subject("infrastructure", choice or definition.default)
        end
        if not quality_available(catalog, quality_of(choice), player_index) then
            return false, "BP_REJ_QUALITY_UNAVAILABLE", {kind = "quality", name = quality_of(choice), quality = quality_of(choice)}
        end
        local projected = catalog_entry(catalog, definition, choice)
        if not projected then
            return false, "BP_REJ_OPTION_PROTOTYPE_MISSING", subject("infrastructure", choice)
        end
        if projected.quality and projected.quality ~= quality_of(choice) then
            return false, "BP_REJ_QUALITY_UNAVAILABLE", {kind = "quality", name = quality_of(choice), quality = quality_of(choice)}
        end
    end

    if not family_matches(settings.belt, catalog) then
        return false, "BP_REJ_BELT_FAMILY_MISSING", subject("infrastructure", settings.belt)
    end
    return true, nil, nil
end

--The underground belt and splitter that belong to a chosen belt, at its quality; nil family when none is known
function Settings.belt_family(belt_name, quality)
    belt_name = entity_name(belt_name)
    quality = name_of(quality) or "normal"
    if not belt_name or not prototype_named(belt_name, "transport-belt") then return nil end

    local underground = related_underground(belt_name) or conventional_underground(belt_name)
    local splitter = known_splitter(belt_name)
    if not underground or not splitter then return nil end
    return {underground = underground, splitter = splitter, quality = quality}
end

return Settings

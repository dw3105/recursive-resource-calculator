-- The blueprint direction points at pickup; the tile behind the inserter is its drop cell.
-- These checks deliberately inspect Serialize.result, not the internal candidate positions.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Serialize = require "logic.bp.serialize"

local PLAYER_BLUEPRINT = os.getenv("HOME") .. "/share/RRC/red_science_1s_manual_bp.txt"
local CARDINAL = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}

local function cell(x, y) return math.floor(x + 1e-9), math.floor(y + 1e-9) end
local function key(x, y) return tostring(x) .. ":" .. tostring(y) end

local function occupant(map, x, y)
    local x0, y0 = cell(x, y)
    return map[key(x0, y0)] or "empty"
end

local function transfer_ok(role, direction, origin_x, origin_y, tiles)
    local vector = CARDINAL[direction]
    if not vector then return false end
    local pickup = occupant(tiles, origin_x + vector[1], origin_y + vector[2])
    local drop = occupant(tiles, origin_x - vector[1], origin_y - vector[2])
    if role == "input" then return drop == "machine" end
    if role == "output" then return pickup == "machine" end
    return false
end

local function make_fixture(shape)
    H.new_world(shape)
    local catalog = {
        entity = {
            machine = {name = "machine", etype = "assembling-machine", tile_w = 3, tile_h = 3},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1},
        },
        inserter = {name = "inserter", pickup_offset = {x = 0, y = 1},
            drop_offset = {x = 0, y = -1.203125}},
    }
    local plan = {steps = {{step_id = "machine", machine = "machine", machine_count = 1,
        inputs = {{flow_id = "item/in", rate_per_second = 1}},
        outputs = {{flow_id = "item/out", rate_per_second = 1}}}}, flows = {}}
    local state = Groups.begin({plan = plan, catalog = catalog})
    for _ = 1, 20 do
        if state.done then break end
        Groups.step(state, {ops = 20})
    end
    local block = state.result and state.result.candidates[1] and state.result.candidates[1].blocks[1]
    assert(block, "small generated fixture has a machine block")
    local placement = Groups.materialize(block, {x = 20, y = 30, dir = Grid.NORTH})
    local internal = {}
    for _, entity in ipairs(placement.entities) do
        if entity.kind == "inserter" then
            internal[key(entity.position.x, entity.position.y)] = {
                role = entity.role, direction = entity.dir}
        end
    end
    local serialized = Serialize.begin({entities = placement.entities, catalog = catalog})
    for _ = 1, 100 do
        if serialized.done then break end
        Serialize.step(serialized, {ops = 100})
    end
    assert(serialized.ok and serialized.result, "small fixture serializes")

    local tiles = {}
    for _, entity in ipairs(serialized.result.entities or {}) do
        local x, y = cell(entity.position.x, entity.position.y)
        if entity.name == "machine" then
            -- A 3x3 machine centered on integer coordinates occupies the surrounding nine tiles.
            for dx = -1, 1 do for dy = -1, 1 do tiles[key(x + dx, y + dy)] = "machine" end end
        elseif entity.name == "transport-belt" then
            tiles[key(x, y)] = "belt"
        end
    end
    local rows = {}
    for _, entity in ipairs(serialized.result.entities or {}) do
        if entity.name == "inserter" then
            local origin_x, origin_y = cell(entity.position.x, entity.position.y)
            local published = entity.direction
            local v = CARDINAL[published]
            local pickup = v and {x = origin_x + v[1], y = origin_y + v[2]} or {x = origin_x, y = origin_y}
            local drop = v and {x = origin_x - v[1], y = origin_y - v[2]} or {x = origin_x, y = origin_y}
            local frame = internal[key(entity.position.x, entity.position.y)]
            rows[#rows + 1] = {id = entity.entity_number, role = frame.role,
                internal = frame.direction, published = published, pickup = pickup, drop = drop,
                pickup_occupant = occupant(tiles, pickup.x, pickup.y), drop_occupant = occupant(tiles, drop.x, drop.y),
                origin_x = origin_x, origin_y = origin_y, tiles = tiles,
                machine_cell = nil}
            -- Resolve this inserter's associated machine from the generated role endpoint recorded by the fixture.
            -- The compact fixture has one machine, so its serialized center is the reference tile.
        end
    end
    local machine
    for _, entity in ipairs(serialized.result.entities or {}) do
        if entity.name == "machine" then machine = entity; break end
    end
    assert(machine, "serialized fixture contains its machine")
    local mx, my = cell(machine.position.x, machine.position.y)
    for _, row in ipairs(rows) do row.machine_cell = {x = mx, y = my} end
    return rows
end

local function row_text(row)
    return string.format("id=%s role=%s internal=%s published=%s pickup=%s drop=%s",
        tostring(row.id), tostring(row.role), tostring(row.internal), tostring(row.published),
        row.pickup_occupant, row.drop_occupant)
end

local function shell_quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " ID0 player's working factory pins published pickup direction", function()
        H.new_world(shape)
        local file = io.open(PLAYER_BLUEPRINT, "r")
        H.equal(file ~= nil, true, "ID0 player blueprint exists at " .. PLAYER_BLUEPRINT)
        if not file then return end
        local encoded = file:read("*a")
        file:close()
        local command = "python3 -c 'import base64,json,sys,zlib; print(zlib.decompress(base64.b64decode(open(sys.argv[1]).read().strip()[1:])).decode())' "
            .. shell_quote(PLAYER_BLUEPRINT)
        local pipe = io.popen(command, "r")
        local json = pipe and pipe:read("*a") or nil
        local close_ok = pipe and pipe:close()
        local blueprint = close_ok and json and helpers.json_to_table(json) or nil
        local err = "python3 zlib/JSON decode failed"
        H.equal(type(blueprint) == "table", true, "ID0 player blueprint decodes: " .. tostring(err))
        if type(blueprint) ~= "table" then return end
        local found = false
        for _, entity in ipairs(blueprint.blueprint and blueprint.blueprint.entities or {}) do
            if entity.name and entity.name:find("inserter", 1, true)
                and entity.position.x == 206.5 and entity.position.y == 1076.5 and entity.direction == Grid.WEST then
                local v = CARDINAL[entity.direction]
                local machine_side = {x = entity.position.x + v[1], y = entity.position.y + v[2]}
                local drop_side = {x = entity.position.x - v[1], y = entity.position.y - v[2]}
                local factory_tiles = {}
                for _, other in ipairs(blueprint.blueprint.entities) do
                    if other.name and other.position then
                        local ox, oy = cell(other.position.x, other.position.y)
                        if other.name:find("transport-belt", 1, true) then factory_tiles[key(ox, oy)] = "belt" end
                        if other.name:find("assembling-machine", 1, true) then
                            for dx = -1, 1 do for dy = -1, 1 do factory_tiles[key(ox + dx, oy + dy)] = "machine" end end
                        end
                    end
                end
                local machine = false
                for _, other in ipairs(blueprint.blueprint.entities) do
                    if other.name and (other.name:find("assembling-machine", 1, true) or other.name:find("lab", 1, true))
                        and math.abs(other.position.x - drop_side.x) <= 1.5
                        and math.abs(other.position.y - drop_side.y) <= 1.5 then machine = true end
                end
                local pickup_side = {x = entity.position.x + v[1], y = entity.position.y + v[2]}
                print(string.format("ID0 id=%s role=input internal=unknown published=%s pickup=%s drop=%s",
                    tostring(entity.entity_number), tostring(entity.direction),
                    occupant(factory_tiles, pickup_side.x, pickup_side.y), occupant(factory_tiles, drop_side.x, drop_side.y)))
                found = machine and not (math.abs(machine_side.x - drop_side.x) < 0.01
                    and math.abs(machine_side.y - drop_side.y) < 0.01)
                break
            end
        end
        H.equal(found, true, "ID0 WEST hand at (206.5, 1076.5) has machine on published drop side")
    end)

    H.test(shape .. " ID1 generated input direction drops into its own machine", function()
        for _, row in ipairs(make_fixture(shape)) do
            if row.role == "input" then
                print("ID1 " .. row_text(row))
                local vector = CARDINAL[row.published]
                H.equal(vector ~= nil and transfer_ok(row.role, row.published, row.origin_x, row.origin_y, row.tiles),
                    true, "ID1 " .. row_text(row))
            end
        end
    end)

    H.test(shape .. " ID2 generated output direction picks from its own machine", function()
        for _, row in ipairs(make_fixture(shape)) do
            if row.role == "output" then
                print("ID2 " .. row_text(row))
                H.equal(transfer_ok(row.role, row.published, row.origin_x, row.origin_y, row.tiles), true,
                    "ID2 " .. row_text(row))
            end
        end
    end)

    H.test(shape .. " ID3 every generated published direction opposes internal direction", function()
        for _, row in ipairs(make_fixture(shape)) do
            print("ID3 " .. row_text(row))
            H.equal(row.published, (row.internal + 8) % 16, "ID3 " .. row_text(row))
        end
    end)

    H.test(shape .. " ID4 flipped published direction is rejected by transfer helper", function()
        local rows = make_fixture(shape)
        for _, row in ipairs(rows) do
            local flipped = (row.published + 8) % 16
            print("ID4 " .. row_text(row) .. " flipped=" .. tostring(flipped))
            H.equal(transfer_ok(row.role, flipped, row.origin_x, row.origin_y, row.tiles), false,
                "ID4 negative control flipped=" .. tostring(flipped) .. " " .. row_text(row))
        end
    end)
end

H.done("test_inserter_direction")

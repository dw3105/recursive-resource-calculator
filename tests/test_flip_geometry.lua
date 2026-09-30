-- FG1-FG4: flip geometry contract from engine fixtures; each case is red on round-51-base before the helper sites land.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Twin = require "tests.twins.lib.twin"
local Route = require "logic.bp.route"
local Serialize = require "logic.bp.serialize"

local function vector(text)
    local x, y = text:match("^(-?%d+),(-?%d+)$")
    return tonumber(x), tonumber(y)
end
local function direction(x, y)
    if x == 0 and y == -1 then return 0 elseif x == 1 and y == 0 then return 4
    elseif x == 0 and y == 1 then return 8 elseif x == -1 and y == 0 then return 12 end
end

H.test("FG1 every 2.0/2.1 fixture row follows north-frame mirror then turn", function()
    for _, version in ipairs({"2.0", "2.1"}) do
        local rows, bases = {}, {}
        for line in io.lines("tests/fixtures/flip_fluidboxes_" .. version .. ".txt") do
            local machine, ds, mirror, box, pos, target = line:match("^CONN (%S+) dir=(%d+) edir=%d+ mirror=(%a+) set=%a+ got=%a+ box=(%d+).- pos=(%-?%d+,%-?%d+) target=(%-?%d+,%-?%d+)$")
            if machine then
                local row = {machine=machine, dir=tonumber(ds), mirror=mirror == "true", box=tonumber(box), pos=pos, target=target}
                rows[#rows + 1] = row
                if row.dir == 0 and not row.mirror then
                    local key = row.machine .. ":" .. row.box
                    bases[key] = bases[key] or {}; bases[key][#bases[key] + 1] = row
                end
            end
        end
        H.equal(#rows > 0, true, version .. " fixture parsed")
        for _, row in ipairs(rows) do
            local possible, ex, ey = bases[row.machine .. ":" .. row.box] or {}, vector(row.pos)
            local qx, qy = vector(row.target)
            local expected = {ex, ey, direction(qx - ex, qy - ey)}
            local found = false
            for _, base in ipairs(possible) do
                local x, y = vector(base.pos)
                local tx, ty = vector(base.target)
                local px, py, pd = Grid.fluid_connection({position={x=x,y=y}, direction=direction(tx-x,ty-y)}, row.dir, row.mirror)
                if px == expected[1] and py == expected[2] and pd == expected[3] then found = true; break end
            end
            H.equal(found, true, version .. " " .. row.machine .. " box " .. row.box .. " row geometry")
        end
    end
end)

H.test("FG2 flipped twins have exact fluid verdicts", function()
    H.deep_equal(Twin.verdict(Twin.load("tests/twins/transport/fluid_flipped_ok.lua")), {}, "flipped box 1 connects")
    H.deep_equal(Twin.verdict(Twin.load("tests/twins/transport/fluid_flipped_bad.lua")), {"BP_V_FLUID_DISCONNECTED"}, "unflipped target rejected")
end)

H.test("FG3 route test helper uses the same connection geometry", function()
    local x,y,d = Grid.fluid_connection({positions={{x=-1,y=2}},direction=8}, 0, true)
    H.deep_equal({x,y,d}, {1,2,8}, "mirrored connection")
    local rotated = Route._test.rotate_connection({positions={{x=-1,y=2}},direction=8}, 0, 9, 9, true, true)
    H.deep_equal({rotated.x,rotated.y,rotated.direction}, {9,9,8}, "route mirrored connection")
end)

H.test("FG4 serializer preserves a machine mirror only when true", function()
    local function serialized(entity)
        local state = Serialize.begin({candidate={entities={entity}}})
        while not state.done do Serialize.step(state, {ops=1}) end
        return state.result.entities[1]
    end
    H.equal(serialized({name="foundry", position={x=0.5,y=0.5}, mirror=true}).mirror, true, "mirror emitted")
    H.equal(serialized({name="foundry", position={x=0.5,y=0.5}}).mirror, nil, "mirror omitted")
end)
H.done("test_flip_geometry")

--The round 8 harness additions, proven before any feature trusts them: the encoder produces a stream a real zlib
--decoder accepts, a progress bar refuses a value outside [0, 1], a blueprint stack round trips, quality changes a
--pole's reach, and an assertion failure is distinguishable from a crash.
local H = require "tests.harness"

local function world_with(shape)
    local world = H.new_world(shape)
    world.add_item("plate")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    return world
end

local function byte_at(text, index) return text:byte(index) end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " H8-1 encode_string emits a zlib stream: header, stored blocks, adler32", function()
        local world = world_with(shape)
        local payload = "the quick brown fox jumps over the lazy dog"
        local encoded = helpers.encode_string(payload)
        H.equal(type(encoded), "string", "encode_string returns a string")
        --decode the base64 by hand through the mock's own inverse, then look at the bytes
        local raw = select(2, pcall(function() return helpers.decode_string(encoded) end))
        H.equal(raw, payload, "decode_string is the inverse of encode_string")

        --adler32 of the payload, computed independently here, must be the last four bytes of the compressed stream
        local a, b = 1, 0
        for index = 1, #payload do
            a = (a + payload:byte(index)) % 65521
            b = (b + a) % 65521
        end
        local expected = b * 65536 + a
        --rebuild the raw deflate stream from the base64 the mock produced
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local values = {}
        for index = 1, #alphabet do values[alphabet:sub(index, index)] = index - 1 end
        local bytes, bits, count = {}, 0, 0
        for index = 1, #encoded do
            local character = encoded:sub(index, index)
            if character ~= "=" then
                bits, count = bits * 64 + values[character], count + 6
                if count >= 8 then
                    count = count - 8
                    local byte = math.floor(bits / 2 ^ count)
                    bits = bits - byte * 2 ^ count
                    bytes[#bytes + 1] = byte
                end
            end
        end
        H.equal(bytes[1], 0x78, "zlib CMF byte")
        H.equal((bytes[1] * 256 + bytes[2]) % 31, 0, "zlib header checksum")
        H.equal(math.floor(bytes[3] / 2) % 4, 0, "deflate block type is stored")
        local trailer = ((bytes[#bytes - 3] * 256 + bytes[#bytes - 2]) * 256 + bytes[#bytes - 1]) * 256 + bytes[#bytes]
        H.equal(trailer, expected, "adler32 trailer matches the payload")
    end)

    H.test(shape .. " H8-2 a debug payload survives table -> json -> compressed -> table", function()
        local world = world_with(shape)
        local payload = {format = "rrc-sheet-debug", schema_version = 1,
            targets = {{full_name = "item/plate", rate = 0.1}, {full_name = "fluid/water", rate = 12.5}},
            selection = {machine = "assembler", quality = "normal"}, empty_object = {}}
        local encoded = helpers.encode_string(helpers.table_to_json(payload))
        local decoded = H.decode_export(encoded)
        H.equal(decoded.format, "rrc-sheet-debug", "format survives")
        H.equal(decoded.schema_version, 1, "schema version survives")
        H.equal(decoded.targets[2].full_name, "fluid/water", "array order survives")
        H.near(decoded.targets[1].rate, 0.1, "full precision survives")
        H.equal(decoded.selection.machine, "assembler", "nested object survives")
    end)

    H.test(shape .. " H8-3 a failed encode returns nil, and only once", function()
        local world = world_with(shape)
        world.fail_next_encode()
        H.equal(helpers.encode_string("payload"), nil, "the failed encode returns nil rather than a short string")
        H.equal(type(helpers.encode_string("payload")), "string", "the next encode works")
    end)

    H.test(shape .. " H8-4 table_to_json refuses a value JSON cannot carry", function()
        local world = world_with(shape)
        H.errors(function() helpers.table_to_json({rate = 0 / 0}) end, "cannot serialize", "NaN is refused")
        H.errors(function() helpers.table_to_json({rate = math.huge}) end, "cannot serialize", "infinity is refused")
    end)

    H.test(shape .. " H8-5 a progress bar takes 0 to 1 and refuses anything else", function()
        local world = world_with(shape)
        local screen = game.get_player(1).gui.screen
        local bar = screen.add{type = "progressbar", name = "bar"}
        H.equal(bar.value, 0, "a new bar starts at zero")
        bar.value = 0.5
        H.near(bar.value, 0.5, "a fraction is kept")
        bar.value = 1
        H.equal(bar.value, 1, "one is inside the range; whether a job may write it is behaviour, not this check")
        H.errors(function() bar.value = 1.5 end, "must be a number in [0, 1]", "above the range is refused")
        H.errors(function() bar.value = -0.1 end, "must be a number in [0, 1]", "below the range is refused")
        H.errors(function() bar.value = "half" end, "must be a number in [0, 1]", "a non-number is refused")
    end)

    H.test(shape .. " H8-6 value, word_wrap and select_all belong to their own element types", function()
        local world = world_with(shape)
        local screen = game.get_player(1).gui.screen
        local bar = screen.add{type = "progressbar", name = "bar"}
        local box = screen.add{type = "text-box", name = "box", text = "payload"}
        local button = screen.add{type = "button", name = "button"}
        H.errors(function() return button.value end, "can only be used if this is", "a button has no value")
        H.errors(function() return bar.word_wrap end, "can only be used if this is", "a bar has no word_wrap")
        box.word_wrap = true
        box.read_only = true
        box.selectable = true
        H.equal(box.word_wrap, true, "a text box keeps word_wrap")
        H.equal(box.read_only, true, "a text box keeps read_only")
        H.equal(H.text_selected(box), false, "nothing is selected yet")
        box.select_all()
        H.equal(H.text_selected(box), true, "select_all marks the whole text")
        H.errors(function() button.select_all() end, "can only be used if this is textfield or text-box", "a button cannot select_all")
    end)

    H.test(shape .. " H8-7 a blueprint stack round trips entities without touching another item", function()
        local world = world_with(shape)
        local player = game.get_player(1)
        world.hold_item(1, "plate", "normal", 3)
        world.flush_cursor_events()
        H.equal(player.cursor_stack.name, "plate", "the player holds something else first")

        local staging = game.create_inventory(1)[1]
        staging.set_stack({name = "blueprint"})
        H.equal(staging.is_blueprint, true, "the staged item is a blueprint")
        H.equal(staging.is_blueprint_setup(), false, "an empty blueprint is not set up")
        staging.set_blueprint_entities({{entity_number = 1, name = "assembler", position = {x = 0.5, y = 0.5}}})
        staging.label = "1 plate/s"
        staging.blueprint_description = "external input: 1 ore/s"
        H.equal(staging.is_blueprint_setup(), true, "entities make it set up")
        H.equal(staging.get_blueprint_entities()[1].name, "assembler", "entities read back")
        H.equal(staging.label, "1 plate/s", "the label reads back")
        H.equal(player.cursor_stack.name, "plate", "staging left the cursor item alone")

        H.errors(function() staging.set_stack({name = "not-an-item"}) end, "Unknown item name", "an unknown item is refused")
    end)

    H.test(shape .. " H8-8 a pole's reach comes from its quality, never from a constant", function()
        local world = world_with(shape)
        local pole = prototypes.entity["medium-electric-pole"]
        H.near(pole.get_supply_area_distance("normal"), 3.5, "normal supply area")
        H.near(pole.get_supply_area_distance("legendary"), 3.5 + 5 * 0.5, "legendary supply area follows the quality level")
        H.near(pole.get_max_wire_distance("normal"), 9, "wire reach at normal quality")
        H.equal(pole.quality_affects_supply_area_distance, true, "the prototype says quality matters")
        H.errors(function() return prototypes.entity["transport-belt"].get_max_wire_distance("normal") end,
            "can only be used if this is", "a belt has no wire reach")
    end)

    H.test(shape .. " H8-9 an assertion failure is tagged, a crash is not", function()
        local world = world_with(shape)
        local _, assertion = pcall(function() H.equal(1, 2, "one is two") end)
        H.equal(tostring(assertion):find(H.ASSERT_MARK, 1, true) ~= nil, true, "an assertion carries the marker")
        local _, crash = pcall(function() local missing = nil return missing.method() end)
        H.equal(tostring(crash):find(H.ASSERT_MARK, 1, true), nil, "a nil index carries no marker")
        local _, refused = pcall(function() return prototypes.entity["transport-belt"].logistic_radius end)
        H.equal(tostring(refused):find(H.ASSERT_MARK, 1, true), nil, "a refused mocked member carries no marker")
    end)

    H.test(shape .. " H8-10 run_ticks drives the mod's own on_tick", function()
        local world = world_with(shape)
        local seen = {}
        world.handlers.events[defines.events.on_tick] = function(event) seen[#seen + 1] = event.tick end
        local before = world.tick
        H.run_ticks(world, 3)
        H.equal(#seen, 3, "three ticks ran")
        H.equal(seen[3] - seen[1], 2, "each tick advanced by one")
        H.equal(world.tick, before + 3, "the world's tick moved with them")
    end)
end

H.done("test_harness_api")

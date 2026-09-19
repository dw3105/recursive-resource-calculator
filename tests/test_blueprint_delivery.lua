--A complete blueprint is staged safely, reaches an empty hand, and never costs a held item on failure.
local H = require "tests.harness"

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_item("iron-plate")
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    return world, require "gui.blueprint_delivery"
end

local function result()
    return {
        entities = {{entity_number = 1, name = "assembling-machine-1", position = {x = 0.5, y = 0.5}}},
    }, {
        label = "iron line",
        icons = {{index = 1, signal = {type = "item", name = "iron-plate"}}},
        description = "item/iron-plate=1/s",
    }
end

local function different_result()
    return {
        entities = {{entity_number = 2, name = "assembling-machine-1", position = {x = 1.5, y = 0.5}}},
    }, {
        label = "copper line",
        icons = {{index = 1, signal = {type = "item", name = "iron-plate"}}},
        description = "item/iron-plate=2/s",
    }
end

local function refuse_cursor_setup(player)
    local cursor = player.cursor_stack
    local cursor_metatable = getmetatable(cursor)
    H.equal(cursor_metatable ~= nil, true, "the cursor stack has a testable metatable")
    local previous_index = cursor_metatable.__index
    cursor_metatable.__index = function(object, key)
        if key == "is_blueprint_setup" then
            return function() return false end
        end
        return previous_index(object, key)
    end
    return function()
        cursor_metatable.__index = previous_index
    end
end

local function held_item(player)
    if not player.cursor_stack.valid_for_read then return nil end
    return {name = player.cursor_stack.name, count = player.cursor_stack.count, quality = player.cursor_stack.quality.name}
end

local function last_text(world)
    return world.flying_texts[#world.flying_texts]
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP-18 delivery to an empty cursor gives a set-up blueprint", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        player.clear_cursor() --the staging inventory must never be made by clearing a held item

        local ok, reason = Delivery.deliver(1, blueprint, metadata)

        H.equal(ok, true, "delivery succeeds")
        H.equal(reason, nil, "successful delivery has no reason")
        H.equal(player.cursor_stack.is_blueprint, true, "the cursor has a blueprint")
        H.equal(player.cursor_stack.is_blueprint_setup(), true, "the blueprint is set up")
        H.deep_equal(player.cursor_stack.get_blueprint_entities(), blueprint.entities, "entities reach the cursor")
        H.equal(player.cursor_stack.label, metadata.label, "label reaches the cursor")
        H.deep_equal(player.cursor_stack.preview_icons, metadata.icons, "preview icons reach the cursor")
        H.equal(player.cursor_stack.blueprint_description, metadata.description, "description reaches the cursor")
        H.deep_equal(last_text(world), {"hxrrc.blueprint_delivered"}, "successful delivery is reported")
    end)

    H.test(shape .. " BP-18 a full cursor keeps its item and reports busy", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        world.hold_item(1, "iron-plate", "normal", 7)
        local before = held_item(player)

        local ok, reason = Delivery.deliver(1, blueprint, metadata)

        H.equal(ok, false, "busy delivery is refused")
        H.equal(reason, "blueprint_cursor_busy", "busy reason")
        H.deep_equal(held_item(player), before, "the held item is unchanged")
        H.equal(player.cursor_stack.is_blueprint, false, "the held item is not overwritten")
        H.deep_equal(last_text(world), {"hxrrc.blueprint_cursor_busy"}, "busy cursor is reported")
    end)

    H.test(shape .. " BP-18 a kept result is handed over by retry once the hand is empty", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        world.hold_item(1, "iron-plate", "normal", 2)
        local delivered, reason = Delivery.deliver(1, blueprint, metadata)
        H.equal(delivered, false, "the first delivery is kept")
        H.equal(reason, "blueprint_cursor_busy", "the first delivery is busy")

        world.empty_hand(1)
        local retried, retry_reason = Delivery.retry(1)

        H.equal(retried, true, "retry succeeds")
        H.equal(retry_reason, nil, "successful retry has no reason")
        H.equal(player.cursor_stack.is_blueprint_setup(), true, "retry hands over the set-up result")
        H.deep_equal(player.cursor_stack.get_blueprint_entities(), blueprint.entities, "retry keeps the entities")
        H.equal(player.cursor_stack.label, metadata.label, "retry keeps the label")
    end)

    H.test(shape .. " BP-18 a successful retry refuses a second handover and keeps one blueprint", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        world.hold_item(1, "iron-plate", "normal", 2)

        local delivered, reason = Delivery.deliver(1, blueprint, metadata)
        H.equal(delivered, false, "the full cursor keeps the result")
        H.equal(reason, "blueprint_cursor_busy", "the kept result reports busy")

        world.empty_hand(1)
        local retried, retry_reason = Delivery.retry(1)
        H.equal(retried, true, "the first retry succeeds")
        H.equal(retry_reason, nil, "the successful retry has no reason")
        H.equal(player.cursor_stack.valid_for_read, true, "the cursor has the handed-over blueprint")
        H.equal(player.cursor_stack.is_blueprint, true, "the cursor holds a blueprint")
        H.equal(player.cursor_stack.count, 1, "the cursor holds exactly one blueprint")
        H.deep_equal(player.cursor_stack.get_blueprint_entities(), blueprint.entities, "the first retry keeps the entities")

        local second_retry, second_reason = Delivery.retry(1)
        H.equal(second_retry, false, "the second retry refuses the already handed-over result")
        H.equal(second_reason, "nothing_to_deliver", "the second retry reports nothing to deliver")
        H.equal(player.cursor_stack.valid_for_read, true, "the second retry leaves the cursor occupied")
        H.equal(player.cursor_stack.is_blueprint, true, "the second retry leaves a blueprint in hand")
        H.equal(player.cursor_stack.count, 1, "the second retry leaves exactly one blueprint")
        H.deep_equal(player.cursor_stack.get_blueprint_entities(), blueprint.entities, "the second retry leaves the same entities")
    end)

    H.test(shape .. " BP-18 a successful retry clears pending before a different blueprint arrives", function()
        local world, Delivery = fixture(shape)
        local first_blueprint, first_metadata = result()
        world.hold_item(1, "iron-plate")

        local delivered = Delivery.deliver(1, first_blueprint, first_metadata)
        H.equal(delivered, false, "the first result is kept")
        H.equal(storage[1].blueprint_delivery ~= nil, true, "the first result is pending")

        world.empty_hand(1)
        local retried, retry_reason = Delivery.retry(1)
        H.equal(retried, true, "the kept result is handed over")
        H.equal(retry_reason, nil, "the successful retry has no reason")
        H.equal(storage[1].blueprint_delivery == nil, true, "successful retry clears the kept result")

        world.empty_hand(1)
        local next_blueprint, next_metadata = different_result()
        local next_delivered, next_reason = Delivery.deliver(1, next_blueprint, next_metadata)
        H.equal(next_delivered, true, "a later different blueprint is not blocked by pending state")
        H.equal(next_reason, nil, "the later delivery has no reason")
        H.deep_equal(game.players[1].cursor_stack.get_blueprint_entities(), next_blueprint.entities,
            "the later delivery reaches the cursor")
    end)

    H.test(shape .. " BP-18 a failed delivery leaves the cursor and staging inventory clean", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        local captured
        local create_inventory = game.create_inventory
        game.create_inventory = function(size)
            H.equal(size, 1, "one staging slot is requested")
            local staged = {held = false, is_blueprint = false, setup = false}
            function staged.set_stack(spec)
                staged.held = spec.name == "blueprint"
                staged.is_blueprint = staged.held
            end
            function staged.set_blueprint_entities()
                error("injected staging failure")
            end
            function staged.is_blueprint_setup()
                return staged.setup
            end
            function staged.clear()
                staged.held = false
                staged.is_blueprint = false
                staged.setup = false
                staged.cleared = true
            end
            captured = staged
            return {staged}
        end

        local ok, reason = Delivery.deliver(1, blueprint, metadata)
        game.create_inventory = create_inventory

        H.equal(ok, false, "the staging failure is refused")
        H.equal(reason, "blueprint_delivery_failed", "staging failure reason")
        H.equal(player.cursor_stack.valid_for_read, false, "the empty cursor stays empty")
        H.equal(player.cursor_ghost, nil, "the cursor ghost stays empty")
        H.equal(player.cursor_record, nil, "the cursor record stays empty")
        H.equal(captured.held, false, "the failed staging slot is empty")
        H.equal(captured.cleared, true, "the failed staging slot was cleaned")
        H.equal(storage[1].blueprint_delivery, nil, "a failed result is not kept")
    end)

    H.test(shape .. " BP-18 discard releases a kept result and retry then reports nothing", function()
        local world, Delivery = fixture(shape)
        local blueprint, metadata = result()
        world.hold_item(1, "iron-plate")
        local delivered = Delivery.deliver(1, blueprint, metadata)
        H.equal(delivered, false, "busy delivery is kept")

        H.equal(Delivery.discard(1), true, "discard releases the kept result")
        world.empty_hand(1)
        local retried, reason = Delivery.retry(1)

        H.equal(retried, false, "retry has nothing after discard")
        H.equal(reason, "nothing_to_deliver", "discarded result is gone")
        H.equal(game.players[1].cursor_stack.valid_for_read, false, "discard does not publish anything")
    end)

    H.test(shape .. " BP-18 a blueprint is never delivered twice", function()
        local world, Delivery = fixture(shape)
        local blueprint, metadata = result()
        local ok = Delivery.deliver(1, blueprint, metadata)
        H.equal(ok, true, "the first delivery succeeds")
        local entities = game.players[1].cursor_stack.get_blueprint_entities()

        local retried, reason = Delivery.retry(1)

        H.equal(retried, false, "a completed delivery cannot be retried")
        H.equal(reason, "nothing_to_deliver", "there is no second result")
        H.deep_equal(game.players[1].cursor_stack.get_blueprint_entities(), entities, "the first blueprint remains the only one")
    end)

    H.test(shape .. " BP-18 the staged stack is a set-up blueprint before handover", function()
        local world, Delivery = fixture(shape)
        local blueprint, metadata = result()
        local captured
        local create_inventory = game.create_inventory
        game.create_inventory = function(size)
            local staged = {held = false, is_blueprint = false, setup = false}
            function staged.set_stack(spec)
                staged.held = spec.name == "blueprint"
                staged.is_blueprint = staged.held
            end
            function staged.set_blueprint_entities(entities)
                staged.entities = entities
                staged.setup = true
            end
            function staged.is_blueprint_setup()
                return staged.setup
            end
            function staged.clear()
                captured = {was_blueprint = staged.is_blueprint, was_setup = staged.setup,
                    cursor_was_blueprint = game.players[1].cursor_stack.is_blueprint}
                staged.held = false
                staged.is_blueprint = false
                staged.setup = false
            end
            captured = staged
            return {staged}
        end

        local ok = Delivery.deliver(1, blueprint, metadata)
        game.create_inventory = create_inventory

        H.equal(ok, true, "delivery succeeds")
        H.equal(captured.was_blueprint, true, "the staged stack was a blueprint")
        H.equal(captured.was_setup, true, "the staged stack was set up")
        H.equal(captured.cursor_was_blueprint, true, "handover happened before staging cleanup")
    end)

    H.test(shape .. " BP-18 a cursor setup refusal clears the hand and staging slot and reports failure", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        local captured_inventory
        local create_inventory = game.create_inventory
        game.create_inventory = function(size)
            captured_inventory = create_inventory(size)
            return captured_inventory
        end
        local restore_cursor = refuse_cursor_setup(player)

        local ok, reason = Delivery.deliver(1, blueprint, metadata)

        restore_cursor()
        game.create_inventory = create_inventory

        H.equal(ok, false, "cursor setup refusal is rejected")
        H.equal(reason, "blueprint_delivery_failed", "cursor setup refusal reports failure")
        H.equal(player.cursor_stack.valid_for_read, false, "cursor setup refusal leaves the hand empty")
        H.equal(player.cursor_ghost, nil, "cursor setup refusal leaves no ghost")
        H.equal(player.cursor_record, nil, "cursor setup refusal leaves no record")
        H.equal(captured_inventory ~= nil, true, "staging inventory was created")
        H.equal(captured_inventory[1] ~= nil, true, "staging slot exists")
        H.equal(captured_inventory[1].valid_for_read, false, "cursor setup refusal leaves no staging item")
    end)

    H.test(shape .. " BP-18 a cursor setup refusal drops the result after clearing the hand", function()
        local world, Delivery = fixture(shape)
        local player = game.players[1]
        local blueprint, metadata = result()
        local restore_cursor = refuse_cursor_setup(player)

        local ok, reason = Delivery.deliver(1, blueprint, metadata)

        restore_cursor()

        H.equal(ok, false, "cursor setup refusal is rejected")
        H.equal(reason, "blueprint_delivery_failed", "cursor setup refusal reports failure")
        H.equal(player.cursor_stack.valid_for_read, false, "the failed handover leaves the hand empty")
        H.equal(storage[1].blueprint_delivery == nil, true, "the refused result is dropped rather than kept")

        local retry_ok, retry_reason = Delivery.retry(1)
        H.equal(retry_ok, false, "a dropped result cannot be retried")
        H.equal(retry_reason, "nothing_to_deliver", "retry reports that the dropped result is gone")
    end)
end

H.done("test_blueprint_delivery")

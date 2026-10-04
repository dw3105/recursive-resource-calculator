--Interim publication is tested with a controlled Search state so the result does not depend on search timing.
local H = require "tests.harness"

local function find(root, name)
    if root and root.name == name then return root end
    for _, child in ipairs(root and root.children or {}) do
        local found = find(child, name)
        if found then return found end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " GI interim delivery and offer", function()
        local world = H.new_world(shape)
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()
        local pane, sheet = H.fill_sheet({})
        storage[1].sheet_section = {sheet_pane = pane}
        local sid = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
        local Registry = require "logic.registry"
        Registry.calculation = {get = function() return nil end}
        local Generation = require "logic.bp.generation"
        local Search = require "logic.bp.search"
        local layout1 = {entities = {{name = "assembling-machine-1", position = {x = 0, y = 0}}}}
        local layout2 = {entities = {{name = "assembling-machine-1", position = {x = 1, y = 0}},
            {name = "assembling-machine-1", position = {x = 2, y = 0}}}}
        local stage = 0
        Search.begin = function(input)
            return {input = input, phase = "search", progress = {phase = "search", done_units = 0, total_units = 2}}
        end
        Search.step = function(state, budget)
            budget.ops = 0
            stage = stage + 1
            if stage == 1 then
                state.interim = {sequence = 1, result = layout1, entities = 1}
                state.done, state.ok = false, false
            elseif stage == 2 then
                state.interim = {sequence = 2, result = layout2, entities = 2}
                state.done, state.ok = false, false
            elseif stage < 15 then
                state.done, state.ok = false, false
            else
                state.done, state.ok, state.result = true, true, layout2
            end
            state.progress = {phase = "search", done_units = stage, total_units = 2}
        end
        local id = Generation.start{player_index = 1, sheet_id = sid, prepared_input = {
            snapshot = {sheet_id = sid, state = "current", fingerprint = {input = "interim"}},
            solver_result = {status = "ok", columns = {}}, catalog = {}, settings = {}, options = {},
            revisions = {sheet = 0, config = 0}, surface = "nauvis", force = "player"}, deliver = true}
        --tick 1 prepare, ticks 2-4 prepare finish (capture, persist, search begin; round 56), tick 5 first search step
        H.run_ticks(world, 5)
        local pending = Generation.status(1, id)
        H.equal(pending.state, "pending", "first interim keeps the job pending")
        H.equal(pending.phase, "improving", "first interim marks the improving phase")
        H.equal(game.get_player(1).cursor_stack.valid_for_read, false, "first interim remains an offer")
        H.run_ticks(world, 9)
        local offer = find(pane, "hxrrc_deliver_better_layout")
        H.equal(offer ~= nil, true, "later interim is offered in the panel")
        H.equal(game.get_player(1).cursor_stack.valid_for_read, false, "interim candidates are not auto-delivered")
        event_handlers.on_gui_click[offer.name]({element = offer, player_index = 1})
        H.equal(world.cursors[1].stack.entities[1].position.x, 1,
            "clicking the offer delivers the better layout")
        H.run_ticks(world, 10)
        H.equal(Generation.status(1, id).state, "success", "final result is published")
        H.equal(storage[1].blueprint_delivery, nil, "equal final result does not queue a duplicate delivery")
        H.equal(stage, 15, "the final tick follows the two interim candidates")
    end)
end

H.done("test_generation_interim")

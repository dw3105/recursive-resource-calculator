--Jobs survive ticks, coalesce edits, share a deterministic budget fairly, and cancel without publishing.
local H = require "tests.harness"

local function seam_or_red(Jobs)
    if type(Jobs.register) ~= "function" then
        H.equal(type(Jobs.register), "function", "the job stepper seam exists")
        return false
    end
    return true
end

local function world_with_control(shape, player_indices)
    local world = H.new_world(shape)
    for _, index in ipairs(player_indices or {1}) do world.add_player(index) end
    world.init()
    require "control"
    world.handlers.on_init()
    return world, require "logic.jobs"
end

local function install_fake(Jobs, commits, steps, begins, kind, served)
    Jobs.register(kind or "fake", {
        begin = function(context)
            if begins then begins[#begins + 1] = context.sheet_id end
            return {remaining = context.work or 0, completed = 0, value = context.value or "fixture"}
        end,
        step = function(job, budget)
            local player_index = job.player_index
            steps[player_index] = (steps[player_index] or 0) + 1
            if served then served[#served + 1] = job.sheet_id end
            job.state.remaining = job.state.remaining - 1
            job.state.completed = job.state.completed + 1
            job.progress.done_units = job.progress.done_units + 1
            budget.ops = budget.ops - 1
            if job.state.remaining <= 0 then
                job.done = true
                job.ok = true
                job.result = {completed = job.state.completed, value = job.state.value}
            end
            return job
        end,
        publish = function(job)
            commits[#commits + 1] = {player_index = job.player_index, sheet_id = job.sheet_id, result = job.result}
        end,
    })
end

local function queue_fake(Jobs, player_index, sheet_id, work, value, total)
    storage[player_index].sheet_revision = storage[player_index].sheet_revision or {}
    storage[player_index].sheet_revision[sheet_id] = 1
    return Jobs.request_sheet(player_index, sheet_id, {
        kind = "fake",
        sheet_id = sheet_id,
        work = work,
        value = value,
        revisions = {sheet = 1, config = 0},
        phase = "working",
        progress = {phase = "working", done_units = 0, total_units = total or work},
    })
end

local function drain(world, Jobs, limit)
    for _ = 1, limit or 100 do
        local running = false
        for _, data in pairs(storage) do
            if type(data) == "table" and ((type(data.calc_jobs) == "table" and next(data.calc_jobs) ~= nil) or data.blueprint_job) then
                running = true
            end
        end
        if not running then return end
        H.run_ticks(world, 1)
    end
    H.equal(true, false, "jobs drain within the test bound")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " J1 a job advances only when the registered tick scheduler runs", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        Jobs.OPS_PER_TICK = 1
        queue_fake(Jobs, 1, 1, 3, "ticks")
        H.equal(steps[1], nil, "requesting work does not execute it")
        H.equal(#commits, 0, "requesting work does not publish it")
        H.run_ticks(world, 1)
        H.equal(steps[1], 1, "one tick spends one registered slice")
        H.equal(#commits, 0, "an unfinished slice does not publish")
    end)

    H.test(shape .. " J2 one operation per tick and a huge budget commit exactly the same fixture", function()
        local function finish(budget)
            local world, Jobs = world_with_control(shape)
            if not seam_or_red(Jobs) then return nil end
            local commits, steps = {}, {}
            install_fake(Jobs, commits, steps)
            Jobs.OPS_PER_TICK = budget
            queue_fake(Jobs, 1, 1, 23, "same-result")
            drain(world, Jobs, 100)
            H.equal(#commits, 1, "one result committed")
            return commits[1].result
        end
        local one = finish(1)
        if not one then return end
        local huge = finish(10000)
        H.deep_equal(one, huge, "the budget changes timing, not the committed result")
    end)

    H.test(shape .. " J3 a second request replaces one sheet job instead of stacking two", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        queue_fake(Jobs, 1, 1, 8, "old")
        queue_fake(Jobs, 1, 1, 2, "new")
        H.equal(next(storage[1].calc_jobs, nil) ~= nil, true, "one replacement remains queued")
        drain(world, Jobs, 20)
        H.equal(#commits, 1, "the replaced job never publishes")
        H.equal(commits[1].result.value, "new", "the latest request wins")
    end)

    H.test(shape .. " J4 cancellation drops only its own late publish and permits a fresh same-revision job", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        Jobs.OPS_PER_TICK = 1
        queue_fake(Jobs, 1, 1, 20, "cancelled")
        H.run_ticks(world, 1)
        H.equal(steps[1], 1, "the job started before the handler cancelled it")
        local late = storage[1].calc_jobs[1]
        late.done, late.ok, late.result = true, true, {value = "late-canceled-publish"}
        Jobs.cancel(1, 1)
        --Model an already-dispatched completion reaching the publish gate after Cancel.
        storage[1].calc_jobs[1] = late
        H.run_ticks(world, 1)
        H.equal(#commits, 0, "tombstone drops the canceled job's own late publish")
        local fresh = queue_fake(Jobs, 1, 1, 1, "fresh-after-cancel")
        H.equal(fresh ~= nil, true, "same-revision user request is accepted")
        H.run_ticks(world, 1)
        H.equal(#commits, 1, "only the fresh job publishes")
        H.equal(commits[1].result.value, "fresh-after-cancel", "late canceled job cannot replace fresh output")
        H.equal(next(storage[1].calc_jobs), nil, "fresh job completes")
    end)

    H.test(shape .. " J5 two players share one budget and neither is starved", function()
        local world, Jobs = world_with_control(shape, {1, 2})
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        Jobs.OPS_PER_TICK = 1
        queue_fake(Jobs, 1, 1, 20, "p1")
        queue_fake(Jobs, 2, 1, 20, "p2")
        H.run_ticks(world, 1)
        H.equal((steps[1] or 0) + (steps[2] or 0), 1, "one operation is shared by all players")
        H.run_ticks(world, 1)
        H.equal(steps[1], 1, "player one made progress")
        H.equal(steps[2], 1, "player two made progress on the next tick")
        H.run_ticks(world, 6)
        H.equal(steps[1] > 0 and steps[2] > 0, true, "the stored cursor keeps both players progressing")
    end)

    H.test(shape .. " J6 forgetting a player drops every job and a disconnected player cannot hold work", function()
        local world, Jobs = world_with_control(shape, {1, 2})
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        queue_fake(Jobs, 2, 1, 10, "gone")
        Jobs.forget_player(2)
        H.equal(storage[2].calc_jobs, nil, "forget removes calculations")
        game.players[2] = nil
        queue_fake(Jobs, 1, 1, 1, "stays")
        storage[2] = {calc_jobs = {[1] = {kind = "fake", player_index = 2, sheet_id = 1}}}
        H.run_ticks(world, 1)
        H.equal(storage[2].calc_jobs, nil, "on_tick prunes a disconnected player's queue")
    end)

    H.test(shape .. " J7 configuration change invalidates jobs and records the reason on their sheets", function()
        local world, Jobs = world_with_control(shape, {1, 2})
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        queue_fake(Jobs, 1, 11, 4, "one")
        queue_fake(Jobs, 2, 22, 4, "two")
        local before = storage[1].config_revision
        Jobs.invalidate_all("configuration_changed")
        H.equal(storage[1].calc_jobs, nil, "player one queue invalidated")
        H.equal(storage[2].calc_jobs, nil, "player two queue invalidated")
        H.equal(storage[1].job_invalidations[11], "configuration_changed", "player one sheet records the reason")
        H.equal(storage[2].job_invalidations[22], "configuration_changed", "player two sheet records the reason")
        H.equal(storage[1].config_revision, before + 1, "configuration revision advances")
        H.equal(#commits, 0, "invalidated work publishes nothing")
    end)

    H.test(shape .. " J8 job storage contains only plain serializable data", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        storage[1].sheet_revision = {[1] = 1}
        Jobs.request_sheet(1, 1, {kind = "fake", work = 5, value = "plain", callback = function() end, lua_object = game.players[1],
            revisions = {sheet = 1, config = 0}, progress = {phase = "working", done_units = 0, total_units = 5}})

        local function walk(value, path, seen)
            local value_type = type(value)
            H.equal(value_type == "function" or value_type == "userdata", false, path .. " is not executable or a LuaObject")
            if value_type ~= "table" then return end
            H.equal(getmetatable(value), nil, path .. " has no metatable")
            seen = seen or {}
            if seen[value] then return end
            seen[value] = true
            for key, child in pairs(value) do walk(key, path .. ".<key>", seen); walk(child, path .. "." .. tostring(key), seen) end
        end
        walk(storage[1].calc_jobs, "calc_jobs")
        H.run_ticks(world, 1)
        walk(storage[1].calc_jobs, "calc_jobs after a tick")
    end)

    H.test(shape .. " J9 progress stays below one until completion and then disappears", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local commits, steps = {}, {}
        install_fake(Jobs, commits, steps)
        Jobs.OPS_PER_TICK = 1
        queue_fake(Jobs, 1, 1, 5, "progress")
        local phase, fraction = Jobs.progress_of(1, 1)
        H.equal(phase, "working", "queued phase is visible")
        H.equal(fraction < 1, true, "queued progress is below one")
        H.run_ticks(world, 1)
        phase, fraction = Jobs.progress_of(1, 1)
        H.equal(phase, "working", "running phase is visible")
        H.equal(fraction < 1, true, "running progress is below one")
        drain(world, Jobs, 10)
        H.equal(Jobs.progress_of(1, 1), nil, "finished work no longer reports as running")
    end)

    H.test(shape .. " J10 request_all_sheets queues the visible sheet first", function()
        local world, Jobs = world_with_control(shape)
        if not seam_or_red(Jobs) then return end
        local Sheet = require "gui.sheet"
        local pane = storage[1].sheet_section.sheet_pane
        Sheet.new(pane)
        pane.selected_tab_index = 2
        local commits, steps, begins, served = {}, {}, {}, {}
        install_fake(Jobs, commits, steps, begins, "calculation", served)
        H.equal(Jobs.request_all_sheets(1), 2, "both sheets are queued")
        H.equal(begins[1], pane.tabs[2].content.tags.hxrrc_sheet_id, "visible sheet is begun first")
        H.equal(begins[2], pane.tabs[1].content.tags.hxrrc_sheet_id, "other sheet follows in tab order")
        Jobs.OPS_PER_TICK = 1
        H.run_ticks(world, 1)
        H.equal(served[1], pane.tabs[2].content.tags.hxrrc_sheet_id, "visible sheet is serviced first")
    end)
end

H.done("test_jobs")

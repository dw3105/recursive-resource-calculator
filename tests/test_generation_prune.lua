-- GP1-GP5 prove finished generation pruning; each assertion is expected to fail on the base code.
local H = require "tests.harness"

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane, a = H.fill_sheet({}, 1)
    local _, b = H.fill_sheet({}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheets = {[a.tags.hxrrc_sheet_id] = a, [b.tags.hxrrc_sheet_id] = b}
    local Registry = require "logic.registry"
    local Snapshot = require "logic.snapshot"
    Registry.calculation = {get = function(player, sid)
        local sheet = sheets[sid]
        local snap = Snapshot.of_sheet(sheet)
        return {schema_version = 1, player_index = player, sheet_id = sid, sheet_revision = 0,
            config_revision = 0, input_fingerprint = snap.fingerprint.input,
            result = {schema_version = 1, status = "ok", columns = {}}}
    end}
    local Search = require "logic.bp.search"
    Search.begin = function(input) return {phase = "search", input = input, progress = {done_units = 0, total_units = 1}} end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, false, "failed"
        state.errors, state.progress = {{code = "BP_R_PORT_BLOCKED"}}, {done_units = 1, total_units = 1}
    end
    return world, require "logic.bp.generation", a.tags.hxrrc_sheet_id, b.tags.hxrrc_sheet_id
end

local function start(world, G, sid)
    return assert(G.start{player_index = 1, sheet_id = sid, deliver = false})
end
local function finish(world, G, id)
    for _ = 1, 100 do
        local s = G.status(1, id)
        if s and s.state ~= "pending" then return end
        H.run_ticks(world, 1)
    end
    H.equal(false, true, "generation finishes within the small fixture")
end

do
    local world, G, a, b = fixture(H.shapes()[1])
    local newest
    for _ = 1, 10 do newest = start(world, G, a); finish(world, G, newest) end
    H.test("GP1", function()
        H.equal((function() local n=0; for _ in pairs(storage.blueprint_generations.jobs) do n=n+1 end; return n end)(), 1)
        H.equal(G.lookup(1, a).job_id, newest)
        H.equal(G.capture(1, newest) ~= nil, true)
    end)
    H.test("GP2", function()
        for _, sid in ipairs({a,b}) do for _=1,3 do local id=start(world,G,sid); finish(world,G,id) end end
        local n=0; for _ in pairs(storage.blueprint_generations.jobs) do n=n+1 end
        H.equal(n, 2)
    end)
    H.test("GP3", function()
        local pending = start(world,G,a)
        storage.blueprint_generations.jobs[pending-1] = {job_id=pending-1, player_index=1, sheet_id=a, state="failure"}
        G.prune_all()
        H.equal(storage.blueprint_generations.jobs[pending] ~= nil, true)
    end)
    H.test("GP4", function()
        local jobs={}; for id=1,21 do jobs[id]={job_id=id,player_index=1,sheet_id="sheet"..((id-1)%3),state="failure"} end
        storage.blueprint_generations.jobs=jobs
        G.prune_all()
        local n=0; for _ in pairs(jobs) do n=n+1 end
        H.equal(n,3)
        for id=1,18 do H.equal(G.status(1,id), nil, "pruned handle is inaccessible") end
    end)
    H.test("GP5", function()
        storage.blueprint_generations.jobs={}
        local old=start(world,G,a)
        local new=start(world,G,a)
        finish(world,G,new)
        H.equal(storage.blueprint_generations.jobs[old], nil)
        H.equal(storage.blueprint_generations.jobs[new] ~= nil, true)
    end)
end

H.done("test_generation_prune")

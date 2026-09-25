--Red on round-37-222b-base: the frozen route calls leave a dead shared trunk and a chain of splitters.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function replay(path)
    H.new_world(H.shapes()[1])
    local f = assert(io.open(path)); local input = helpers.json_to_table(f:read("*a")); f:close()
    local state = Route.begin(input)
    while not state.done do Route.step(state, {ops=100000}) end
    if state.ok then
        state = Route.tidy_begin(state)
        while not state.done do Route.tidy_step(state, {ops=100000}) end
    end
    return state
end

local function edges(work, key, flow)
    local s = work.segments_by_cell[key]
    if not s or not (s.flow_id == flow or (s.flow_ids and s.flow_ids[flow])) then return {} end
    local out = {}
    local function add(k) if k then out[#out+1]=k end end
    if s.underground then
        if key == s.underground_entry_key then add(s.underground_exit_key) end
        if key == s.underground_exit_key then
            local dx,dy=Grid.dir_vector(s.direction); if dx then add(tostring(s.underground_exit_x+dx)..":"..tostring(s.underground_exit_y+dy)) end
        end
    elseif s.splitter then
        local dx,dy=Grid.dir_vector(s.splitter_direction)
        if dx then
            add(tostring(s.splitter_anchor_x+dx)..":"..tostring(s.splitter_anchor_y+dy))
            local x,y=string.match(s.splitter_second_key or "", "^([^:]+):([^:]+)$")
            if x then add(tostring(tonumber(x)+dx)..":"..tostring(tonumber(y)+dy)) end
        end
        add(s.splitter_second_key)
    else
        local x,y=string.match(key,"^([^:]+):([^:]+)$"); local dx,dy=Grid.dir_vector(s.direction)
        if dx then add(tostring(tonumber(x)+dx)..":"..tostring(tonumber(y)+dy)) end
    end
    return out
end

local function path_segments(work, start, target, flow)
    local seen, q, head={[start]=true},{start},1
    local parent={}
    while q[head] do
        local k=q[head]; head=head+1
        if k==target then break end
        for _,n in ipairs(edges(work,k,flow)) do if not seen[n] then seen[n]=true;parent[n]=k;q[#q+1]=n end end
    end
    local live={}; local key=target
    while key do
        local s=work.segments_by_cell[key]; if s then live[s.segment_id]=true end
        key=parent[key]
    end
    return live
end

H.test("TJ1 tidy removes dead belts and chained splitters from frozen route calls", function()
    for _,path in ipairs({"tests/fixtures/route_ins10s_bulk_call4.json", "tests/fixtures/route_ins10s_call1.json"}) do
        local state=replay(path); H.equal(state.ok,true,"route and tidy complete: "..path)
        local work=state.work
        local live={}
        for _,binding in ipairs(work.bindings) do
            local source=work.endpoint_by_id[binding.source_port_id]
            local sink=work.endpoint_by_id[binding.sink_port_id]
            for id in pairs(path_segments(work,tostring(source.x)..":"..tostring(source.y),tostring(sink.x)..":"..tostring(sink.y),binding.flow_id)) do live[id]=true end
        end
        for _,s in ipairs(work.segments) do
            if s.flow_id and s.kind == "belt" then
                H.equal(live[s.segment_id] or false,true,"every flow belt lies on a live path: "..tostring(s.segment_id))
            end
        end
        for _,s in ipairs(work.segments) do if s.splitter then
            local dx,dy=Grid.dir_vector(s.splitter_direction)
            local sx,sy=string.match(s.splitter_second_key or "", "^([^:]+):([^:]+)$")
            for _,k in ipairs({tostring(s.splitter_anchor_x+dx)..":"..tostring(s.splitter_anchor_y+dy),
                tostring(tonumber(sx)+dx)..":"..tostring(tonumber(sy)+dy)}) do
                local next_segment=work.segments_by_cell[k]
                H.equal(next_segment and next_segment.splitter or false,false,"splitter output does not feed another splitter")
            end
        end end
    end
end)

H.done("test_route_tidy_junk")

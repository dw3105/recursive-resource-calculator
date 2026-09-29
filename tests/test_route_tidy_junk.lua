--Red before the route tidy fix: call 1 overlaps the replacement belts with splitter tiles, and bulk call 4
--retains a splitter with an unfed input after its feed belts are swept.
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

H.test("TJ1 tidy removes dead belts and chained splitters from frozen route calls", function()
    for _,path in ipairs({"tests/fixtures/route_ins10s_bulk_call4.json", "tests/fixtures/route_ins10s_call1.json"}) do
        local state=replay(path); H.equal(state.ok,true,"route and tidy complete: "..path)
        local work=state.work
        local sources={}
        for _,binding in ipairs(work.bindings) do
            local source=work.endpoint_by_id[binding.source_port_id]
            if source then sources[tostring(source.x)..":"..tostring(source.y)]=true end
        end
        for key,s in pairs(work.segments_by_cell) do
            if s.kind == "belt" and not s.underground and not s.splitter then
                local fed=false
                for other_key,other in pairs(work.segments_by_cell) do
                    if other~=s and (other.flow_id==s.flow_id or (other.flow_ids and other.flow_ids[s.flow_id])) then
                        for _,out in ipairs(edges(work,other_key,s.flow_id)) do if out==key then fed=true end end
                    end
                end
                H.equal(fed or sources[key] or s.fixed or false,true,"every belt has a source or transport feed: "..tostring(s.segment_id))
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

H.test("TJ2 call 1 has no transport overlaps or splitter chains", function()
    local work=replay("tests/fixtures/route_ins10s_call1.json").work
    local occupied={}
    for _,entity in ipairs(work.entities) do
        local segment=work.entity_by_segment[entity.segment_id]
        local x,y=entity.position.x,entity.position.y
        local keys={tostring(x)..":"..tostring(y)}
        if segment and segment.splitter then keys={segment.splitter_anchor_key,segment.splitter_second_key} end
        for _,key in ipairs(keys) do
            H.equal(occupied[key],nil,"transport tile is unique: "..tostring(key))
            occupied[key]=entity.id
        end
    end
    for _,s in ipairs(work.segments) do if s.splitter then
        local dx,dy=Grid.dir_vector(s.splitter_direction)
        local sx,sy=string.match(s.splitter_second_key,"^([^:]+):([^:]+)$")
        for _,key in ipairs({tostring(s.splitter_anchor_x+dx)..":"..tostring(s.splitter_anchor_y+dy),
            tostring(tonumber(sx)+dx)..":"..tostring(tonumber(sy)+dy)}) do
            H.equal(work.segments_by_cell[key] and work.segments_by_cell[key].splitter or false,false,"no splitter chain")
        end
    end end
end)

--TJ3: the dead trunk's splitter at (24,8) had NO live input after the sweep. A branch splitter is normally fed on
--one input only, and a hand may drop straight onto a splitter tile, so the rule is: every splitter has at least one
--fed input or a hand drop on one of its own tiles.
H.test("TJ3 bulk call 4 every splitter is fed", function()
    local work=replay("tests/fixtures/route_ins10s_bulk_call4.json").work
    local drops={}
    for _,b in ipairs(work.bindings or {}) do
        local src=work.endpoint_by_id and work.endpoint_by_id[b.source_port_id]
        if src then drops[tostring(src.x)..":"..tostring(src.y)]=true end
    end
    for _,s in ipairs(work.segments) do if s.splitter then
        local dx,dy=Grid.dir_vector(s.splitter_direction)
        local sx,sy=string.match(s.splitter_second_key,"^([^:]+):([^:]+)$"); sx,sy=tonumber(sx),tonumber(sy)
        local own={tostring(s.splitter_anchor_x)..":"..tostring(s.splitter_anchor_y), s.splitter_second_key}
        local live=drops[own[1]] or drops[own[2]] or false
        for _,input in ipairs({{s.splitter_anchor_x-dx,s.splitter_anchor_y-dy},{sx-dx,sy-dy}}) do
            local key=tostring(input[1])..":"..tostring(input[2])
            --A hand dropping onto the belt behind an input feeds it as surely as one dropping onto the splitter
            --(iron-plate source (32,12) -> splitter (32,13) south, kept since 9714d0f, 2026-09-29).
            if drops[key] and work.segments_by_cell[key] and work.segments_by_cell[key].direction==s.splitter_direction then live=true end
            for other_key,other in pairs(work.segments_by_cell) do
                if other~=s then for _,out in ipairs(edges(work,other_key,s.flow_id)) do if out==key then live=true end end end
            end
        end
        H.equal(live,true,"splitter "..own[1].." has a live input")
    end end
end)

H.done("test_route_tidy_junk")

--Draw the Flow graph of one candidate before pack (round 51, drawn pack; CONTEXT.md: Flow graph, Layer, Source,
--Output, Crossing). Nodes are Blocks, one Source per external input flow and one Output per external output flow;
--Layers run away from the input edge. The drawn pack (RRC_PACK=sugiyama) aims each Block at its Layer and rank.
--
--Contract (frozen round 51 STEP 0; lane 285 fills the body, never the signatures):
--  FlowDraw.begin{nodes = {{id, w, h, ports = {{port_id, role = "in"|"out", attach_dx, attach_dy, kind}}}},
--                 links = candidate links (search.lua candidate_links; edge links carry flow_id and ext = "in"|"out"),
--                 input_edge, output_edge, restarts = 30, sweeps = 8, seed = 1} -> state
--  FlowDraw.step(state, budget) -> true when done; spends budget.ops; the same result for any slicing
--  state.result = {layer_of = {[id] = L}, rank_of = {[id] = r}, layers = {{id, ...}, ...},
--                  sources = {{flow_id, rank}}, outputs = {{flow_id, producer, layer, rank}},
--                  dummies = {{link, layer, rank}}, crossings = N, turn_of = {[id] = 0|4|8|12}}
--
--STEP 0 skeleton: longest-path Layers, ranks in input order, no dummies, no crossing count, every Turn NORTH.
local FlowDraw = {}

local function node_of(end_)
    return end_ and end_.block_id
end

function FlowDraw.begin(input)
    return {input = input, done = false}
end

local function skeleton(input)
    local ids, known = {}, {}
    for _, node in ipairs(input.nodes or {}) do
        ids[#ids + 1] = node.id
        known[node.id] = true
    end
    local layer_of = {}
    for _, id in ipairs(ids) do layer_of[id] = 1 end
    for _ = 1, #ids do
        for _, link in ipairs(input.links or {}) do
            local a, b = node_of(link.a), node_of(link.b)
            if a and b and known[a] and known[b] and layer_of[b] < layer_of[a] + 1 then layer_of[b] = layer_of[a] + 1 end
        end
    end
    local layers, rank_of, turn_of = {}, {}, {}
    for _, id in ipairs(ids) do
        local layer = layers[layer_of[id]] or {}
        layers[layer_of[id]] = layer
        layer[#layer + 1] = id
        rank_of[id] = #layer
        turn_of[id] = 0
    end
    local sources, outputs, seen = {}, {}, {}
    for _, link in ipairs(input.links or {}) do
        local flow = link.flow_id
        if link.ext == "in" and flow and not seen["in|" .. flow] then
            seen["in|" .. flow] = true
            sources[#sources + 1] = {flow_id = flow, rank = #sources + 1}
        elseif link.ext == "out" and flow and not seen["out|" .. flow] then
            seen["out|" .. flow] = true
            local producer = node_of(link.a)
            local layer = (layer_of[producer] or 0) + 1
            outputs[#outputs + 1] = {flow_id = flow, producer = producer, layer = layer, rank = #outputs + 1}
        end
    end
    return {layer_of = layer_of, rank_of = rank_of, layers = layers, sources = sources, outputs = outputs,
        dummies = {}, crossings = 0, turn_of = turn_of}
end

function FlowDraw.step(state, budget)
    if state.done then return true end
    state.result = skeleton(state.input)
    state.done = true
    if budget and budget.ops then budget.ops = math.max(0, budget.ops - 1) end
    return true
end

return FlowDraw

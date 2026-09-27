return function(src)
  local n
  src, n = src:gsub("local function begin_search%(work, demand, amount, order_index%)\n", function() return [[
local function begin_search(work, demand, amount, order_index)
    if demand.kind ~= "pipe" and demand.sink and demand.sink.feed_curve and not demand.curve_allowed
        and demand.sink.travel_dir ~= nil then
        local dx, dy = Grid.dir_vector(demand.sink.travel_dir)
        if dx and static_owner(work, demand.sink.x - dx, demand.sink.y - dy) ~= nil then demand.curve_allowed = true end
    end
    if demand.kind ~= "pipe" and demand.source and not demand.source.perimeter and not demand.source.row_port
        and not demand.free_heading and demand.source.travel_dir ~= nil then
        local dx, dy = Grid.dir_vector(demand.source.travel_dir)
        if dx and static_owner(work, demand.source.x + dx, demand.source.y + dy) ~= nil then demand.free_heading = true end
    end
]] end, 1)
  assert(n == 1, "f79")
  return src
end

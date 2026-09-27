return function(src)
  local n
  src, n = src:gsub("    local segment = work.segments_by_cell%[coordinate_key%(x, y%)%]\n    if segment then\n        %-%-An underground input consumes", function() return [[
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    if segment and demand.kind == "pipe" and segment.kind == "pipe" and segment.underground and move_direction ~= nil
        and segment.underground_entry_x ~= nil then
        local mdx, mdy = Grid.dir_vector(move_direction)
        local sdx, sdy = Grid.dir_vector(segment.direction)
        if mdx ~= nil and sdx ~= nil then
            local fx, fy = x - mdx, y - mdy
            local here = coordinate_key(x, y)
            local ok
            if here == segment.underground_entry_key then
                ok = (fx == segment.underground_entry_x - sdx and fy == segment.underground_entry_y - sdy)
                    or coordinate_key(fx, fy) == segment.underground_exit_key
            else
                ok = (fx == segment.underground_exit_x + sdx and fy == segment.underground_exit_y + sdy)
                    or coordinate_key(fx, fy) == segment.underground_entry_key
            end
            if not ok then search.saw_blocked = true; return false end
        end
    end
    if segment then
        --An underground input consumes]] end, 1)
  assert(n == 1, "f4")
  return src
end

return function(src)
  local n
  src, n = src:gsub("    local segment = work.segments_by_cell%[coordinate_key%(x, y%)%]\n    %-%-On the frozen gray %+ magenta sheet", function() return [[
    if demand.kind == "pipe" and move_direction ~= nil then
        local mdx, mdy = Grid.dir_vector(move_direction)
        local from = mdx and work.segments_by_cell[coordinate_key(x - mdx, y - mdy)]
        if from and from.kind == "pipe" and from.underground and from.underground_entry_x ~= nil then
            local sdx, sdy = Grid.dir_vector(from.direction)
            local from_key = coordinate_key(x - mdx, y - mdy)
            local here = coordinate_key(x, y)
            local ok = true
            if sdx ~= nil then
                if from_key == from.underground_entry_key then
                    ok = here == coordinate_key(from.underground_entry_x - sdx, from.underground_entry_y - sdy)
                        or here == from.underground_exit_key
                elseif from_key == from.underground_exit_key then
                    ok = here == coordinate_key(from.underground_exit_x + sdx, from.underground_exit_y + sdy)
                        or here == from.underground_entry_key
                end
            end
            if not ok then search.saw_blocked = true; return false end
        end
    end
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    --On the frozen gray + magenta sheet]] end, 1)
  assert(n == 1, "f4b")
  return src
end

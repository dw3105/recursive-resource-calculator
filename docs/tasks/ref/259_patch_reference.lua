return function(src)
  local old = "        --An underground input consumes its feed into the pair; stepping onto it from the side cannot continue.\n"
  local new = [[        if demand.kind ~= "pipe" and segment.kind == "belt" and segment.underground
            and segment.underground_exit_key == coordinate_key(x, y) and move_direction == segment.direction then
            search.saw_blocked = true
            return false
        end
]] .. old
  local s, e = src:find(old, 1, true); assert(s, "A")
  return src:sub(1, s - 1) .. new .. src:sub(e + 1)
end

return function(src)
  local n
  src, n = src:gsub('elseif not placed and reason == "route%-discontinuous" and %(not demand.no_chain_dive or not demand.no_self_cross%) then', function() return [[elseif not placed and (reason == "route-discontinuous" or (reason ~= "capacity" and not demand.no_self_cross and (function()
                            local seen = {}
                            for _, cell in ipairs(outcome) do
                                local k = coordinate_key(cell.x, cell.y)
                                if seen[k] then return true end
                                seen[k] = true
                            end
                            return false
                        end)())) and (not demand.no_chain_dive or not demand.no_self_cross) then]] end, 1)
  assert(n == 1, "f5b")
  return src
end

-- In-memory trial R1 (result may change): a failed flood is not replayed in the 3 other direction orders.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = "and search.order_index < #DIRECTION_ORDERS then"
    local a, b = src:find(old, 1, true)
    assert(a, "noreplay anchor")
    io.stderr:write("PATCH noreplay live\n")
    return src:sub(1, a - 1) .. "and search.order_index < 1 then" .. src:sub(b + 1)
end

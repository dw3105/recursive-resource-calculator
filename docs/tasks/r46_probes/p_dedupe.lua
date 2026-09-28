-- In-memory trial T1: the retry list holds one entry per REFUSED OPTION, so one binding is retried N times.
-- A repeat is skipped only while no re-route was kept since the same binding's last retry (same world, same answer).
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local old = "            if demand and find_binding(work, wanted) then\n                --Option 1 keeps both hands"
    local a, b = src:find(old, 1, true)
    assert(a, "dedupe anchor not found")
    local new = "            local repeat_same_world = false\n" ..
        "            if st.retrying then\n" ..
        "                st.retry_seen = st.retry_seen or {}\n" ..
        "                local k = tostring(wanted[1]) .. '|' .. tostring(wanted[2]) .. '|' .. tostring(wanted[3])\n" ..
        "                repeat_same_world = st.retry_seen[k] == st.improved\n" ..
        "                st.retry_seen[k] = st.improved\n" ..
        "                if repeat_same_world and _G.__P then _G.__P.count('retry_skipped') end\n" ..
        "            end\n" ..
        "            if demand and not repeat_same_world and find_binding(work, wanted) then\n                --Option 1 keeps both hands"
    io.stderr:write("PATCH dedupe live\n")
    return src:sub(1, a - 1) .. new .. src:sub(b + 1)
end

-- In-memory trial T2: a trial whose lift cannot start (same answer for every option of one binding, world is
-- restored between options) is skipped BEFORE the whole-state copy. Multi trials: only when the first lift fails.
return function(name, src)
    if name ~= "logic.bp.route" then return src end
    local head = "\nlocal function lift_binding(work, binding, allow_fixed)\n"
    local a, b = src:find(head, 1, true)
    assert(a, "liftskip anchor 1")
    local stop = "    if count < 2 then return nil end\n"
    local c, d = src:find(stop, b, true)
    assert(c, "liftskip anchor 2")
    local body = src:sub(b + 1, d)
    local check = "\ndo\n    local function lift_check(work, binding, allow_fixed)\n" .. body .. "    return count\n    end\n" ..
        "    _G.__cannot_start = function(work, st)\n" ..
        "        local option = st.options[st.option_index] or nil\n" ..
        "        local spec = option and option.multi_bindings and option.multi_bindings[1] or st.wanted\n" ..
        "        local binding\n" ..
        "        for _, candidate in ipairs(work.bindings or {}) do\n" ..
        "            if candidate.source_port_id == spec[1] and candidate.sink_port_id == spec[2]\n" ..
        "                and candidate.rate_per_second == spec[3] then binding = candidate; break end\n" ..
        "        end\n" ..
        "        if not binding then return true end\n" ..
        "        local key = tostring(spec[1]) .. '|' .. tostring(spec[2]) .. '|' .. tostring(spec[3])\n" ..
        "        st.lift_memo = st.lift_memo or {}\n" ..
        "        if st.lift_memo.index ~= st.index or st.lift_memo.improved ~= st.improved or st.lift_memo.order ~= st.order then\n" ..
        "            st.lift_memo = {index = st.index, improved = st.improved, order = st.order, answers = {}}\n" ..
        "        end\n" ..
        "        local answer = st.lift_memo.answers[key]\n" ..
        "        if answer == nil then answer = lift_check(work, binding) and true or false; st.lift_memo.answers[key] = answer end\n" ..
        "        if not answer and _G.__P then _G.__P.count('trial_skipped_cannot_start') end\n" ..
        "        return not answer\n" ..
        "    end\nend\n"
    src = src:sub(1, a - 1) .. check .. src:sub(a)
    local old = '        elseif st.stage == "trial_start" or st.stage == "commit_start" then\n'
    local e, f = src:find(old, 1, true)
    assert(e, "liftskip anchor 3")
    local new = '        elseif st.stage == "trial_start" and _G.__cannot_start(work, st) then\n' ..
        '            st.option_index = st.option_index + 1\n' ..
        '            if st.option_index <= #st.options then st.stage = "trial_start"\n' ..
        '            elseif st.best then st.stage = "commit_start"\n' ..
        '            else st.stage = "next" end\n' ..
        '            used = used + 1\n' .. old
    io.stderr:write("PATCH liftskip live\n")
    return src:sub(1, e - 1) .. new .. src:sub(f + 1)
end

local M = {}
function M.classify(ok, code, mixed, starved, bleed, dead, flip)
    if not ok and code == "BP_FAIL_FLIP_FORBIDDEN" and flip == 1 then return "forbidden" end
    if not ok and code == "BP_FAIL_FLUID_PORT_BLOCKED" then return "forbidden" end
    if not ok or code ~= "-" or mixed ~= 0 or starved ~= 0 or bleed ~= 0 or dead ~= 0 then return "FAIL" end
    return "valid"
end
function M.format(r)
    return string.format("CENSUS ver=%s case=%s turn=%d flip=%d result=%s code=%s lanes=mixed=%d,starved=%d,bleed=%d,dead=%d sha=%s",
        r.ver,r.case,r.turn,r.flip,r.result,r.code,r.mixed,r.starved,r.bleed,r.dead,r.sha)
end
function M.parse(s)
    local ver, case, turn, flip, result, code, mixed, starved, bleed, dead, sha = s:match(
        "^CENSUS ver=([^ ]+) case=([^ ]+) turn=(%d+) flip=(%d+) result=([^ ]+) code=([^ ]+) lanes=mixed=(%d+),starved=(%d+),bleed=(%d+),dead=(%d+) sha=([^ ]+)$")
    if not ver then return nil end
    return {ver=ver,case=case,turn=tonumber(turn),flip=tonumber(flip),result=result,code=code,
        mixed=tonumber(mixed),starved=tonumber(starved),bleed=tonumber(bleed),dead=tonumber(dead),sha=sha}
end
return M

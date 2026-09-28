-- Chain: PATCHES=a.lua,b.lua (paths), applied in order.
local fns = {}
for path in (os.getenv("PATCHES") or ""):gmatch("[^,]+") do fns[#fns + 1] = assert(loadfile(path))() end
return function(name, src)
    for _, fn in ipairs(fns) do src = assert(fn(name, src)) end
    return src
end

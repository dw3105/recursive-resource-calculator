-- PATCHES=a.lua,b.lua chains patches
local list = {}
for p in (os.getenv("PATCHES") or ""):gmatch("[^,]+") do list[#list+1] = assert(loadfile(p))() end
return function(name, src) for _, f in ipairs(list) do src = f(name, src) end return src end

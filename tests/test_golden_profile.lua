-- GP regression: every assertion here fails on round-45-base because golden profiling/reporting do not exist there.
local function run(command)
    local p=io.popen(command..' 2>&1'); local s=p:read('*a'); local ok,why,code=p:close(); return s,ok,why,code
end
local function check(id, condition, detail)
    io.write(id..' '..(condition and 'ok' or 'FAIL')..(detail and (' '..detail) or '')..'\n')
    if not condition then failures=failures+1 end
end
failures=0
local tmp=os.tmpname(); os.remove(tmp); assert(os.execute('mkdir -p '..tmp))
local out=tmp..'/one.json'; local log,ok=run('lua5.2 tools/golden_profile.lua player-red-science-1s '..out)
local fields='case git_head ops_per_step ok error_codes entities canonical_sha256 ticks cpu_total ops_used capped worst_tick phases grids stages route route_demands_top calls rejections search'
local py="python3 -c \"import json,sys;d=json.load(open(sys.argv[1])); req='"..fields.."'.split(); assert all(k in d for k in req); assert d['ok'] is True; assert d['ticks']>0; assert 'Route.step' in d['calls']; assert abs(sum(p['cpu'] for p in d['phases'])-d['cpu_total']) <= d['cpu_total']*.1\" "..out
local _,valid=run(py); check('GP1',ok and valid and log=='' ,'profile valid')
local cap=tmp..'/cap.json'; local _,capok=run('lua5.2 tools/golden_profile.lua player-red-science-1s '..cap..' --cap 1')
local _,capvalid=run("python3 -c \"import json,sys;assert json.load(open(sys.argv[1]))['capped'] is True\" "..cap)
check('GP2',capok and capvalid,'capped JSON')
local two=tmp..'/two.json'; local f=assert(io.open(two,'wb')); f:write('{"case":"second","cpu_total":1,"phases":[],"grids":[],"stages":{},"calls":{},"route_demands_top":[],"rejections":{}}'); f:close()
local _,reportok=run('python3 tools/golden_report.py '..tmp..' '..tmp..'/out.html')
local html=''; local rf=io.open(tmp..'/out.html','rb'); if rf then html=rf:read('*a');rf:close() end
check('GP3',reportok and html:find('player%-red%-science%-1s') and html:find('second') and html:find('prefers%-color%-scheme'),'HTML report')
os.execute('rm -rf '..tmp)
io.write(string.format('test_golden_profile: %d failed\n',failures)); if failures>0 then os.exit(1) end

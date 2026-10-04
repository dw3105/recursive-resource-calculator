-- Must fail on base code: gate56 runner and row verdict are missing. 2026-10-04
os.execute("mkdir -p tests/fixtures/r56/308/head tests/fixtures/r56/308/main")
local pwd=assert(io.popen("pwd")):read("*l")
local function run(mode)
    local pipe=assert(io.popen("GATE56_STUB="..mode.." GATE56_RUN="..pwd.."/tests/fixtures/r56/308/gate_stub.sh sh tools/gate56.sh "..pwd.."/tests/fixtures/r56/308/head "..pwd.."/tests/fixtures/r56/308/main x layered"))
    local output=pipe:read("*a"); assert(pipe:close()); return output
end
local same=run("same")
assert(same:match("ROW case=x pack=layered ticks=3 worst_ms=4%.00 cpu_s=2%.00 sha=12345678 valid=ok main_cpu_s=2%.50 main_sha=12345678 verdict=SAME"),"GT1")
print("GT1")
assert(run("slow"):match("verdict=SLOWER"),"GT2")
print("GT2")
--GT3 (integrator 2026-10-04, red on lane 308 head): same bytes but head slower than main is SLOWER, never SAME
--(DoD 1: every row Speed tie or faster).
assert(run("sameslow"):match("verdict=SLOWER"),"GT3")
print("GT3")
print("test_gate56: 3 cases, 3 passed, 0 failed")

--Red on round-37-base: the frozen accepted candidate contains an un-fed belt stub.
local H=require "tests.harness"
H.test("frozen inserter bulk layout flags source-less belt",function()
 H.new_world(H.shapes()[1]); local f=assert(io.open("tests/fixtures/validate_ins10s_bulk_stub.json")); local root=helpers.json_to_table(f:read("*a")); f:close()
 local V=require "logic.bp.validate"; local s=V.begin(root); while not s.done do V.step(s,{ops=100000}) end
 local found=false; for _,e in ipairs(s.errors or {}) do if e.code=="BP_V_BELT_NO_SOURCE" then found=true end end
 H.equal(found,true,"source-less belt run is diagnosed")
end)
H.done("test_validate_belt_no_source")

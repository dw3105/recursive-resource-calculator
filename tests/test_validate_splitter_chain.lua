--Red on round-37-base: the frozen accepted candidate contains consecutive splitter chain junk.
local H=require "tests.harness"
H.test("frozen inserter layout flags splitter chains",function()
 H.new_world(H.shapes()[1]); local f=assert(io.open("tests/fixtures/validate_ins10s_v3_chain.json")); local root=helpers.json_to_table(f:read("*a")); f:close()
 local V=require "logic.bp.validate"; local s=V.begin(root); while not s.done do V.step(s,{ops=100000}) end
 local found=false; for _,e in ipairs(s.errors or {}) do if e.code=="BP_V_SPLITTER_CHAIN" then found=true end end
 H.equal(found,true,"consecutive splitter chain is diagnosed")
end)
H.done("test_validate_splitter_chain")

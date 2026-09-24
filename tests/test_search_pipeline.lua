local H = require "tests.harness"
local Search = require "logic.bp.search"
H.test("search starts at the planning stage", function()
    local s = Search.begin({plan_result={steps={},flows={}}, grids={{w=2,h=2}}})
    H.equal(s.phase, "plan")
    H.equal(type(Search.step), "function")
end)
H.done("test_search_pipeline")

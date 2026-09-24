local H = require "tests.harness"
local Search = require "logic.bp.search"
H.test("search state records retry budget", function()
    local s = Search.begin({plan_result={steps={},flows={}}, grids={{w=2,h=2}}})
    H.equal(s.work.attempt or 0, 0)
end)
H.done("test_search_retry")

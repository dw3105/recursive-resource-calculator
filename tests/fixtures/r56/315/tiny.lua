local H = require "tests.harness"

H.test("a", function() print("FIXTURE-a") end)
H.test("b", function() print("FIXTURE-b") end)
H.done("tiny")

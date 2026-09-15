--Identities of items above normal quality: apart from legacy names and from each other, whatever the names contain
local H = require "tests.harness"

H.test("Q-12 a delimiter in item or quality names never makes two identities equal", function()
    H.new_world("2.0")
    local QualityId = require "logic.quality_id"
    if QualityId.encode("a:b", "c") == QualityId.encode("a", "b:c") then
        error("delimiter pair collides: " .. QualityId.encode("a:b", "c"))
    end
    H.equal(QualityId.encode("a:b", "c"), "item-quality:3:a:b1:c", "length-prefixed components")
    H.equal(QualityId.encode("a", "b:c"), "item-quality:1:a3:b:c", "length-prefixed components")
    H.equal(QualityId.encode("a", "rare") ~= "item/a@rare", true, "apart from a legacy item named a@rare")
    H.equal(QualityId.encode("a", "rare"):find("/", 1, true), nil, "no slash, so no legacy full name")
end)

H.done("test_quality_id")

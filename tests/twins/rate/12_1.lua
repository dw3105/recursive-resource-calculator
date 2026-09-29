local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {segments={{segment_id="s",kind="inserter",capacity_per_second=1,allocations={{flow_id="item/iron-plate",rate_per_second=2}}}},flows={{flow_id="item/iron-plate"}}}
return {id = "T-280-V121", rule = "BP_V_INSERTER_CAPACITY", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect", codes = {"BP_V_INSERTER_CAPACITY"}, audit = {}}

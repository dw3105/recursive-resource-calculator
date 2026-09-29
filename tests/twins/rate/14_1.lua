local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {flows={{flow_id="item/iron-plate",producers={{step_id="s",share_per_second=2}},consumers={{step_id="s",share_per_second=0}}}},segments={{segment_id="s",kind="belt",flow_id="item/iron-plate",capacity_per_second=10}}}
return {id = "T-280-V141", rule = "BP_V_FLOW_IMBALANCE", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect", codes = {"BP_V_FLOW_IMBALANCE"}, audit = {}}

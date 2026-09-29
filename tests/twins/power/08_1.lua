local entities = {{id="p1",kind="pole",name="medium-electric-pole",x=1,y=1},{id="p2",kind="pole",name="medium-electric-pole",x=18,y=18}}
local validator = {catalog={entity={ ["medium-electric-pole"]={name="medium-electric-pole",etype="electric-pole",wire_reach=9}}}}
return {id = "T-280-V81", rule = "BP_V_WIRE_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "defect", codes = {"BP_V_WIRE_DISCONNECTED"}, audit = {}}

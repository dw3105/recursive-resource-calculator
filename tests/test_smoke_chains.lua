local H = require "tests.harness"
local fluid = require "docs.tasks.068_fluid_smoke"
local beacon = require "docs.tasks.068_beacon_power_smoke"

for _, shape in ipairs(H.shapes()) do
    fluid.run(shape)
    beacon.run(shape)
end

H.done("test_smoke_chains")

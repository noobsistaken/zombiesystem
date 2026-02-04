--[[
    Author: noobs
]]
--[[
    Client Entry Point
    Initializes Knit and all client-side Controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

--------------------------------------------------------------------------------
-- ADD CONTROLLERS
--------------------------------------------------------------------------------

local ControllersFolder = script:FindFirstChild("Controllers")

if ControllersFolder then
    Knit.AddControllers(ControllersFolder)
else
    warn("[Client] Controllers folder not found!")
end

--------------------------------------------------------------------------------
-- START KNIT
--------------------------------------------------------------------------------

Knit.Start():andThen(function()
    print("[Client] Knit started successfully!")
end):catch(function(err)
    warn("[Client] Knit failed to start:", err)
end)

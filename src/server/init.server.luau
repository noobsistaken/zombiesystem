--[[
    Author: noobs
]]
--[[
    Server Entry Point
    Initializes Knit and all server-side Services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

--------------------------------------------------------------------------------
-- ADD SERVICES
--------------------------------------------------------------------------------

-- Services are loaded by Knit.AddServices from the Services folder
-- Note: init.server.luau becomes the Script, so Services is a child of `script`
local ServicesFolder = script:FindFirstChild("Services")

if ServicesFolder then
    Knit.AddServices(ServicesFolder)
else
    warn("[Server] Services folder not found!")
end

--------------------------------------------------------------------------------
-- START KNIT
--------------------------------------------------------------------------------

Knit.Start():andThen(function()
    print("[Server] Knit started successfully!")
end):catch(function(err)
    warn("[Server] Knit failed to start:", err)
end)

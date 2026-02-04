--[[
    Author: noobs
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local ProjectileVisuals = require(script.Parent.Parent.Modules.ProjectileVisuals)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local WeaponConfig = GameConfig.Weapon
local TracerConfig = GameConfig.Tracer
local ZOOM_THRESHOLD = 1.5

----------------------------------------------------------------

local WeaponController = Knit.CreateController({
    Name = "WeaponController",
})

local ControllerJanitor = Janitor.new()
local WeaponService: any = nil
local ViewmodelController: any = nil
local ZombieController: any = nil

local isFiring = false
local lastFireTime = 0

----------------------------------------------------------------

local function GetCamera(): Camera
    return workspace.CurrentCamera
end

local function IsInFirstPerson(): boolean
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local dist = (camera.CFrame.Position - camera.Focus.Position).Magnitude
    return dist < ZOOM_THRESHOLD
end

----------------------------------------------------------------

local function PerformLocalRaycast(origin: Vector3, direction: Vector3): number?
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    
    local zombieFolder = workspace:FindFirstChild("Zombies")
    if not zombieFolder then
        return nil
    end
    
    rayParams.FilterDescendantsInstances = {zombieFolder}

    local normalizedDir = direction.Unit * WeaponConfig.MaxRaycastDistance
    local result = workspace:Raycast(origin, normalizedDir, rayParams)

    if result and result.Instance then
        local zombieModel = result.Instance:FindFirstAncestorOfClass("Model")
        if zombieModel then
            local idMatch = string.match(zombieModel.Name, "Zombie_(%d+)")
            if idMatch then
                return tonumber(idMatch)
            end
        end
    end

    return nil
end

----------------------------------------------------------------

local function FireShot()
    if not IsInFirstPerson() then return end
    
    local camera = GetCamera()
    if not camera then return end

    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    ProjectileVisuals.FireTracer(ray.Origin, ray.Direction, TracerConfig)

    if ViewmodelController then
        ViewmodelController:ApplyRecoil()
    end

    local hitZombieId = PerformLocalRaycast(ray.Origin, ray.Direction)

    -- Optimistic kill: hide instantly on client
    if hitZombieId and ZombieController then
        ZombieController:ProcessLocalHit(hitZombieId)
    end

    local params = {
        Origin = ray.Origin,
        Direction = ray.Direction,
        HitZombieId = hitZombieId,
    }

    WeaponService:Shoot(params):catch(function(err)
        warn("[WeaponController] Shoot error:", err)
    end)
end

----------------------------------------------------------------

function WeaponController:KnitStart()
    WeaponService = Knit.GetService("WeaponService")

    local success, result = pcall(function()
        return Knit.GetController("ViewmodelController")
    end)
    if success then
        ViewmodelController = result
    end

    local success2, result2 = pcall(function()
        return Knit.GetController("ZombieController")
    end)
    if success2 then
        ZombieController = result2
    end

    ControllerJanitor:Add(
        WeaponService.OnHitConfirmed:Connect(function(position: Vector3)
        end),
        "Disconnect"
    )

    ControllerJanitor:Add(
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isFiring = true
            end
        end),
        "Disconnect"
    )

    ControllerJanitor:Add(
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isFiring = false
            end
        end),
        "Disconnect"
    )

    ControllerJanitor:Add(
        RunService.RenderStepped:Connect(function()
            if isFiring and WeaponService then
                local now = os.clock()
                if now - lastFireTime >= 1 / WeaponConfig.FireRate then
                    lastFireTime = now
                    FireShot()
                end
            end
        end),
        "Disconnect"
    )

    print("[WeaponController] Started")
end

function WeaponController:KnitInit()
    print("[WeaponController] Initialized")
end

function WeaponController:Destroy()
    ControllerJanitor:Destroy()
end

return WeaponController

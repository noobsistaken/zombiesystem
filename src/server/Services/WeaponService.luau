--[[
    Author: noobs
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ShootParams = {
    Origin: Vector3,
    Direction: Vector3,
    HitZombieId: number?,
}

local Config = GameConfig.Weapon

----------------------------------------------------------------

local WeaponService = Knit.CreateService({
    Name = "WeaponService",
    Client = {
        OnHitConfirmed = Knit.CreateSignal(),
    },
})

local ServiceJanitor = Janitor.new()
local PlayerCooldowns: {[Player]: number} = {}

----------------------------------------------------------------

local function CheckRateLimit(player: Player): boolean
    local now = os.clock()
    local lastShot = PlayerCooldowns[player] or 0
    local minInterval = 1 / Config.RateLimitPerSecond

    if now - lastShot < minInterval then
        return false
    end

    PlayerCooldowns[player] = now
    return true
end

local function ValidateOrigin(player: Player, origin: Vector3): boolean
    local character = player.Character
    if not character then return false end

    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return false end

    local maxDistance = 10
    local distance = (origin - head.Position).Magnitude

    return distance <= maxDistance
end

----------------------------------------------------------------

function WeaponService.Client:Shoot(player: Player, params: ShootParams): boolean
    if not CheckRateLimit(player) then
        return false
    end

    if not ValidateOrigin(player, params.Origin) then
        return false
    end

    if params.Direction.Magnitude < 0.1 then
        return false
    end

    -- Client sends HitZombieId if they detected a hit
    if params.HitZombieId then
        local ZombieService = Knit.GetService("ZombieService")
        local zombie = ZombieService:GetZombieById(params.HitZombieId)

        if zombie then
            -- Validate hit: check if zombie is near the shot ray
            local toZombie = zombie.Position - params.Origin
            local rayDir = params.Direction.Unit
            local projLength = toZombie:Dot(rayDir)
            
            if projLength > 0 and projLength < Config.MaxRaycastDistance then
                local closestPoint = params.Origin + rayDir * projLength
                local dist = (zombie.Position - closestPoint).Magnitude
                
                if dist < 5 then -- Hit radius validation
                    ZombieService:RespawnZombie(params.HitZombieId)
                    self.OnHitConfirmed:Fire(player, zombie.Position)
                    return true
                end
            end
        end
    end

    return false
end

----------------------------------------------------------------

function WeaponService:KnitStart()
    ServiceJanitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
        PlayerCooldowns[player] = nil
    end), "Disconnect")

    print("[WeaponService] Started")
end

function WeaponService:KnitInit()
    print("[WeaponService] Initialized")
end

function WeaponService:Destroy()
    ServiceJanitor:Destroy()
end

return WeaponService

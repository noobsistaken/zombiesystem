--[[
    ZombieController
    Author: noobs

    Description: 
    Handles client-side rendering using BulkMoveTo.
    Listens to 10Hz snapshots from ZombieService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.janitor)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ZombieVisual = {
    Id: number,
    Model: Model,
    CurrentPos: Vector3,
    TargetPos: Vector3,
    Velocity: Vector3,
    IsNew: boolean,
    LastSeen: number,
    IsDead: boolean,
}

export type NetworkPacket = {
    P: Vector3,
    V: Vector3,
    H: number,
}

local Config = GameConfig.Zombies
local LERP_SPEED = 15
local NETWORK_TIMEOUT = 5.0

----------------------------------------------------------------

local ZombieController = Knit.CreateController({
    Name = "ZombieController",
})

local ControllerJanitor = Janitor.new()
local ZombieService: any = nil

local Visuals: {[number]: ZombieVisual} = {}
local LocalKills: {[number]: boolean} = {}
local snapshotCounter: number = 0

local zombieTemplate: Model? = nil
local zombieFolder: Folder? = nil

----------------------------------------------------------------

local function LoadTemplate()
    local Assets = ReplicatedStorage:FindFirstChild("Assets")
    if Assets then
        zombieTemplate = Assets:FindFirstChild("zombie")
    end
    
    if not zombieTemplate then
        warn("[ZombieController] No zombie template found!")
    end
end

local function CreateVisual(id: number, position: Vector3): ZombieVisual?
    if not zombieTemplate then
        return nil
    end

    local model = zombieTemplate:Clone()
    model.Name = "Zombie_" .. tostring(id)
    
    local rootPart = model:FindFirstChild("HumanoidRootPart")
    
    -- setup parts
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = true
            part.Size = part.Size * Config.HitboxScale
            
            if part == rootPart then
                -- root is anchored for BulkMoveTo
                part.Anchored = true
            else
                -- Other parts are unanchored and welded to root
                part.Anchored = false
            end
        end
    end
    
    -- weld to root
    if rootPart then
        for _, part in model:GetDescendants() do
            if part:IsA("BasePart") and part ~= rootPart then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = rootPart
                weld.Part1 = part
                weld.Parent = part
            end
        end
    end

    model:PivotTo(CFrame.new(position))
    model.Parent = zombieFolder

    local visual: ZombieVisual = {
        Id = id,
        Model = model,
        CurrentPos = position,
        TargetPos = position,
        Velocity = Vector3.zero,
        IsNew = true,
        LastSeen = os.clock(),
        IsDead = false,
    }

    return visual
end

local function DestroyVisual(id: number)
    local visual = Visuals[id]
    if visual then
        if visual.Model then
            visual.Model:Destroy()
        end
        Visuals[id] = nil
    end
    LocalKills[id] = nil
end

local function SetVisualTransparency(visual: ZombieVisual, transparency: number)
    if not visual.Model then return end
    for _, part in visual.Model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Transparency = transparency
            -- hide decals/textures too
            for _, child in part:GetChildren() do
                if child:IsA("Decal") or child:IsA("Texture") then
                    child.Transparency = transparency
                end
            end
        end
    end
end

----------------------------------------------------------------

local function OnSnapshot(snapshot: {[number]: NetworkPacket})
    local now = os.clock()
    local receivedCount = 0

    for id, packet in snapshot do
        receivedCount += 1
        local position = packet.P
        local velocity = packet.V
        local health = packet.H

        if LocalKills[id] then
            if health == 0 then
                -- server confirmed kill, we good
                DestroyVisual(id)
                LocalKills[id] = nil 
            end
            continue
        end

        local visual = Visuals[id]
        
        if health == 0 then
            -- EXPLICIT DEATH: Server says zombie is dead
            if visual then
                DestroyVisual(id)
            end
            continue
        end

        -- Zombie is alive
        if visual then
            visual.TargetPos = position
            visual.Velocity = velocity
            visual.LastSeen = now
            visual.IsNew = false
            visual.IsDead = false
            SetVisualTransparency(visual, 0)
        else
            -- snap new entities
            local newVisual = CreateVisual(id, position)
            if newVisual then
                newVisual.TargetPos = position
                newVisual.CurrentPos = position
                newVisual.Velocity = velocity
                newVisual.LastSeen = now
                newVisual.IsNew = true
                newVisual.IsDead = false
                Visuals[id] = newVisual
            end
        end
    end
    
    -- debug stats
    snapshotCounter = snapshotCounter + 1
    if snapshotCounter % 30 == 0 then
        local visualCount = 0
        for _ in Visuals do visualCount += 1 end
        print(string.format("[CLIENT] Received: %d | Visuals: %d", receivedCount, visualCount))
    end
end

local function OnRenderStepped(dt: number)
    local now = os.clock()
    
    -- bulk move prep
    local parts: {BasePart} = {}
    local cframes: {CFrame} = {}

    for id, visual in Visuals do
        if not visual.Model then
            continue
        end

        -- skip dead
        if LocalKills[id] then
            continue
        end

        -- timeout check
        if (now - visual.LastSeen) >= NETWORK_TIMEOUT then
            DestroyVisual(id)
            continue
        end

        -- snap
        if visual.IsNew then
            visual.CurrentPos = visual.TargetPos
            visual.IsNew = false
        else
            -- lerp
            local diff = visual.TargetPos - visual.CurrentPos
            local dist = diff.Magnitude

            if dist > 20 then
                -- studio lag fix
                visual.CurrentPos = visual.TargetPos
            elseif dist > 0.01 then
                local moveAmount = math.min(LERP_SPEED * dt, dist)
                visual.CurrentPos = visual.CurrentPos + diff.Unit * moveAmount
            else
                visual.CurrentPos = visual.TargetPos
            end
        end

        local finalPos = Vector3.new(visual.CurrentPos.X, Config.SpawnHeight, visual.CurrentPos.Z)
        local rootPart = visual.Model:FindFirstChild("HumanoidRootPart")
        
        if rootPart and rootPart:IsA("BasePart") then
            local targetCFrame: CFrame
            if visual.Velocity.Magnitude > 0.1 then
                targetCFrame = CFrame.lookAt(finalPos, finalPos + visual.Velocity)
            else
                targetCFrame = CFrame.new(finalPos)
            end
            
            table.insert(parts, rootPart)
            table.insert(cframes, targetCFrame)
        end
    end
    
    -- optimize bridge calls
    if #parts > 0 then
        workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end
end

----------------------------------------------------------------

function ZombieController:ProcessLocalHit(id: number)
    local visual = Visuals[id]
    if visual then
        SetVisualTransparency(visual, 1)
        LocalKills[id] = true
    end
end

----------------------------------------------------------------

function ZombieController:KnitStart()
    ZombieService = Knit.GetService("ZombieService")

    zombieFolder = Instance.new("Folder")
    zombieFolder.Name = "Zombies"
    zombieFolder.Parent = workspace
    ControllerJanitor:Add(zombieFolder, "Destroy")

    LoadTemplate()

    ControllerJanitor:Add(
        ZombieService.OnSnapshot:Connect(OnSnapshot),
        "Disconnect"
    )

    ControllerJanitor:Add(
        RunService.RenderStepped:Connect(OnRenderStepped),
        "Disconnect"
    )

    print("[ZombieController] Started (explicit death state)")
end

function ZombieController:KnitInit()
    print("[ZombieController] Initialized")
end

function ZombieController:GetVisualAtPosition(position: Vector3, radius: number): ZombieVisual?
    for _, visual in Visuals do
        if visual.Model and not LocalKills[visual.Id] then
            local dist = (visual.CurrentPos - position).Magnitude
            if dist < radius then
                return visual
            end
        end
    end
    return nil
end

function ZombieController:Destroy()
    ControllerJanitor:Destroy()
    for id, _ in Visuals do
        DestroyVisual(id)
    end
end

return ZombieController

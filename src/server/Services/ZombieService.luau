--[[
    ZombieService
    Author: noobs

    Description:
    Handles server-side zombie logic.
    Uses Spatial Hashing (O(N) neighbor lookup) and steering behaviors.
    Replicates compressed snapshots at 10Hz.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SwarmMath = require(ReplicatedStorage.Shared.Modules.SwarmMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

export type ZombieData = {
    Id: number,
    Position: Vector3,
    Velocity: Vector3,
    Health: number,
    DeathTime: number?,
}

export type NetworkPacket = {
    P: Vector3,  -- Position
    V: Vector3,  -- Velocity
    H: number,   -- Health (0 = dead)
}

local Config = GameConfig.Zombies
local DEAD_BROADCAST_TIME = 1.0

----------------------------------------------------------------

local ZombieService = Knit.CreateService({
    Name = "ZombieService",
    Client = {
        OnSnapshot = Knit.CreateSignal(),
    },
})

local Zombies: {[number]: ZombieData} = {}
local ZombieCount: number = 0
local NextId: number = 1

local CELL_SIZE = 10
local grid: {[string]: {ZombieData}} = {}

local SNAPSHOT_INTERVAL = 0.1
local lastSnapshotTime = 0

local RESPAWN_DELAY = 3.0
local RespawnQueue: {number} = {}

-- optimize: skip far steering
local STEERING_SKIP_DISTANCE = 100

----------------------------------------------------------------

local function GetRandomSpawnPosition(): Vector3
    local angle = math.random() * math.pi * 2
    local radius = math.random() * Config.SpawnRadius
    return Vector3.new(
        math.cos(angle) * radius,
        Config.SpawnHeight,
        math.sin(angle) * radius
    )
end

local function GetCellKey(pos: Vector3): string
    local cx = math.floor(pos.X / CELL_SIZE)
    local cz = math.floor(pos.Z / CELL_SIZE)
    return cx .. "_" .. cz
end

local function GridClear()
    table.clear(grid)
end

local function GridInsert(zombie: ZombieData)
    local key = GetCellKey(zombie.Position)
    if not grid[key] then
        grid[key] = {}
    end
    table.insert(grid[key], zombie)
end

local function GridGetNeighbors(pos: Vector3): {ZombieData}
    local result: {ZombieData} = {}
    local cx = math.floor(pos.X / CELL_SIZE)
    local cz = math.floor(pos.Z / CELL_SIZE)
    
    for dx = -1, 1 do
        for dz = -1, 1 do
            local key = (cx + dx) .. "_" .. (cz + dz)
            local cell = grid[key]
            if cell then
                for _, z in cell do
                    table.insert(result, z)
                end
            end
        end
    end
    return result
end

----------------------------------------------------------------

local function GetNearestPlayerPosition(): Vector3?
    local players = Players:GetPlayers()
    if #players == 0 then
        return nil
    end

    local centroid = Vector3.zero
    local count = 0
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            centroid += zombie.Position
            count += 1
        end
    end
    
    if count > 0 then
        centroid /= count
    end

    local closestPos: Vector3? = nil
    local closestDist = math.huge

    for _, player in players do
        local character = player.Character
        if character then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                local dist = (root.Position - centroid).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPos = root.Position
                end
            end
        end
    end

    return closestPos
end

----------------------------------------------------------------

function ZombieService:SpawnZombie(position: Vector3?): ZombieData?
    if ZombieCount >= Config.MaxCount then
        return nil
    end

    local spawnPos = position or GetRandomSpawnPosition()

    local zombie: ZombieData = {
        Id = NextId,
        Position = spawnPos,
        Velocity = Vector3.zero,
        Health = 1,
        DeathTime = nil,
    }

    NextId += 1
    ZombieCount += 1
    Zombies[zombie.Id] = zombie

    return zombie
end

function ZombieService:KillZombie(zombieId: number): boolean
    local zombie = Zombies[zombieId]
    if zombie and zombie.Health > 0 then
        zombie.Health = 0
        zombie.DeathTime = os.clock()
        ZombieCount -= 1
        return true
    end
    return false
end

function ZombieService:RespawnZombie(zombieId: number)
    if self:KillZombie(zombieId) then
        table.insert(RespawnQueue, os.clock() + RESPAWN_DELAY)
    end
end

function ZombieService:GetZombieById(zombieId: number): ZombieData?
    return Zombies[zombieId]
end

function ZombieService:GetZombieAtPosition(position: Vector3, radius: number): ZombieData?
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            local dist = (zombie.Position - position).Magnitude
            if dist < radius then
                return zombie
            end
        end
    end
    return nil
end

----------------------------------------------------------------

local function BuildSnapshot(): {[number]: NetworkPacket}
    local snapshot: {[number]: NetworkPacket} = {}
    local now = os.clock()
    
    for id, zombie in Zombies do
        if zombie.Health > 0 then
            snapshot[id] = {
                P = zombie.Position,
                V = zombie.Velocity,
                H = 1,
            }
        elseif zombie.DeathTime and (now - zombie.DeathTime) < DEAD_BROADCAST_TIME then
            -- broadcast death for 1s
            snapshot[id] = {
                P = zombie.Position,
                V = Vector3.zero,
                H = 0,
            }
        end
    end
    
    return snapshot
end

local function CleanupDeadZombies()
    local now = os.clock()
    local toRemove: {number} = {}
    
    for id, zombie in Zombies do
        if zombie.Health <= 0 and zombie.DeathTime then
            if (now - zombie.DeathTime) >= DEAD_BROADCAST_TIME then
                table.insert(toRemove, id)
            end
        end
    end
    
    for _, id in toRemove do
        Zombies[id] = nil
    end
end

local function ProcessRespawnQueue()
    local now = os.clock()
    local i = 1
    while i <= #RespawnQueue do
        local unlockTime = RespawnQueue[i]
        if now >= unlockTime then
            table.remove(RespawnQueue, i)
            ZombieService:SpawnZombie() -- Fresh ID, no arguments
        else
            i += 1
        end
    end
end

local function Heartbeat(dt: number)
    local target = GetNearestPlayerPosition()
    local now = os.clock()
    
    CleanupDeadZombies()
    ProcessRespawnQueue()
    
    if not target then
        if now - lastSnapshotTime >= SNAPSHOT_INTERVAL then
            lastSnapshotTime = now
            local snapshot = BuildSnapshot()
            ZombieService.Client.OnSnapshot:FireAll(snapshot)
        end
        return
    end

    -- grid update
    GridClear()
    for _, zombie in Zombies do
        if zombie.Health > 0 then
            GridInsert(zombie)
        end
    end

    -- update loop
    for _, zombie in Zombies do
        if zombie.Health <= 0 then
            continue
        end

        local distToTarget = (zombie.Position - target).Magnitude
        local hasVelocity = zombie.Velocity.Magnitude > 0.1

        if distToTarget > STEERING_SKIP_DISTANCE and hasVelocity then
            -- far: coast
            local newPos = zombie.Position + zombie.Velocity * dt
            newPos = Vector3.new(newPos.X, Config.SpawnHeight, newPos.Z)
            zombie.Position = newPos
        else
            -- near: steer
            local neighbors = GridGetNeighbors(zombie.Position)
            
            local localNeighbors: {SwarmMath.EntityState} = {}
            for _, neighbor in neighbors do
                if neighbor ~= zombie and neighbor.Health > 0 then
                    local dist = (zombie.Position - neighbor.Position).Magnitude
                    if dist < Config.NeighborRadius then
                        table.insert(localNeighbors, {
                            Position = neighbor.Position,
                            Velocity = neighbor.Velocity,
                        })
                    end
                end
            end

            local agentState: SwarmMath.EntityState = {
                Position = zombie.Position,
                Velocity = zombie.Velocity,
            }

            local force = SwarmMath.CalculateSteering(agentState, localNeighbors, target)
            local _, newVel = SwarmMath.ApplyForce(agentState, force, dt)
            
            zombie.Velocity = Vector3.new(newVel.X, 0, newVel.Z)
            
            local newPos = zombie.Position + zombie.Velocity * dt
            newPos = Vector3.new(newPos.X, Config.SpawnHeight, newPos.Z)
            zombie.Position = newPos
        end
    end

    if now - lastSnapshotTime >= SNAPSHOT_INTERVAL then
        lastSnapshotTime = now
        local snapshot = BuildSnapshot()
        ZombieService.Client.OnSnapshot:FireAll(snapshot)
    end
end

----------------------------------------------------------------

function ZombieService:KnitStart()
    for _ = 1, Config.MaxCount do
        self:SpawnZombie()
    end

    print("[ZombieService] Spawned", Config.MaxCount, "zombies (explicit state)")

    RunService.Heartbeat:Connect(Heartbeat)

    -- Debug Logger (Portfolio Proof)
    task.spawn(function()
        while true do
            task.wait(3)
            local entityCount = 0
            local aliveCount = 0
            for _, zombie in Zombies do
                entityCount += 1
                if zombie.Health > 0 then
                    aliveCount += 1
                end
            end
            local snapshot = BuildSnapshot()
            local snapshotSize = 0
            for _ in snapshot do
                snapshotSize += 1
            end
            print(string.format(
                "[SERVER] Entities: %d | Alive: %d | Queue: %d | Snapshot: %d",
                entityCount,
                aliveCount,
                #RespawnQueue,
                snapshotSize
            ))
        end
    end)
end

function ZombieService:KnitInit()
    print("[ZombieService] Initialized")
end

return ZombieService

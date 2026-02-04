--[[
    Author: noobs
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type Entity = {
    Position: Vector3,
    [string]: any,
}

export type SpatialHashGrid = {
    CellSize: number,
    Cells: {[string]: {Entity}},
}

----------------------------------------------------------------

local function GetCellKey(position: Vector3, cellSize: number): string
    local x = math.floor(position.X / cellSize)
    local z = math.floor(position.Z / cellSize)
    return x .. "_" .. z
end

----------------------------------------------------------------

function SpatialHash.new(cellSize: number?): SpatialHashGrid
    local self = setmetatable({}, SpatialHash)
    self.CellSize = cellSize or 10
    self.Cells = {}
    return self :: any
end

----------------------------------------------------------------

function SpatialHash.Clear(self: SpatialHashGrid)
    table.clear(self.Cells)
end

function SpatialHash.Insert(self: SpatialHashGrid, entity: Entity)
    local key = GetCellKey(entity.Position, self.CellSize)
    
    if not self.Cells[key] then
        self.Cells[key] = {}
    end
    
    table.insert(self.Cells[key], entity)
end

----------------------------------------------------------------

function SpatialHash.GetNearby(self: SpatialHashGrid, position: Vector3): {Entity}
    local result: {Entity} = {}
    local cellSize = self.CellSize
    
    local cx = math.floor(position.X / cellSize)
    local cz = math.floor(position.Z / cellSize)
    
    for dx = -1, 1 do
        for dz = -1, 1 do
            local key = (cx + dx) .. "_" .. (cz + dz)
            local cell = self.Cells[key]
            if cell then
                for _, entity in cell do
                    table.insert(result, entity)
                end
            end
        end
    end
    
    return result
end

----------------------------------------------------------------

function SpatialHash.Rebuild(self: SpatialHashGrid, entities: {Entity})
    self:Clear()
    for _, entity in entities do
        self:Insert(entity)
    end
end

return SpatialHash

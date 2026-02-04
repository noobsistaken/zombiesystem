--[[
    Author: noobs
]]

local Spring = {}

export type Spring = {
    Position: Vector3,
    Velocity: Vector3,
    Target: Vector3,
    Damping: number,
    Stiffness: number,
    
    SetTarget: (self: Spring, target: Vector3) -> (),
    Impulse: (self: Spring, force: Vector3) -> (),
    Update: (self: Spring, dt: number) -> Vector3,
}

----------------------------------------------------------------

function Spring.new(damping: number?, stiffness: number?): Spring
    local self = {} :: Spring

    self.Position = Vector3.zero
    self.Velocity = Vector3.zero
    self.Target = Vector3.zero
    self.Damping = damping or 0.5
    self.Stiffness = stiffness or 10

    function self:SetTarget(target: Vector3)
        self.Target = target
    end

    function self:Impulse(force: Vector3)
        self.Velocity = self.Velocity + force
    end

    function self:Update(dt: number): Vector3
        local displacement = self.Target - self.Position
        local springForce = displacement * self.Stiffness
        local dampingForce = self.Velocity * self.Damping

        local acceleration = springForce - dampingForce

        self.Velocity = self.Velocity + acceleration * dt
        
        -- Clamp velocity to prevent runaway
        local maxVel = 50
        if self.Velocity.Magnitude > maxVel then
            self.Velocity = self.Velocity.Unit * maxVel
        end
        
        self.Position = self.Position + self.Velocity * dt

        return self.Position
    end

    return self
end

return Spring

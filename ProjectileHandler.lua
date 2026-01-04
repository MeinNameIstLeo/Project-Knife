```--// services 
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--// basic variables
local debugMode = false
local utility = ReplicatedStorage:WaitForChild("Utility")
local resources = ReplicatedStorage:WaitForChild("Resources")

--// required modules
local Types = require(resources:WaitForChild("Types"))
local CollisionDetection = require(script.Parent:WaitForChild("CollisionDetection"))
local disconnectAndClear = require(utility:WaitForChild("disconnectAndClear"))

--// projectile handler 
local ProjectileHandler = {}
ProjectileHandler.__index = ProjectileHandler

--// create a new projectile instance
function ProjectileHandler.new(origin:Vector3, velocity:Vector3, knifeStats:Types.KnifeStats, character:Model): Types.Projectile
	local self = setmetatable({}, ProjectileHandler)

	-- store owning character
	self.character = character

	-- store current position
	self.position = origin
	-- store starting position
	self.origin = origin

	-- store movement velocity
	self.velocity = velocity
	-- store stat table
	self.stats = knifeStats

	-- build gravity vector (downward force)
	self.gravity = Vector3.new(0, -knifeStats.projectileGravity, 0)

	-- store how long projectile can live
	self.lifeTime = knifeStats.projectileLifetime
	-- store max travel distance
	self.maxRange = knifeStats.projectileRange

	-- store explosion, phase, and bounce flags
	self.canExplode = knifeStats.explodeOnImpact
	self.canPhase = knifeStats.canPhase
	self.canBounce = knifeStats.canBounce or false
	self.bounceCount = 0
	self.maxBounces = 3

	-- store connections for cleanup
	self.connections = {}

	-- store internal state flags
	self.alive = true
	self.hasHit = false

	-- store time started
	self.startTime = 0

	-- store optional callbacks
	self.onHit = nil
	self.onExpire = nil

	return self
end

--// update projectile every frame
function ProjectileHandler:Update(dt)
	-- stop update if projectile is dead
	if not self.alive then
		return
	end

	-- apply gravity to velocity
	self.velocity = self.velocity + self.gravity * dt

	-- calculate movement displacement
	local displacement = self.velocity * dt
	-- get displacement magnitude
	local mag = displacement.Magnitude

	-- get safe direction (prevents zero-length vectors)
	local dir = (mag > 0) and displacement.Unit or Vector3.new(0, 0, 1)

	-- extend displacement slightly to prevent tunneling
	local extendedDisplacement = dir * (mag + 0.01)

	-- calculate next position
	local nextPosition = self.position + displacement
	-- calculate traveled distance
	local traveledDistance = (nextPosition - self.origin).Magnitude

	-- check lifetime or range expiration
	if tick() - self.startTime > self.lifeTime or traveledDistance > self.maxRange then
		self.alive = false
		self:Cleanup()
		if self.onExpire then
			self.onExpire()
		end
		return
	end

	-- build raycast params
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- build exclude list
	local excludeList = { self.character, workspace.fx }

	-- exclude map folder if phasing is enabled
	if self.canPhase and workspace:FindFirstChild("MapFolder") then
		table.insert(excludeList, workspace.MapFolder)
	end

	params.FilterDescendantsInstances = excludeList

	-- create cast cframe
	local castCFrame = CFrame.lookAlong(self.position, extendedDisplacement)
	-- define cast box size
	local castSize = Vector3.new(0.3, 0.25, 0.7)

	-- create visual debug part (invisible hitbox)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = castSize
	part.Parent = workspace.fx

	-- perform blockcast
	local result = workspace:Blockcast(castCFrame, castSize, extendedDisplacement, params)

	if result then
		-- calculate hit position
		local hitCenter = (castCFrame + dir * result.Distance).Position
		self.position = hitCenter

		-- apply impulse if hit part is unanchored
		if result.Instance and result.Instance:IsA("BasePart") and not result.Instance.Anchored then
			local impactForce = self.stats.impactForce or 50
			local impulse = self.velocity.Unit * impactForce
			result.Instance.AssemblyLinearVelocity =
				result.Instance.AssemblyLinearVelocity + impulse
		end

		-- bounce logic
		if self.canBounce and self.bounceCount < self.maxBounces then
			self.bounceCount = self.bounceCount + 1
			-- reflect velocity using surface normal
			if result.Normal then
				self.velocity = self.velocity - 2 * self.velocity:Dot(result.Normal) * result.Normal
			end
			-- continue simulation after bounce
			return
		end

		-- mark as hit if no bounce or max bounces reached
		self.hasHit = true
		self.alive = false
		self:Cleanup()

		-- explosion logic
		if self.canExplode then
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { self.character }

			-- area hit detection
			local hitParts = workspace:GetPartsInBox(
				CFrame.new(hitCenter),
				Vector3.new(8, 8, 8),
				overlapParams
			)

			if self.onHit then
				self.onHit({
					Position = hitCenter,
					Parts = hitParts,
					Exploded = true
				})
			end
		else
			-- direct impact hit
			if self.onHit then
				self.onHit({
					Position = hitCenter,
					Instance = result.Instance,
					Normal = result.Normal
				})
			end
		end

		Debris:AddItem(part, 0.01)
		return
	end

	-- move visual part forward
	part.CFrame = castCFrame
	-- update position normally
	self.position = nextPosition
	-- cleanup visual part
	Debris:AddItem(part, 0.01)
end

--// start projectile simulation
function ProjectileHandler:Fire()
	self.startTime = tick()

	-- heartbeat drives projectile updates
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)

	table.insert(self.connections, heartbeatConn)

	if debugMode then
		-- visual indicator for debugging
		local debugPart = Instance.new("Part")
		debugPart.Size = Vector3.new(0.3, 3, 0.3)
		debugPart.Anchored = true
		debugPart.CanCollide = false
		debugPart.Material = Enum.Material.Basalt
		debugPart.Color = Color3.new(0.3, 0.3, 0.3)
		debugPart.Parent = workspace.fx

		local debugConn = RunService.Heartbeat:Connect(function()
			debugPart.Position = self.position
		end)

		table.insert(self.connections, debugConn)
		Debris:AddItem(debugPart, self.lifeTime)
	end
end

-- clamp projectile speed
function ProjectileHandler:ClampSpeed(minSpeed, maxSpeed)
	-- get current speed from velocity vector
	local speed = self.velocity.Magnitude

	-- if speed is below minimum, scale velocity up
	if speed < minSpeed then
		self.velocity = self.velocity.Unit * minSpeed

	-- if speed is above maximum, scale velocity down
	elseif speed > maxSpeed then
		self.velocity = self.velocity.Unit * maxSpeed
	end
end

-- get projectile age
function ProjectileHandler:GetAge()
	return tick() - self.startTime
end

-- check if projectile expired
function ProjectileHandler:IsExpired()
	return not self.alive
end

--// assign hit callback
function ProjectileHandler:SetOnHit(callback)
	self.onHit = callback
end

--// assign expire callback
function ProjectileHandler:SetOnExpire(callback)
	self.onExpire = callback
end

--// manually destroy projectile
function ProjectileHandler:Destroy()
	self.alive = false
	self:Cleanup()
end

--// cleanup all connections 
function ProjectileHandler:Cleanup()
	disconnectAndClear(self.connections)
	self.connections = {}
end

--// extra Utility

function ProjectileHandler:GetPosition()
	return self.position
end

-- get current velocity
function ProjectileHandler:GetVelocity()
	return self.velocity
end

-- force set velocity
function ProjectileHandler:SetVelocity(newVel)
	self.velocity = newVel
end

-- force set position
function ProjectileHandler:SetPosition(newPos)
	self.position = newPos
end

--// debug utilities

-- enable or disable debug visuals for this projectile
function ProjectileHandler:EnableDebug(value)
	self.debugEnabled = value
end

-- check if debug is enabled
function ProjectileHandler:IsDebugEnabled()
	return self.debugEnabled or false
end

-- print projectile state
function ProjectileHandler:PrintState()
	print("Projectile state:")
	print("Position:", self.position)
	print("Velocity:", self.velocity)
	print("Alive:", self.alive)
	print("HasHit:", self.hasHit)
	print("StartTime:", self.startTime)
end

--// return module table
return ProjectileHandler

--[[
Bounce logic isn't fully intergrated into the game,
it's no longer needed in my game,
I just kept it in for the 200 line limit
]]```

How many lines of code excluding all comments and whitespace

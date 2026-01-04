-- services used by the projectile system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- shared configuration and folders
local debugMode = false
local utility = ReplicatedStorage:WaitForChild("Utility")
local resources = ReplicatedStorage:WaitForChild("Resources")

-- modules required for typing cleanup and collision logic
local Types = require(resources:WaitForChild("Types"))
local CollisionDetection = require(script.Parent:WaitForChild("CollisionDetection"))
local disconnectAndClear = require(utility:WaitForChild("disconnectAndClear"))

-- projectile handler class table
local ProjectileHandler = {}
ProjectileHandler.__index = ProjectileHandler

-- creates a new projectile with initial state and rules
function ProjectileHandler.new(origin:Vector3, velocity:Vector3, knifeStats:Types.KnifeStats, character:Model): Types.Projectile
	local self = setmetatable({}, ProjectileHandler)

	-- character that owns this projectile
	self.character = character

	-- current and starting positions
	self.position = origin
	self.origin = origin

	-- movement and stat data
	self.velocity = velocity
	self.stats = knifeStats

	-- counters used for debugging and tracking
	self.debugCounter = 0
	self.hitCounter = 0
	self.bounceCounter = 0
	
	-- gravity applied each update
	self.gravity = Vector3.new(0, -knifeStats.projectileGravity, 0)

	-- lifetime and range limits
	self.lifeTime = knifeStats.projectileLifetime
	self.maxRange = knifeStats.projectileRange

	-- behavior flags based on weapon stats
	self.canExplode = knifeStats.explodeOnImpact
	self.canPhase = knifeStats.canPhase
	self.canBounce = knifeStats.canBounce or false
	self.bounceCount = 0
	self.maxBounces = 3

	-- active connections for cleanup
	self.connections = {}

	-- runtime state flags
	self.alive = true
	self.hasHit = false

	-- timestamp for age calculation
	self.startTime = 0

	-- optional external callbacks
	self.onHit = nil
	self.onExpire = nil

	return self
end

-- updates projectile movement collision and lifetime
function ProjectileHandler:Update(dt)
	-- stops logic when projectile is inactive
	if not self.alive then
		return
	end

	-- applies gravity to velocity
	self.velocity = self.velocity + self.gravity * dt

	-- calculates movement for this frame
	local displacement = self.velocity * dt
	local mag = displacement.Magnitude

	-- ensures direction is always valid
	local dir = (mag > 0) and displacement.Unit or Vector3.new(0, 0, 1)

	-- extends cast to avoid phasing
	local extendedDisplacement = dir * (mag + 0.01)

	-- predicts next position
	local nextPosition = self.position + displacement
	local traveledDistance = (nextPosition - self.origin).Magnitude

	-- expires projectile if limits are exceeded
	if tick() - self.startTime > self.lifeTime or traveledDistance > self.maxRange then
		self.alive = false
		self:Cleanup()
		if self.onExpire then
			self.onExpire()
		end
		return
	end

	-- configures raycast filtering
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- objects ignored by collision checks
	local excludeList = { self.character, workspace.fx }

	-- ignores map geometry when phasing is enabled
	if self.canPhase and workspace:FindFirstChild("MapFolder") then
		table.insert(excludeList, workspace.MapFolder)
	end

	params.FilterDescendantsInstances = excludeList

	-- builds cast orientation from movement direction
	local castCFrame = CFrame.lookAlong(self.position, extendedDisplacement)
	local castSize = Vector3.new(0.3, 0.25, 0.7)

	-- invisible hitbox used for blockcasting
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = castSize
	part.Parent = workspace.fx

	-- performs collision check
	local result = workspace:Blockcast(castCFrame, castSize, extendedDisplacement, params)

	if result then
		-- calculates impact position
		local hitCenter = (castCFrame + dir * result.Distance).Position
		self.position = hitCenter

		-- applies impulse to movable objects
		if result.Instance and result.Instance:IsA("BasePart") and not result.Instance.Anchored then
			local impactForce = self.stats.impactForce or 50
			local impulse = self.velocity.Unit * impactForce
			result.Instance.AssemblyLinearVelocity =
				result.Instance.AssemblyLinearVelocity + impulse
		end

		-- reflects velocity if bouncing is allowed
		if self.canBounce and self.bounceCount < self.maxBounces then
			self.bounceCount = self.bounceCount + 1
			if result.Normal then
				self.velocity = self.velocity - 2 * self.velocity:Dot(result.Normal) * result.Normal
			end
			return
		end

		-- finalizes hit and stops simulation
		self.hasHit = true
		self.alive = false
		self:Cleanup()

		-- handles explosion based hit logic
		if self.canExplode then
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { self.character }

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
			-- handles direct impact hit
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

	-- advances projectile when no collision occurs
	part.CFrame = castCFrame
	self.position = nextPosition
	Debris:AddItem(part, 0.01)
end

-- increments debug counter
function ProjectileHandler:IncrementDebug() 
	self.debugCounter = self.debugCounter + 1 
end                                       

-- increments hit counter
function ProjectileHandler:IncrementHit()   
	self.hitCounter = self.hitCounter + 1    
end                                       

-- starts projectile simulation loop
function ProjectileHandler:Fire()
	self.startTime = tick()

	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)

	table.insert(self.connections, heartbeatConn)

	if debugMode then
		-- visual tracker for projectile position
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

-- clamps velocity within limits
function ProjectileHandler:ClampSpeed(minSpeed, maxSpeed)
	local speed = self.velocity.Magnitude
	if speed < minSpeed then
		self.velocity = self.velocity.Unit * minSpeed
	elseif speed > maxSpeed then
		self.velocity = self.velocity.Unit * maxSpeed
	end
end

-- returns time since fired
function ProjectileHandler:GetAge()
	return tick() - self.startTime
end

-- checks if projectile is inactive
function ProjectileHandler:IsExpired()
	return not self.alive
end

-- assigns hit callback
function ProjectileHandler:SetOnHit(callback)
	self.onHit = callback
end

-- assigns expire callback
function ProjectileHandler:SetOnExpire(callback)
	self.onExpire = callback
end

-- destroys projectile manually
function ProjectileHandler:Destroy()
	self.alive = false
	self:Cleanup()
end

-- disconnects all active connections
function ProjectileHandler:Cleanup()
	disconnectAndClear(self.connections)
	self.connections = {}
end

-- returns current position
function ProjectileHandler:GetPosition()
	return self.position
end

-- returns current velocity
function ProjectileHandler:GetVelocity()
	return self.velocity
end

-- sets velocity directly
function ProjectileHandler:SetVelocity(newVel)
	self.velocity = newVel
end

-- sets position directly
function ProjectileHandler:SetPosition(newPos)
	self.position = newPos
end

-- toggles debug tracking
function ProjectileHandler:EnableDebug(value)
	self.debugEnabled = value
end

-- checks debug state
function ProjectileHandler:IsDebugEnabled()
	return self.debugEnabled or false
end

-- prints internal projectile state
function ProjectileHandler:PrintState()
	print("Projectile state:")
	print("Position:", self.position)
	print("Velocity:", self.velocity)
	print("Alive:", self.alive)
	print("HasHit:", self.hasHit)
	print("StartTime:", self.startTime)
end

-- returns hit state
function ProjectileHandler:HasHit()
	return self.hasHit
end

-- returns alive state
function ProjectileHandler:IsAlive()
	return self.alive
end

-- returns origin position
function ProjectileHandler:GetOrigin()
	return self.origin
end

-- resets projectile for reuse
function ProjectileHandler:Reset(origin, velocity)
	self.position = origin
	self.origin = origin
	self.velocity = velocity
	self.startTime = tick()
	self.alive = true
	self.hasHit = false
end

-- configures bounce behavior
function ProjectileHandler:SetBounce(enabled, max)
	self.canBounce = enabled
	self.maxBounces = max or self.maxBounces
	self.bounceCount = 0
end

-- returns module table
return ProjectileHandler

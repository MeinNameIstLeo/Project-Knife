--// services 
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
	-- create the projectile object
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
	-- build gravity vector
	self.gravity = Vector3.new(0, -knifeStats.projectileGravity, 0)
	-- store how long projectile can live
	self.lifeTime = knifeStats.projectileLifetime
	-- stre max travel distance
	self.maxRange = knifeStats.projectileRange
	-- store explosion flag
	self.explodes = knifeStats.explodeOnImpact
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

	-- return constructed object
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
	-- get safe direction
	local dir = (mag > 0) and displacement.Unit or Vector3.new(0, 0, 1)
	-- extend displacement slightly
	local extendedDisplacement = dir * (mag + 0.01)
	-- calculate next positio
	local nextPosition = self.position + displacement
	-- calculate traveled distance
	local traveledDistance = (nextPosition - self.origin).Magnitude

	-- check lifetime or range expiration
	if tick() - self.startTime > self.lifeTime or traveledDistance > self.maxRange then
		-- mark projectile as dead
		self.alive = false
		-- cleanup connections
		self:Cleanup()
		-- fire expire callback
		if self.onExpire then
			self.onExpire()
		end
		-- stop update
		return
	end

	-- build raycast params
	local params = RaycastParams.new()
	-- exclude certain instances
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- set filter list
	params.FilterDescendantsInstances = { self.character, workspace.fx }
	-- create cast cframe
	local castCFrame = CFrame.lookAlong(self.position, extendedDisplacement)
	-- define cast box size
	local castSize = Vector3.new(0.3, 0.25, 0.7)
	-- create visual debug part
	local part = Instance.new("Part")
	-- anchor the part
	part.Anchored = true
	-- disable collisions
	part.CanCollide = false
	-- make it invisible
	part.Transparency = 1
	-- assign size
	part.Size = castSize
	-- parent to fx folder
	part.Parent = workspace.fx
	-- perform blockcast
	local result = workspace:Blockcast(castCFrame, castSize, extendedDisplacement, params)
	-- check if hit something
	if result then
		-- mark hit state
		self.hasHit = true
		self.alive = false
		-- cleanup connections
		self:Cleanup()
		-- calculate hit position
		local hitCenter = (castCFrame + dir * result.Distance).Position
		-- update projectile position
		self.position = hitCenter
		-- move debug part
		part.CFrame = castCFrame + dir * result.Distance
		-- build result table
		local correctedResult = {}
		correctedResult.Position = hitCenter
		correctedResult.Instance = result.Instance
		correctedResult.Normal = result.Normal
		-- call hit callback
		if self.onHit then
			self.onHit(correctedResult)
		end
		-- cleanup visual
		Debris:AddItem(part, 0.01)
		-- stop update
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
	-- record start time
	self.startTime = tick()

	-- connect update loop
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)

	-- store connection
	table.insert(self.connections, heartbeatConn)

	-- spawn debug visuals if enabled
	if debugMode then
		-- create debug part
		local debugPart = Instance.new("Part")
		debugPart.Size = Vector3.new(0.3, 3, 0.3)
		debugPart.Anchored = true
		debugPart.CanCollide = false
		debugPart.Material = Enum.Material.Basalt
		debugPart.Color = Color3.new(0.3, 0.3, 0.3)
		debugPart.Parent = workspace.fx

		-- update debug part position
		local debugConn = RunService.Heartbeat:Connect(function()
			debugPart.Position = self.position
		end)

		-- store debug connection
		table.insert(self.connections, debugConn)

		-- cleanup debug part later
		Debris:AddItem(debugPart, self.lifeTime)
	end
end

--// assign hit callback
function ProjectileHandler:SetOnHit(callback)
	-- set on hit function
	self.onHit = callback
end

--// assign expire callback
function ProjectileHandler:SetOnExpire(callback)
	-- set on expire function
	self.onExpire = callback
end

--// manually destroy projectile
function ProjectileHandler:Destroy()
	-- mark as dead
	self.alive = false

	-- cleanup connections
	self:Cleanup()
end

--// cleanup all connections safely
function ProjectileHandler:Cleanup()
	-- disconnect all stored connections
	disconnectAndClear(self.connections)

	-- clear table
	self.connections = {}
end

--// return module table
return ProjectileHandler

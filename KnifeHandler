--//Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--//Variables
local utility = ReplicatedStorage:WaitForChild("Utility")
local resources = ReplicatedStorage:WaitForChild("Resources")
local hitDetection = script.Parent:WaitForChild("HitDetection")
--//Requires
local ProjectileHandler = require(hitDetection:WaitForChild("ProjectileHandler"))
local ProjectileVisual = require(script.Parent:WaitForChild("Visuals"):WaitForChild("ProjectileVisual"))
local animationHandler = require(script.Parent:WaitForChild("OtherHandlers"):WaitForChild("AnimationHandler"))
local BaseStats = require(script.Parent:WaitForChild("Stats"):WaitForChild("BaseStats"))
local getKnifeVelocity = require(script.Parent:WaitForChild("Utility"):WaitForChild("getKnifeVelocity"))
local getProjectileDirection = require(script.Parent:WaitForChild("Utility"):WaitForChild("getProjectileDirection"))
local getAimDirection = require(script.Parent.Utility:WaitForChild("getAimDirection"))
local disconnectAndClear = require(utility:WaitForChild("disconnectAndClear"))

-- module
local KnifeHandler = {}
KnifeHandler.__index = KnifeHandler

-- New knife setup
function KnifeHandler.new(knife : Tool, character : Model) 
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid:WaitForChild("Animator")
	local animHandler = animationHandler.new(knife, animator)
	
	-- Self setup
	local self = setmetatable({
		animationHandler = animHandler,
		character = character,
		humanoid = humanoid,
		knife = knife,
		equipped = false,
		stats = BaseStats.Knife,
		ammo = knife:GetAttribute("_ammo"),
		isSwinging = knife:GetAttribute("isSwinging"),
		isReloading = knife:GetAttribute("isReloading"),
		connections = {},
		
	}, KnifeHandler)
	
	-- Setup connections
	self:Init()
	
	-- return
	return self
end

-- if humanoid exists and health is > 0
function KnifeHandler:isHumanoidAlive() : boolean 
	return self.humanoid and self.humanoid.Health > 0
end

-- Check the player can throw a knife
function KnifeHandler:canThrow() : boolean
	return self:isHumanoidAlive() and self.equipped and self.ammo > 0 and not self.isSwinging and not self.isReloading and self.isCharging
end

-- Check if player can slash the knife
function KnifeHandler:canSlash() : boolean
	return self:isHumanoidAlive() and self.equipped and not self.isSwinging and not self.isReloading and not self.isCharging
end

-- Check if player can reload
function KnifeHandler:canReload() : boolean
	return self:isHumanoidAlive() and self.equipped and self.ammo <= 0 and not self.isReloading
end

-- Knife tool was equipped
function KnifeHandler:Equip()
	if self.equipped then
		return
	end
	
	-- Enable weapon animation handler
	self.animationHandler:Enable()
	
	-- Setting humaoid (incase we dont already have one)
	self.humanoid = self.knife.Parent:FindFirstChildOfClass("Humanoid")
	
	-- Equipping
	self.equipped = true
end

-- Knife tool was unequipped
function KnifeHandler:Unequip()
	-- Equipped
	if not self.equipped then
		return
	end
	
	-- If charge task is active, disable
	if self.chargeTask then
		task.cancel(self.chargeTask)
		self.chargeTask = nil
	end
	
	-- Disable weapon animation handler
	self.animationHandler:Disable()
	
	-- Reset flags
	self.isActive = false
	self.isCharging = false
	self.isSwinging = false
	
	-- Unequip
	self.equipped = false
end

-- User activated tool
function KnifeHandler:Activated()
	if self.isSwinging or self.isCharging or self.isReloading then return end
	
	-- Inputs
	self.holdStartTime = workspace:GetServerTimeNow()
	self.isActive = true

	-- Schedule charge check
	self.chargeTask = task.delay(self.stats.holdTime, function()
		if self.ammo > 0 then
			self.isCharging = true
			
			-- Charge begun, start animation
			self.animationHandler:PlayCharge(self.stats.chargeTime)
		end
	end)
end

-- User released activation on tool
function KnifeHandler:Deactivated()
	-- If activation wasn't succesful return
	if not self.isActive then return end
	
	-- Holding
	self.isActive = false
	local holdTime = workspace:GetServerTimeNow() - self.holdStartTime
	self.holdStartTime = nil
	
	-- Cancel pending charge task
	if self.chargeTask then
		task.cancel(self.chargeTask)
		self.chargeTask = nil
	end
	
	-- Decide slash or throw
	self:AttemptAttack(holdTime)
end

-- Attempt attack
function KnifeHandler:AttemptAttack(holdTime: number)
	-- Check if you can throw
	if self:canThrow() then
		self.isCharging = false
		self:Throw(holdTime)
		
		if self.ammo <= 0 then
			self:Reload()
			print("Reloading started")
		end
	-- Else if possible slash instead
	elseif self:canSlash() then
		self:Slash()
	end
end

-- Knife was slashed
function KnifeHandler:Slash()
	print("Slash executed")
	self.animationHandler:PlaySlash()
end

-- Knife was thrown
function KnifeHandler:Throw(holdTime : number) 
	
	-- Play throw animation
	self.animationHandler:PlayThrow()
	
	-- Time fired
	local now = workspace:GetServerTimeNow()
	
	-- Spread info
	local spread = self.stats.projectileSpread
	local raysPerShot = self.stats.projectilesPerShot
	
	-- Get projectile stats to pass in
	local origin = self.knife.Handle.Position
	local aimCFrame = getAimDirection(origin)
	local directions = getProjectileDirection(aimCFrame, raysPerShot, math.rad(spread), now)
	
	-- For every direction create a projectile
	for _,projectileDir:Vector3 in directions do
		-- Velocity vector
		local velocity = getKnifeVelocity(holdTime, self.stats, projectileDir)
		-- Create a projectile object
		local projectile = ProjectileHandler.new(origin, velocity, self.stats, self.knife.Parent)
		-- Associate the projectile with a visual projectile
		local visual = ProjectileVisual.new(projectile, self.knife.Handle)
		-- Start the visual projectile setup (must be done before firing)
		visual:Start()
		-- Fire the projectile
		projectile:Fire()
	end
	
	-- Remove 1 ammo
	self.ammo -= 1
end

-- Reloading
function KnifeHandler:Reload()
	-- Check if we can reload (Our system only wants us to reload when we have 0 knives, reloading is automatic)
	
	-- Set transparent for reloading
	self.knife.Handle.Transparency = 1
	
	-- reload stats
	local reloadTime = self.stats.reloadTime
	local magazineSize = self.stats.magazineSize
	
	-- set reloading
	self.isReloading = true
	
	-- Fire reload event
	-- ????????????????
	
	-- Reload task
	self.reloadTask = task.delay(reloadTime, function()
		-- Ammo/Tasks
		self.ammo = magazineSize
		self.isReloading = false
		self.reloadTask = nil
		
		-- Set visible
		self.knife.Handle.Transparency = 0
		print("Reload finished")
	end)
end

-- Upon creation
function KnifeHandler:Init()
	
	-- Equipped tool
	table.insert(
		self.connections,
		self.knife.Equipped:Connect(function()
			self:Equip()
		end)
	)
	
	-- Unequipped tool
	table.insert(
		self.connections,
		self.knife.Unequipped:Connect(function()
			self:Unequip()
		end)
	)
	
	-- Activated tool, start throw/slash checks
	table.insert(
		self.connections,
		self.knife.Activated:Connect(function()
			self:Activated()
		end)
	)
	
	-- Deactivated tool, initiate attack
	table.insert(
		self.connections,
		self.knife.Deactivated:Connect(function()
			self:Deactivated()
		end)
	)
end

-- Cleanup on removal
function KnifeHandler:Cleanup()
	-- Clear connections
	disconnectAndClear(self.connections)
	
	-- Clean up animations
	self.animationHandler:Cleanup()
end

-- returning
return KnifeHandler

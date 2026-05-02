------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------- DEAR HIDDEN DEV APPLICATION READER -----------------------------------------------
-- I shared multiple scripts with you, please read all comments shared and provide feedback on which part you don't
-- think it shows my understanding of the code, if you think so, so i can focus explaining more on there
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

-- Initialization

local IceRinkServer = {}
local PlayerStateService = require(script:WaitForChild("PlayerStateService"))

-- Services
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local MapsFolder        = ServerStorage:WaitForChild("MapsFolder")
local ItemsFolder       = ServerStorage:WaitForChild("Items")

-- Read every skate pairs and hold them in server memory on load. This is essential because characters wear these skates before entering the arena and we dont want to search and find skate pairs everytime a
-- character tries to enter the arena.
local ItemRegistry = {}
for _, itemFolder in ipairs(ItemsFolder:GetChildren()) do
	if itemFolder:IsA("Folder") then
		ItemRegistry[itemFolder.Name] = {
			Left = itemFolder:WaitForChild("L"),
			Right = itemFolder:WaitForChild("R")
		}
	end
end

-- Workspace Parts
local Workspace         = game:GetService("Workspace")
local Map 				= Workspace:WaitForChild("Map")
local CurrentMap        = Map:WaitForChild("CurrentMap")
local Lobby             = Map:WaitForChild("Lobby")
local Portal            = Lobby:WaitForChild("Portal")
local SpawnLocation     = Lobby:WaitForChild("SpawnLocation")

local IceRinkFolder     = MapsFolder:WaitForChild("IceRinkFolder")
local MountainFolder    = MapsFolder:WaitForChild("MountainFolder")
local CurrentMapName        = "Mountain"
--[[task.spawn(function()
	while true do
		if CurrentMapName == "IceRink" then
			MountainFolder.Parent = Workspace
			IceRinkFolder.Parent = MapsFolder
			CurrentMapName = "Mountain"
		elseif CurrentMapName == "Mountain" then
			MountainFolder.Parent = MapsFolder
			IceRinkFolder.Parent = Workspace
			CurrentMapName = "IceRink"
		end
		task.wait(100)
	end
end)]]
local TeleportLocation  = IceRinkFolder:WaitForChild("TeleportLocation")

-- Remote Events
local Remotes            = ReplicatedStorage:WaitForChild("IceRinkRemotes")
local PortalEffectRE     = Remotes:WaitForChild("PortalEffect")
local SkatesEquippedRE   = Remotes:WaitForChild("SkatesEquipped")
local SkatesRemovedRE    = Remotes:WaitForChild("SkatesRemoved")
local BumpAttackerRE     = Remotes:WaitForChild("BumpAttacker")
local BumpVictimRE       = Remotes:WaitForChild("BumpVictim")
local SetSkateCFGRE      = Remotes:WaitForChild("SetSkateCFG")
local KillFeedEvent      = Remotes:WaitForChild("KillFeedEvent")
local DamageIndicatorEvent = ReplicatedStorage:WaitForChild("DamageIndicatorEvent")
local CoinReceiveSFXEvent  = ReplicatedStorage:WaitForChild("CoinReceiveSFXEvent")
local DashAbilityEvent = ReplicatedStorage:WaitForChild("DashAbilityEvent")

-- hitbox class framework implementation
local HitboxClass = require(ReplicatedStorage.HitboxClass)
local HitboxTypes = require(ReplicatedStorage.HitboxClass.Types)

-- Config
local CFG = {
	TELEPORT_DEBOUNCE  = 2,     -- seconds before a player can re-enter the portal
	VOID_Y_THRESHOLD   = -50,   -- Y below which player is considered in the void
	BUMP_THRESHOLD     = 18,    -- minimum speed (studs/s) to trigger a bump
	BUMP_LAUNCH_SPEED  = 65,   -- impulse applied to the hit player
	BUMP_LAUNCH_UP     = 60,    -- upward component of the launch
	STUN_DURATION      = 2,     -- seconds a hit player is stunned
	BUMP_DAMAGE        = 20,    -- HP taken by the hit player
	ICE_FRICTION       = 0.01,  -- near-zero surface friction on the rink
	RESPAWN_HEIGHT     = 5,     -- studs above SpawnLocation to place the character

	KILL_REWARD        = 5,
}


-- store the recent player who attacked at for each player to later award the attacker
local lastAttacker = {}

-- vfx for dash ability
local VFXAttachment = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("DashVFX"):WaitForChild("VFXRootAttachment")

local playerData = {}
local function getData(player)
	return playerData[player]
end

local function getCoins(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Coins")
end
local function getKills(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Kills")
end

-- set ice rink physics
local iceProps = PhysicalProperties.new(
	CFG.ICE_FRICTION,
	0.1,
	0.01,
	0.1,
	0.01
)

for _,i in pairs(IceRinkFolder:GetChildren()) do
	if i:IsA("BasePart") then 
		i.CustomPhysicalProperties = iceProps
		i.TopSurface    = Enum.SurfaceType.Smooth
		i.BottomSurface = Enum.SurfaceType.Smooth
	end
end
for _,i in pairs(MountainFolder:GetChildren()) do
	if i:IsA("BasePart") then 
		i.CustomPhysicalProperties = iceProps
		i.TopSurface    = Enum.SurfaceType.Smooth
		i.BottomSurface = Enum.SurfaceType.Smooth
	end
end

-- equip given skate accessories to character. this is only visual, it has no effect on gameplay
local function equipSkates(character, itemName)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local itemData = ItemRegistry[itemName]
	if not humanoid then return end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and
			(child.Name == "LeftSkate" or child.Name == "RightSkate") then
			child:Destroy()
		end
	end

	local leftClone = itemData.Left:Clone()
	leftClone.Name = "LeftSkate"
	
	local rightClone = itemData.Right:Clone()
	rightClone.Name = "RightSkate"
	
	humanoid:AddAccessory(leftClone)
	humanoid:AddAccessory(rightClone)
end

-- remove equipped skate accessories. this is only visual, it has no effect on gameplay
local function removeSkates(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and
			(child.Name == "LeftSkate" or child.Name == "RightSkate") then
			child:Destroy()
		end
	end
end


-- handle spawn and reset certain stats on death
local respawning = {}

local function respawnAtLobby(player)
	if respawning[player] then return end
	respawning[player] = true

	local data = getData(player)
	if data then
		data.onIce   = false
		data.stunned = false
	end

	local character = player.Character
	if character then
		removeSkates(character)
	end

	SkatesRemovedRE:FireClient(player)

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end

	task.spawn(function()
		local newChar = player.CharacterAdded:Wait()
		task.wait(0.15)
		local hrp = newChar:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = SpawnLocation.CFrame + Vector3.new(0, CFG.RESPAWN_HEIGHT, 0)
		end
		respawning[player] = nil
	end)
end

-- teleport the character to ice rink and set stats for pvp arena. flag the player so it can start pvp fight. this is essential to split lobby and pvp arena logic and later will be 
-- extended to achieve spawn protection.
local function teleportToRink(player)
	local data = getData(player)
	if not data or data.teleportCooldown then return end

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.HipHeight = 2.95
	data.teleportCooldown = true
	task.delay(CFG.TELEPORT_DEBOUNCE, function()
		local d = getData(player)
		if d then d.teleportCooldown = false end
	end)
	local clone = VFXAttachment:Clone()
	clone.Parent = hrp
	
	PortalEffectRE:FireClient(player)
	task.wait(0.45)

	hrp.CFrame = TeleportLocation.CFrame + Vector3.new(0, 3, 0)
	data.onIce = true
	SkatesEquippedRE:FireClient(player, player.playerData.equippedItem.Value)
	
	
	equipSkates(player.Character, tostring(player.playerData.equippedItem.Value))
end

-- set certain stats for ice rink.
-- handle humanoid.died for rewarding the last attacker. if a character dies by any means, the last player who attacked is accountable.
function IceRinkServer.onPlayerAdded(player)
	playerData[player] = {
		onIce            = false,
		stunned          = false,
		teleportCooldown = false,
		bumpCooldown     = false,
	}

	local function setupCharacter(character)
		local data = getData(player)
		if data then
			data.onIce   = false
			data.stunned = false
		end

		local humanoid = character:WaitForChild("Humanoid")
		character.Parent = workspace.Alive

		humanoid.Died:Connect(function()
			local attacker = lastAttacker[player]
			print(attacker)
			if attacker and attacker ~= player and attacker.Parent then
				local coins = getCoins(attacker)
				if coins then
					coins.Value = coins.Value + CFG.KILL_REWARD
					CoinReceiveSFXEvent:FireClient(attacker)
				end
				local kills = getKills(attacker)
				if kills then
					kills.Value = kills.Value + 1
				end
				KillFeedEvent:FireAllClients(attacker.Name, player.Name, CFG.KILL_REWARD)
			end
			lastAttacker[player] = nil
			task.wait(0.1)
			respawnAtLobby(player)
		end)
	end

	if player.Character then
		setupCharacter(player.Character)
	end

	player.CharacterAdded:Connect(setupCharacter)

	player.CharacterRemoving:Connect(function()
		local data = getData(player)
		if data then
			data.onIce   = false
			data.stunned = false
		end
	end)
end

-- Portal teleports the players to ice rink
Portal.Touched:Connect(function(part)
	local character = part.Parent
	local player    = Players:GetPlayerFromCharacter(character)
	if player then
		teleportToRink(player)
	end
end)

-- safety check for characters who might pass hazard under arena
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if respawning[player] then continue end
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp.Position.Y < CFG.VOID_Y_THRESHOLD then
			respawnAtLobby(player)
		end
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	IceRinkServer.onPlayerAdded(player)
end

local AttackEvent = ReplicatedStorage:WaitForChild("AttackEvent")

-- Players who are teleported to the arena can fire this event if they're not stunned. A hitbox is created attached and in front of the character for a small duration covering the attack animation.
-- If hit is successful, the character who got hit launches towards opposite direction of the character who hit, got stunned and damaged. The lastAttacker property for who got hit becomes the player who hit for later use.
AttackEvent.OnServerEvent:Connect(function(player, clientFootPos)
	local hitboxParams = {
		SizeOrPart = Vector3.new(7, 6, 6),
		SpatialOption = "InBox",
		Blacklist = { player.Character },
		DebounceTime = 1,
		Debris = 0.14,
		Debug = false,
	} :: HitboxTypes.HitboxParams

	local newHitbox, _ = HitboxClass.new(hitboxParams)
	newHitbox:WeldTo(player.Character.HumanoidRootPart, CFrame.new(0, 0, -2))
	newHitbox.HitSomeone:Connect(function(hitChars)
		for _, hitChar in pairs(hitChars) do
			local otherPlayer = Players:GetPlayerFromCharacter(hitChar)
			local otherData = getData(otherPlayer)
			local otherHum  = hitChar:FindFirstChildOfClass("Humanoid")
			local otherHRP  = hitChar:FindFirstChild("HumanoidRootPart")
			if otherData and otherHRP and otherHum then
				if otherData.stunned or not otherData.onIce then continue end

				lastAttacker[otherPlayer] = player

				local diff = otherHRP.Position - player.Character.HumanoidRootPart.Position
				local launchDir = if diff.Magnitude > 0.01
					then Vector3.new(diff.X, 0, diff.Z).Unit
					else player.Character.CFrame.LookVector * Vector3.new(1, 0, 1)
				local launchVelocity = launchDir * CFG.BUMP_LAUNCH_SPEED + Vector3.new(0, CFG.BUMP_LAUNCH_UP, 0)

				otherData.stunned = true
				otherHum:TakeDamage(CFG.BUMP_DAMAGE)
				otherHum.PlatformStand = true
				otherHum.WalkSpeed = 0
				otherHum.JumpPower = 0
				
				DamageIndicatorEvent:FireAllClients(otherPlayer, CFG.BUMP_DAMAGE)

				BumpVictimRE:FireClient(otherPlayer, CFG.STUN_DURATION)
				otherHRP:SetNetworkOwner(nil)
				--otherHRP.AssemblyLinearVelocity = launchVelocity
				otherHRP:ApplyImpulse(launchVelocity*7)
				PlayerStateService:SwitchState(otherPlayer, "Stunned")
				task.delay(CFG.STUN_DURATION, function()
					PlayerStateService:SwitchState(otherPlayer, "Idle")

					if not otherHRP then return end
					otherHRP:SetNetworkOwner(otherPlayer)
					otherData.stunned = false
					if otherHum and otherHum.Parent then
						otherHum.WalkSpeed = 16
						otherHum.JumpPower = 50
						otherHum.PlatformStand = false
					end
				end)
			end
		end
	end)
	newHitbox:Start()
end)

-- clean-up unnecessary data for server efficiency
local function onPlayerRemoving(player)
	playerData[player] = nil
	respawning[player] = nil
	lastAttacker[player] = nil
	lastAttackTimes[player.UserId] = nil
	
	for victim, attacker in pairs(lastAttacker) do
		if attacker == player then
			lastAttacker[victim] = nil
		end
	end
end

-- Players who are teleported to the arena can fire this event if they're not stunned. If the player is verified for dash, it then fires back to the client and get carried there towards camera's look direction.
-- This could be done here in the server but since movement is already synced with proper Network Owner settings i didn't want to exhaust server. Also this way we provide the client instant feedback which is
-- important for gameplay feel.
DashAbilityEvent.OnServerEvent:Connect(function(player)
	local data = getData(player)
	if not data then
		print("no data")
		return
	elseif not data.onIce then
		print("not on ice")
		return
	end
	PlayerStateService:SwitchState(player, "Dash")
	task.spawn(function()
		task.wait(0.2)
		PlayerStateService:SwitchState(player, "Idle")
	end)
end)

-- this is a module script gets required from a server script and its onPlayerAdded method is being called there. thats why i later commented out the below code line.

--Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)


return IceRinkServer
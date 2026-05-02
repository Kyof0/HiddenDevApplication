------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
------------------------------------- DEAR HIDDEN DEV APPLICATION READER -----------------------------------------------
-- I shared multiple scripts with you, please read all comments shared and provide feedback on which part you don't
-- think it shows my understanding of the code, if you think so, so i can focus explaining more on there
------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

-- Initialization

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local PremiumPassID = 1797767026

local ShopItems = ReplicatedStorage:WaitForChild("ShopItems")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local LoadShopItemsEvent = RemoteEvents:WaitForChild("LoadShopItemsEvent")
local LoadOwnedItemsEvent = RemoteEvents:WaitForChild("LoadOwnedItemsEvent")
local EquipItemEvent = RemoteEvents:WaitForChild("EquipItemEvent")
local EquipItemRF = RemoteEvents:WaitForChild("EquipItemRF")
local BuyItemRF = RemoteEvents:WaitForChild("BuyItemRF")

local IceSkateShopServiceServer = {}

-- Invokes when a player tries to buy skate in the shop. First checks if the item is valid and then checks if the player already owns the item. Players cant interact with buy button on client if the item is owned 
-- already but it is important to secure the database from any exploits. Then it checks if the player has enough coins and returns true after reducing the coins for the player.
BuyItemRF.OnServerInvoke = function(player, itemName)
	local item = ShopItems:FindFirstChild(itemName)
	if not item then return false end
	if not player.playerData.ownedItems:FindFirstChild(itemName) then
		if player.leaderstats.Coins.Value >= ShopItems[itemName].Price.Value then
			player.leaderstats.Coins.Value -= ShopItems[itemName].Price.Value
			local newItemID = Instance.new("IntValue")
			newItemID.Name = itemName
			newItemID.Parent = player.playerData.ownedItems
			newItemID.Value = tonumber(itemName)
			--IceSkateShopServiceServer.SyncOwnedItems(player)
			return true
		end
	end
	return false
end

-- Invokes when a player tries to equip a skate in the shop. It checks if the player has the item and returns the result. The item name is just an id every skate has. Equipped item property is being hold
-- on server for each player. When a player tries to enter PVP Arena, its character wears the skate pairs matching with the equipped item id and its linear velocity component being adjusted according
-- to what skates attributes are on client side.
EquipItemRF.OnServerInvoke = function(player, itemName)
	if player.playerData.ownedItems:FindFirstChild(itemName) or itemName == "0" then
		player.playerData.equippedItem.Value = tonumber(itemName)
		return true
	end
	return false
end

-- This function gives the player all skates other than 0 and 9999. 0 is the default skate everybody already has. I dont save it in database because nobody has a chance not to have that skate so its going to
-- be a waste of storage. Skates named 9999 are just placeholders in the shop to show more skates are on the way.
function IceSkateShopServiceServer.BuyAllItems(player)
	for i, item in pairs(ShopItems:GetChildren()) do
		if item.Name == "0" or item.Name == "9999" then continue end
		if not player.playerData.ownedItems:FindFirstChild(item.Name) then
			local newItemID = Instance.new("IntValue")
			newItemID.Name = item.Name
			newItemID.Parent = player.playerData.ownedItems
			newItemID.Value = tonumber(item.Name)
		end
	end
	IceSkateShopServiceServer.SyncOwnedItems(player)
end

-- Handles on player added logic. First sends the player all available shop items, then sends the item list that player owns so client can update the shop. It then checks if the player owns premium game pass.
-- If true, BuyAllItems got called for the player. Even tho BuyAllItems gets called after the premium game pass purchase is done we still need this safety check for a couple of reasons. The purchase could 
-- have been done outside of the game, the purchase callback might not work, we promise players current and future skates.
function IceSkateShopServiceServer.onPlayerAdded(player)
	
	LoadShopItemsEvent:FireClient(player, ShopItems)
	task.spawn(function()
		
		local playerData = player:WaitForChild("playerData", 10)
		if not playerData then return warn("PlayerData failed to load for " .. player.Name) end

		local equippedItem = playerData:WaitForChild("equippedItem")

		IceSkateShopServiceServer.SyncOwnedItems(player)
		
		local equipped = tostring(equippedItem.Value)
		EquipItemEvent:FireClient(player, equipped)
	end)
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, PremiumPassID)
	end)

	if success then
		if hasPass then
			print(player.Name .. " owns the gamepass!")
			
			IceSkateShopServiceServer.BuyAllItems(player)
		else
			print(player.Name .. " does not own the gamepass.")
		end
	else
		warn("Error checking gamepass for " .. player.Name)
	end
end

-- sends the player owned items so client can update its shop.
function IceSkateShopServiceServer.SyncOwnedItems(player)
	local ownedItems = {}
	for i, item in pairs(player.playerData.ownedItems:GetChildren()) do
		table.insert(ownedItems, item)
	end
	LoadOwnedItemsEvent:FireClient(player, ownedItems)
end
function IceSkateShopServiceServer.Init()

end

return IceSkateShopServiceServer
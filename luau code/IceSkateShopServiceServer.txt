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
EquipItemRF.OnServerInvoke = function(player, itemName)
	if player.playerData.ownedItems:FindFirstChild(itemName) or itemName == "0" then
		player.playerData.equippedItem.Value = tonumber(itemName)
		return true
	end
	return false
end
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
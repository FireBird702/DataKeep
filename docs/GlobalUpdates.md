---
sidebar_position: 5
---

# Global Updates

The following example shows how you would handle global updates:

```lua title="DataTemplate.luau"
local dataTemplate = {
	Coins = 0,
}

export type template = typeof(dataTemplate)

return table.freeze(dataTemplate)
```

```lua title="GlobalUpdateDataType.luau"
export type globalUpdateData = {
	Type: "Coins",
	Coins: number,
} | {
	Type: "Gems", -- something else as an example to show type checking
	Gems: number,
}

return nil
```

```lua title="Main.luau"
local Players = game:GetService("Players")

local DataKeep = require(path_to_datakeep)
local DataTemplate = require(path_to_datatemplate)
local GlobalUpdateDataType = require(path_to_global_update_data_type)

local loadedKeeps = {}

local store = DataKeep.GetStore("PlayerData", DataTemplate):expect()

local function onPlayerAdded(player: Player)
	store:LoadKeep(`Player_{player.UserId}`):andThen(function(keep)
		keep:Reconcile()
		keep:AddUserId(player.UserId) -- help with GDPR requests

		keep.Released:Connect(function()
			print(`{player.Name}'s Keep has been released!`)

			loadedKeeps[player] = nil
			player:Kick("Session released!")
		end)

		keep.ReleaseFailed:Connect(function()
			print(`Failed to release {player.Name}'s Keep!`)

			loadedKeeps[player] = nil
			player:Kick("Failed to release session!")
		end)

		if not player:IsDescendantOf(Players) then
			keep:Release():catch(function() end)
			return
		end

		local function processGlobalUpdate(globalUpdateData: GlobalUpdateDataType.globalUpdateData, globalUpdateId: number)
			if not (globalUpdateData.Type == "Coins") then
				return
			end

			keep:ClearLockedUpdate(globalUpdateId):andThen(function()
				-- clear locked update first and then apply changes

				keep.Data.Coins += globalUpdateData.Coins
			end):catch(function(err)
				print(`Failed to clear locked update ({globalUpdateId}): {err}`)
			end):await()
		end

		-- process already locked global updates
		for _, globalUpdate in keep:GetLockedGlobalUpdates() do
			processGlobalUpdate(globalUpdate.Data, globalUpdate.Id)
		end

		-- listen for new locked global updates
		keep.OnGlobalUpdate:Connect(processGlobalUpdate)

		loadedKeeps[player] = keep

		print(`Loaded {player.Name}'s Keep!`)
	end):catch(function()
		player:Kick("Data failed to load")
	end)
end

-- loop through already connected players in case they joined before DataKeep loaded
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local keep = loadedKeeps[player]

	if not keep then
		return
	end

	keep:Release():catch(function() end)
end)
```

```lua title="GiftingExample.luau"
-- Offline / from different server gifting example

local Players = game:GetService("Players")

local DataKeep = require(path_to_datakeep)
local DataTemplate = require(path_to_datatemplate)
local GlobalUpdateDataType = require(path_to_global_update_data_type)

local store = DataKeep.GetStore("PlayerData", DataTemplate):expect()

local coinsToAdd = 100

store:PostGlobalUpdate(`Player_[UserId]`, function(globalUpdates)
	for _, globalUpdate: DataKeep.GlobalUpdate<GlobalUpdateDataType.globalUpdateData> in globalUpdates:GetActiveUpdates() do
		if not (globalUpdate.Data.Type == "Coins") then
			continue
		end

		globalUpdate.Data.Coins += coinsToAdd
		globalUpdates:ChangeActiveUpdate(globalUpdate.Id, globalUpdate):expect()
		return
	end

	-- active update not found, add a new one
	globalUpdates:AddGlobalUpdate({
		Type = "Coins",
		Coins = coinsToAdd,
	}):expect()
end)
```

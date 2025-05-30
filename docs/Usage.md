---
sidebar_position: 3
---

# Usage

## Basic Approach

DataKeep will lift everything, the only thing you need to do is load data. DataKeep does not use getter / setter functions allowing for customizable experience like, make your own wrapper.

The following is a very basic Keep loader implementation.

```lua
local Players = game:GetService("Players")

local DataKeep = require(path_to_datakeep)

local dataTemplate = {
	Coins = 0,
}

local loadedKeeps = {}

local store = DataKeep.GetStore("PlayerData", dataTemplate):expect()

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

		loadedKeeps[player] = keep

		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"

		local coins = Instance.new("NumberValue")
		coins.Name = "Coins"
		coins.Value = keep.Data.Coins
		coins.Parent = leaderstats

		leaderstats.Parent = player

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

## Class Approach

For more experienced developers I personally opt in to create a service that returns a "Player" OOP class that holds it own cleaner and a Keep inside.

Note: "attributes" and "leaderstats" are folders in the script parent which contains numberValues / stringValues / boolValues

```lua
--> Services

local Players = game:GetService("Players")

--> Includes

local DataKeep = require(path_to_datakeep)
local DataTemplate = require(path_to_datatemplate)

--> Module Definition

local Player = {}
Player.__index = Player

--> Variables

local store = DataKeep.GetStore("PlayerData", DataTemplate):expect()

--> Private Functions

local function initKeep(playerClass, keep)
	local player = playerClass.Player

	-- attributes & leaderstats

	local attributes = Instance.new("Folder")
	attributes.Name = "attributes"
	attributes.Parent = player

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local function bindData(value, parent) -- leaderstats or attributes
		local doesExist = keep.Data[value.Name]

		if not doesExist then
			return
		end

		value = value:Clone()

		value.Value = keep.Data[value.Name]

		value:GetPropertyChangedSignal("Value"):Connect(function() -- should clean on value destroy
			keep.Data[value.Name] = value.Value
		end)

		value.Parent = parent

		playerClass._keys[value.Name] = value
	end

    -- "attributes" and "leaderstats" are folders in the script parent
	-- which contains numberValues / stringValues / boolValues

	for _, attribute in script.Parent.attributes:GetChildren() do
		bindData(attribute, attributes)
	end

	for _, leaderstat in script.Parent.leaderstats:GetChildren() do
		bindData(leaderstat, leaderstats)
	end

	-- listen for globals
end

local function loadKeep(playerClass)
	local player = playerClass.Player

	local keepPromise = store:LoadKeep(`Player_{player.UserId}`)

	keepPromise:andThen(function(keep)
		keep:Reconcile()
		keep:AddUserId(player.UserId) -- help with GDPR requests

		keep.Released:Connect(function()
			print(`{player.Name}'s Keep has been released!`)

			playerClass:Destroy()
			player:Kick("Session released!")
		end)

		keep.ReleaseFailed:Connect(function()
			print(`Failed to release {player.Name}'s Keep!`)

			playerClass:Destroy()
			player:Kick("Failed to release session!")
		end)

		if not player:IsDescendantOf(Players) then
			playerClass:Destroy()
			return
		end

		initKeep(playerClass, keep)
	end):catch(function()
		player:Kick("Data failed to load")
	end)

	return keepPromise -- so they can attach to the promise
end

--> Constructor

function Player.new(player: Player)
	local self = setmetatable({
		Player = player,

		Keep = nil,

		_keys = {}, -- stored attribute / leaderstats keys for changing to automatically change the datakeep. **MUST USE THESE FOR ANY ATTRIBUTES / LEADERSTATS BINDED**
	}, Player)

	self.Keep = loadKeep(self)

	return self
end

--> Public Methods

function Player:GetKey(keyName: string)
	return self._keys[keyName]
end

function Player:GetData(key: string)
	local keep = self.Keep:expect()
	return keep.Data[key]
end

function Player:Destroy()
	-- do cleaning, this should generally include releasing the keep

	if self._destroyed then
		return
	end

	self._destroyed = true

	if self.Keep then
		local keep = self.Keep:expect()
		keep:Release():catch(function() end)
	end
end

return Player
```

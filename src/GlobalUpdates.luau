--!strict

local DeepCopy = require(script.Parent.Utils.DeepCopy)
local Message = require(script.Parent.Utils.Message)
local Promise = require(script.Parent.Parent.Promise)
local PromiseTypes = require(script.Parent.PromiseTypes)
local Types = require(script.Parent.Types)

--> Structure

local GlobalUpdates = {}
GlobalUpdates.__index = GlobalUpdates

--> Types

--[=[
	@class GlobalUpdates
	@server

	Used to add, lock and change global updates.

	Revealed through [:PostGlobalUpdate()](Store#PostGlobalUpdate).
]=]

--> Public Methods

--[=[
	@method AddGlobalUpdate
	@within GlobalUpdates

	@param globalUpdateData any

	@return Promise<number>

	Adds a global update to the Keep.

	```lua
	store:PostGlobalUpdate(function(globalUpdates)
		globalUpdates:AddGlobalUpdate({
			Hello = "World!",
		}):andThen(function(updateId)
			print("Added Global Update!", updateId)
		end)
	end)
	```
]=]

function GlobalUpdates.AddGlobalUpdate<T>(self: Types.globalUpdatesClass<T>, globalUpdateData: Types.globalUpdateData<T>): PromiseTypes.TypedPromise<number>
	return Promise.new(function(resolve)
		local globalUpdates = self._updates

		local updateId: number = globalUpdates.Id
		updateId += 1

		globalUpdates.Id = updateId

		table.insert(globalUpdates.Updates, {
			Id = updateId,
			Locked = false,
			Data = globalUpdateData,
		})

		return resolve(updateId)
	end)
end

--[=[
	@method ChangeActiveUpdate
	@within GlobalUpdates

	@param updateId number
	@param globalUpdateData any

	@return Promise<()>

	Change an **active** global update's data to the new data.

	Useful for stacking updates to save space for Keeps that maybe receiving lots of globals. Ex. a content creator receiving gifts.
]=]

function GlobalUpdates.ChangeActiveUpdate<T>(self: Types.globalUpdatesClass<T>, updateId: number, globalUpdateData: Types.globalUpdateData<T>): PromiseTypes.TypedPromise<()>
	return Promise.new(function(resolve)
		if not updateId or not (typeof(updateId) == "number") then
			error(Message.new("updateId is not a number"))
		end

		local globalUpdates = self._updates

		if globalUpdates.Id < updateId then
			error(Message.new("Invalid update id"))
		end

		for _, update in globalUpdates.Updates do
			if update.Id == updateId and not update.Locked then
				update.Data = globalUpdateData

				return resolve()
			end
		end

		error(Message.new("This global update is locked"))
	end)
end

--[=[
	@method RemoveActiveUpdate
	@within GlobalUpdates

	@param updateId number

	@return Promise<()>

	Removes an active global update.

	```lua
	local updates = globalUpdates:GetActiveUpdates()

	for _, update in updates do
		globalUpdates:RemoveActiveUpdate(update.Id):andThen(function()
			print("Removed Global Update!")
		end)
	end
	```
]=]

function GlobalUpdates.RemoveActiveUpdate<T>(self: Types.globalUpdatesClass<T>, updateId: number): PromiseTypes.TypedPromise<()>
	return Promise.new(function(resolve)
		if not updateId or not (typeof(updateId) == "number") then
			error(Message.new("updateId is not a number"))
		end

		local globalUpdates = self._updates

		if globalUpdates.Id < updateId then
			error(Message.new("Invalid update id"))
		end

		local globalUpdateIndex = nil

		for i = 1, #globalUpdates.Updates do
			if globalUpdates.Updates[i].Id == updateId then
				globalUpdateIndex = i
				break
			end
		end

		if globalUpdateIndex == nil then
			error(Message.new("Invalid update id"))
		end

		if globalUpdates.Updates[globalUpdateIndex].Locked then
			error(`Unable to remove {updateId} which is a locked update`)
		end

		-- instantly removes internally, unlike locked updates. This is because locked updates can still be deleted mid-processing
		table.remove(globalUpdates.Updates, globalUpdateIndex)
		return resolve()
	end)
end

--[=[
	@method GetActiveUpdates
	@within GlobalUpdates

	@return { GlobalUpdate }

	Returns all **active** global updates.

	```lua
	local updates = globalUpdates:GetActiveUpdates()

	for _, update in updates do
		print("ActiveUpdate data:", update.Data)
	end
	```
]=]

function GlobalUpdates.GetActiveUpdates<T>(self: Types.globalUpdatesClass<T>): { Types.globalUpdate<T> }
	local globalUpdates = self._updates

	local updates = {}

	for _, update in globalUpdates.Updates do
		if not update.Locked then
			table.insert(updates, update)
		end
	end

	return updates
end

--[[
	Define how to process active global update, by default just locks the global update (this is only ran if the Keep is online during saving).

	The function reveals the lock and remove global update function through the parameters.

	:::info
	This function will not run for global updates that are already locked. Use [:GetLockedGlobalUpdates()](Keep#GetLockedGlobalUpdates)

	Instead of changing this function, use global updates example
	:::

	:::warning
	**This function should not be used directly. It is used internally when processing global updates.**

	Updates **must** be locked eventually in order for [.OnGlobalUpdate](Keep#OnGlobalUpdate) to get fired.
	:::

	:::danger
	The lock and remove function revealed here are **NOT** the same as the ones in the Keep class, they are only for this function.
	:::
]]

function GlobalUpdates._globalUpdateProcessor(_globalUpdateData: Types.globalUpdateData, lock: () -> (), _remove: () -> ())
	-- by default just locks the global update

	lock()
end

function GlobalUpdates._processGlobalUpdates<T>(latestData: Types.keepStruct<T>, pendingActions: { pendingGlobalLocks: { number }, pendingGlobalLockRemoves: { number } }, globalUpdateProcessor: Types.globalUpdateProcessor, isReleasing: boolean)
	-- this handles full profiles and if there are only global updates (globals posted with never loaded)

	local finalGlobals = latestData.GlobalUpdates -- the final global updates to save
	local globalUpdates = finalGlobals.Updates -- do we deep copy here..?

	local function lockGlobalUpdate(index: number) -- we take index instead, why take updateId just to loop through? we aren't doing any removing, all removals are on locked globals and will be passed to .pendingGlobalLockRemoves
		return Promise.new(function(resolve)
			if table.find(pendingActions.pendingGlobalLocks, index) then
				return resolve()
			end

			table.insert(pendingActions.pendingGlobalLocks, index) -- locked queue
			return resolve()
		end)
	end

	local function removeLockedUpdate(index: number, updateId: number)
		return Promise.new(function(resolve)
			if globalUpdates[index].Id ~= updateId then -- shouldn't happen, but
				error(Message.new(`Failed to remove locked update: Invalid update id`))
			end

			if not globalUpdates[index].Locked and not pendingActions.pendingGlobalLocks[index] then
				error(Message.new(`Failed to remove locked update: Global update was not locked`))
			end

			if table.find(pendingActions.pendingGlobalLockRemoves, updateId) then
				return resolve()
			end

			table.insert(pendingActions.pendingGlobalLockRemoves, updateId) -- locked removal queue
			return resolve()
		end)
	end

	local recentlyLockedGlobalUpdates = {} -- list of locked GlobalUpdates for .OnGlobalUpdate

	if not isReleasing then
		-- do not lock global updates when keep is releasing

		local processUpdates = {}

		for i = 1, #globalUpdates do
			if globalUpdates[i].Locked then
				continue
			end

			globalUpdateProcessor(globalUpdates[i].Data, function()
				table.insert(processUpdates, function()
					lockGlobalUpdate(i)
				end)
			end, function()
				table.insert(processUpdates, function()
					removeLockedUpdate(i, globalUpdates[i].Id)
				end)
			end)
		end

		for _, updateProcessor in processUpdates do
			updateProcessor()
		end

		for _, update in finalGlobals.Updates do
			if update.Locked then
				continue
			end

			for _, pendingLock in pendingActions.pendingGlobalLocks do
				if not (pendingLock == update.Id) then
					continue
				end

				update.Locked = true

				table.insert(recentlyLockedGlobalUpdates, DeepCopy(update))
				break
			end
		end
	end

	for _, updateId in pendingActions.pendingGlobalLockRemoves do
		for i = 1, #finalGlobals.Updates do
			if finalGlobals.Updates[i].Id == updateId and finalGlobals.Updates[i].Locked then
				table.remove(finalGlobals.Updates, i)
				break
			end
		end
	end

	local pendingGlobalLocksLeft = {}

	for _, updateId in pendingActions.pendingGlobalLocks do
		if table.find(pendingActions.pendingGlobalLockRemoves, updateId) then
			continue
		end

		table.insert(pendingGlobalLocksLeft, updateId)
	end

	pendingActions.pendingGlobalLocks = pendingGlobalLocksLeft
	table.clear(pendingActions.pendingGlobalLockRemoves)

	latestData.GlobalUpdates = finalGlobals

	return {
		latestData = latestData,
		actions = pendingActions,
		recentlyLockedGlobalUpdates = recentlyLockedGlobalUpdates,
	}
end

return GlobalUpdates

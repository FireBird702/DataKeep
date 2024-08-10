--!strict

--> Includes

local MockStorePages = require(script.MockStorePages)
local deepCopy = require(script.Parent.deepCopy)

--> Structure

local MockStore = {}
MockStore.__index = MockStore

--> Constructor

function MockStore.new()
	return setmetatable({
		_data = {},
		_dataVersions = {},
	}, MockStore)
end

--> Types

export type MockStore = typeof(MockStore.new()) & {
	_data: any,
}

--> Private Functions

function didyield(f, ...)
	local finished = false
	local data

	coroutine.wrap(function(...)
		data = f(...)
		finished = true
	end)(...)

	return not finished, data
end

local function createNewVersion(self, key, data: any)
	if self._dataVersions[key] == nil then
		self._dataVersions[key] = {}
	end

	local versionData = {
		Version = #self._dataVersions[key] + 1,
		CreatedTime = os.time(),
		UpdatedTime = os.time(),
		Deleted = false,
	}

	table.insert(self._dataVersions[key], { versionData, deepCopy(data) })

	return versionData
end

--> Public Methods

function MockStore:GetAsync(key: string)
	return self._data[key]
end

function MockStore:SetAsync(key: string, value: any)
	self._data[key] = deepCopy(value)

	return createNewVersion(self, key, value)
end

function MockStore:UpdateAsync(key: string, callback: (any) -> any)
	local value = self._data[key]
	local yielded, newValue = didyield(callback, value)

	if yielded then
		error("UpdateAsync yielded!")
		return value
	end

	if not newValue then
		return value
	end

	local newVersion = self:SetAsync(key, newValue)
	return self._data[key], newVersion
end

function MockStore:ListVersionsAsync(key: string, sortDirection: Enum.SortDirection, minDate: number, maxDate: number, limit: number)
	limit = limit or 1

	local versions = self._dataVersions[key]

	if not versions then
		return MockStorePages({}, sortDirection == Enum.SortDirection.Ascending, limit)
	end

	local filteredVersions = {}

	for _, versionData in versions do
		local createdTime = versionData[1].CreatedTime

		minDate = minDate or 0
		maxDate = maxDate or math.huge

		if createdTime >= minDate and createdTime <= maxDate then
			table.insert(filteredVersions, 1, versionData[1])
		end
	end

	table.sort(filteredVersions, function(a, b)
		return a.CreatedTime < b.CreatedTime
	end)

	return MockStorePages(filteredVersions, sortDirection == Enum.SortDirection.Ascending, limit)
end

function MockStore:GetVersionAsync(key: string, version)
	local versions = self._dataVersions[key]

	if not versions then
		return
	end

	for _, versionData in versions do
		if versionData[1].Version == version then
			return versionData[2]
		end
	end

	return
end

return MockStore

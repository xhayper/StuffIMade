--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local function deepCopy<T>(orig: T): T
	local orig_type = type(orig)
	local copy
	if orig_type == "table" then
		copy = {}
		for orig_key, orig_value in next, orig :: any, nil do
			copy[deepCopy(orig_key)] = deepCopy(orig_value)
		end
		setmetatable(copy, deepCopy(getmetatable(orig :: any)))
	else -- number, string, boolean, etc
		copy = orig :: any
	end
	return (copy :: any) :: T
end

local function deepEq(tbl1: unknown, tbl2: unknown): boolean
	if tbl1 == tbl2 then
		return true
	elseif type(tbl1) == "table" and type(tbl2) == "table" then
		for key1, value1 in tbl1 :: any do
			local value2 = (tbl2 :: any)[key1]

			if value2 == nil then
				-- avoid the type call for missing keys in tbl2 by directly comparing with nil
				return false
			elseif value1 ~= value2 then
				if type(value1) == "table" and type(value2) == "table" then
					if not deepEq(value1, value2) then
						return false
					end
				else
					return false
				end
			end
		end

		-- check for missing keys in tbl1
		for key2, _ in tbl2 :: any do
			if (tbl1 :: any)[key2] == nil then
				return false
			end
		end

		return true
	end

	return false
end

type CacheStoreImpl = {
	__index: CacheStoreImpl,

	new: (name: string, scope: string?, options: DataStoreOptions?) -> CacheStore,

	Get: <T>(self: CacheStore, key: string, noCache: boolean?) -> T?,
	Set: (self: CacheStore, key: string, value: unknown) -> (),
	Delete: (self: CacheStore, key: string) -> (),

	RemoveKey: (self: CacheStore, key: string, fromStore: boolean?) -> (),

	RemoveOnSync: (self: CacheStore, key: string) -> (),
	CancelRemoveOnSync: (self: CacheStore, key: string) -> (),

	GetSortedAsync: (
		self: CacheStore,
		ascending: boolean,
		pagesize: number,
		minValue: number?,
		maxValue: number?
	) -> DataStorePages,

	Sync: (self: CacheStore, key: string?) -> (),

	Destroy: (self: CacheStore) -> (),

	__syncToDatastore: (self: CacheStore, key: string) -> (),
}

type CacheStoreProto = {
	__store: GlobalDataStore | OrderedDataStore,
	-- UnixTimestampMillis for updateTime
	-- cacheTime - keeps track of when cache is invalidated
	-- updateTime - the time when the data was updated
	__cachedData: {
		[string]: {
			data: unknown,
			updateTime: number,
			cacheTime: number,
			uploadedToDatastore: boolean,
			removeOnSync: boolean,
		},
	},
	__syncThread: thread,

	-- unit second
	CacheTimeout: number,
	SyncTime: number,
	StoreType: "Ordered" | "Global" | "Normal",

	Destroyed: boolean,
}
--& ({
--	StoreType: "Ordered",
--	__store: OrderedDataStore,
--} | {
--	StoreType: "Normal",
--	__store: GlobalDataStore,
--})

export type CacheStore = typeof(setmetatable({} :: CacheStoreProto, {} :: CacheStoreImpl))

local CacheStore = {}
CacheStore.__index = CacheStore

function CacheStore.new(
	name: string,
	scope: string?,
	storeType: ("Ordered" | "Global" | "Normal")?,
	options: DataStoreOptions?
): CacheStore
	local self = setmetatable({}, CacheStore) :: CacheStore

	self.__store = if storeType == "Ordered"
		then DataStoreService:GetOrderedDataStore(name, scope)
		else (if storeType == "Global"
			then DataStoreService:GetGlobalDataStore()
			else DataStoreService:GetDataStore(name, scope, options))

	self.__cachedData = {}

	self.Destroyed = false
	self.CacheTimeout = 10
	self.SyncTime = 10
	self.StoreType = storeType or "Normal"

	self.__syncThread = task.spawn(function()
		while task.wait(self.SyncTime) do
			self:Sync()
		end
	end)

	game:BindToClose(function()
		if self.Destroyed then
			return
		end

		task.cancel(self.__syncThread)
		self.__syncThread = nil :: any

		repeat
			local shouldContinue = false

			do
				for _, _ in self.__cachedData do
					shouldContinue = true
					break
				end
			end

			if not shouldContinue then
				break
			end

			for k, v in self.__cachedData do
				v.removeOnSync = true
				self.__cachedData[k] = v
			end

			self:Sync()

			do
				for _, _ in self.__cachedData do
					shouldContinue = true
					break
				end
			end

			if shouldContinue then
				task.wait(3)
			else
				break
			end
		until false

		self:Destroy()
	end)

	return self
end

function CacheStore.Get<T>(self: CacheStore, key: string, noCache: boolean?): T?
	if noCache then
		local _, data = pcall(function()
			return self.__store:GetAsync(key)
		end)

		return data :: T?
	end

	-- We return this if we ran out of budget to get the data... or if we can't fetch the data...
	local returnCachedData = deepCopy(self.__cachedData[key] and self.__cachedData[key].data :: T or nil)

	if
		not self.__cachedData[key]
		or (DateTime.now().UnixTimestampMillis - self.__cachedData[key].cacheTime >= self.CacheTimeout)
	then
		if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) then
			return returnCachedData
		end

		local dataExistBeforeGet = self.__cachedData[key] ~= nil

		local success, datastoreData, keyInfo: DataStoreKeyInfo? = pcall(function()
			return self.__store:GetAsync(key)
		end)

		-- We lose the race condition
		if dataExistBeforeGet ~= (self.__cachedData[key] ~= nil) then
			return
		end

		if not success then
			return returnCachedData
		end

		if self.__cachedData[key] and deepEq(datastoreData, self.__cachedData[key].data) then
			self.__cachedData[key].updateTime =
				math.min(if keyInfo then keyInfo.UpdatedTime else math.huge, self.__cachedData[key].updateTime)
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis

			if self.__cachedData[key].removeOnSync then
				self.__cachedData[key] = nil
			end

			return returnCachedData
		end

		-- Data is still fresh, keep it
		if keyInfo then
			if self.__cachedData[key] and self.__cachedData[key].updateTime >= keyInfo.UpdatedTime then
				self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis
				return returnCachedData
			else
				if self.__cachedData[key] and self.__cachedData[key].removeOnSync then
					self.__cachedData[key] = nil
				else
					self.__cachedData[key] = self.__cachedData[key] or {} :: any

					-- Data is not fresh, update it
					self.__cachedData[key].data = datastoreData
					self.__cachedData[key].updateTime = keyInfo.UpdatedTime
					self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis
					self.__cachedData[key].uploadedToDatastore = true
				end

				return deepCopy(datastoreData :: T?)
			end
		end
	end

	return returnCachedData
end

function CacheStore.Set(self: CacheStore, key: string, value: unknown): ()
	if self.__cachedData[key] and deepEq(self.__cachedData[key].data, value) then
		return
	end

	if self.StoreType == "Ordered" and typeof(value) ~= "number" then
		error("Ordered Store Type requires number value!")
	end

	self.__cachedData[key] = {
		data = value,
		updateTime = DateTime.now().UnixTimestampMillis,
		cacheTime = DateTime.now().UnixTimestampMillis,
		uploadedToDatastore = false,
		removeOnSync = false,
	}
end

function CacheStore.Delete(self: CacheStore, key: string): ()
	if self.__cachedData[key].data == nil then
		return
	end

	self.__cachedData[key] = {
		data = nil,
		updateTime = DateTime.now().UnixTimestampMillis,
		cacheTime = DateTime.now().UnixTimestampMillis,
		uploadedToDatastore = false,
		removeOnSync = false,
	}
end

-- TODO: Properly support RemoveKey
function CacheStore.RemoveKey(self: CacheStore, key: string, fromStore: boolean?)
	self.__cachedData[key] = nil

	if fromStore then
		pcall(function()
			self.__store:RemoveAsync(key)
		end)
	end
end

function CacheStore.RemoveOnSync(self: CacheStore, key: string): ()
	if not self.__cachedData[key] then
		return
	end

	self.__cachedData[key].removeOnSync = true
end

function CacheStore.CancelRemoveOnSync(self: CacheStore, key: string): ()
	if not self.__cachedData[key] then
		return
	end

	self.__cachedData[key].removeOnSync = false
end

function CacheStore.GetSortedAsync(
	self: CacheStore,
	ascending: boolean,
	pagesize: number,
	minValue: number?,
	maxValue: number?
): DataStorePages
	if self.StoreType ~= "Ordered" then
		error(`GetSortedAsync can't be run on {self.StoreType} datastore!`)
	end

	return (self.__store :: OrderedDataStore):GetSortedAsync(ascending, pagesize, minValue, maxValue) :: DataStorePages
end

function CacheStore.Sync(self: CacheStore, key: string?): ()
	if key then
		self:__syncToDatastore(key)
	else
		for k, v in self.__cachedData do
			if v.uploadedToDatastore then
				if v.removeOnSync then
					self.__cachedData[k] = nil
				end

				continue
			end

			if
				0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
				or 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
			then
				continue
			end

			self:__syncToDatastore(k)
		end
	end
end

function CacheStore.__syncToDatastore(self: CacheStore, key: string): ()
	if not self.__cachedData[key] then
		return
	end

	if self.__cachedData[key] and self.__cachedData[key].uploadedToDatastore then
		return
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) then
		-- can't sync cause out of quota to check if datastore have been updated before
		return
	end

	local success, datastoreData, keyInfo: DataStoreKeyInfo? = pcall(function()
		return self.__store:GetAsync(key)
	end)

	if self.__cachedData[key] == nil then
		return
	end

	if not success then
		-- Can't sync, we can't check if cache overridden yet
		return
	end

	if deepEq(datastoreData, self.__cachedData[key].data) then
		if self.__cachedData[key].removeOnSync then
			self.__cachedData[key] = nil
		else
			self.__cachedData[key].updateTime =
				math.min(if keyInfo then keyInfo.UpdatedTime else math.huge, self.__cachedData[key].updateTime)
			self.__cachedData[key].uploadedToDatastore = true
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis
		end
		return
	end

	if keyInfo then
		if keyInfo.UpdatedTime >= self.__cachedData[key].updateTime then
			if self.__cachedData[key].removeOnSync then
				self.__cachedData[key] = nil
			else
				self.__cachedData[key].uploadedToDatastore = true
				self.__cachedData[key].data = datastoreData
				self.__cachedData[key].updateTime = keyInfo.UpdatedTime
				self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis
			end
			return
		end
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) then
		-- can't sync cause out of quota to set the value
		return
	end

	local dataExistBeforeSet = self.__cachedData[key] ~= nil

	local success = pcall(function()
		return self.__store:SetAsync(key, self.__cachedData[key].data)
	end)

	-- We lose the race condition
	if dataExistBeforeSet ~= (self.__cachedData[key] ~= nil) then
		return
	end

	if not success then
		return
	end

	if self.__cachedData[key].removeOnSync then
		self.__cachedData[key] = nil
	else
		self.__cachedData[key].uploadedToDatastore = true
		self.__cachedData[key].cacheTime = DateTime.now().UnixTimestampMillis
	end
end

function CacheStore.Destroy(self: CacheStore): ()
	task.cancel(self.__syncThread)

	self.Destroyed = true

	self.__store = nil :: any
	self.__cachedData = nil :: any
	self.__syncThread = nil :: any
	self.SyncTime = nil :: any
	self.CacheTimeout = nil :: any
end

return CacheStore

--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

type CacheStoreImpl = {
	__index: CacheStoreImpl,

	new: (name: string, scope: string?, options: DataStoreOptions?) -> CacheStore,

	Get: <T>(self: CacheStore, key: string) -> T?,
	Set: (self: CacheStore, key: string, value: unknown) -> (),
	Delete: (self: CacheStore, key: string) -> (),

	RemoveOnSync: (self: CacheStore, key: string) -> (),
	CancelRemoveOnSync: (self: CacheStore, key: string) -> (),
	
	GetSortedAsync: (self: CacheStore, ascending: boolean, pagesize: number, minValue: number?, maxValue: number?) -> DataStorePages,

	Destroy: (self: CacheStore) -> (),

	__syncToDatastore: (self: CacheStore, key: string) -> (),
}

type CacheStoreProto = {
	__store: GlobalDataStore | OrderedDataStore,
	-- UnixTimestamp for updateTime
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
	StoreType: "Ordered" | "Normal",

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
	storeType: "Ordered" | "Normal",
	options: DataStoreOptions?
): CacheStore
	local self = setmetatable({}, CacheStore) :: CacheStore

	self.__store = if storeType == "Ordered"
		then DataStoreService:GetOrderedDataStore(name, scope)
		else DataStoreService:GetDataStore(name, scope, options)

	self.__cachedData = {}

	self.Destroyed = false
	self.CacheTimeout = 10
	self.SyncTime = 10
	self.StoreType = storeType

	self.__syncThread = task.spawn(function()
		while task.wait(self.SyncTime) do
			for k, v in self.__cachedData do
				if v.uploadedToDatastore then
					if v.removeOnSync then
						self.__cachedData[k] = nil
					end

					continue
				end

				if
					0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
					or 0
					>= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
				then
					continue
				end

				self:__syncToDatastore(k)
			end
		end
	end)

	return self
end

function CacheStore.Get<T>(self: CacheStore, key: string): T?
	-- We return this if we ran out of budget to get the data... or if we can't fetch the data...
	local returnCachedData = self.__cachedData[key] and self.__cachedData[key].data :: T or nil

	if
		not self.__cachedData[key]
		or (DateTime.now().UnixTimestamp - self.__cachedData[key].cacheTime >= self.CacheTimeout)
	then
		if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) then
			return returnCachedData
		end

		local success, datastoreData, keyInfo: DataStoreKeyInfo = pcall(function()
			return self.__store:GetAsync(key)
		end)

		if not success then
			return returnCachedData
		end

		local decodedData = if self.StoreType == "Ordered" then datastoreData else HttpService:JSONDecode(datastoreData)

		if decodedData == self.__cachedData[key].data then
			self.__cachedData[key].updateTime = math.min(keyInfo.UpdatedTime, self.__cachedData[key].updateTime)
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp

			if self.__cachedData[key].removeOnSync then
				self.__cachedData[key] = nil
			end

			return returnCachedData
		end

		-- Data is still fresh, keep it
		if self.__cachedData[key].updateTime >= keyInfo.UpdatedTime then
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
			return returnCachedData
		else
			if self.__cachedData[key].removeOnSync then
				self.__cachedData[key] = nil
			else
				-- Data is not fresh, update it
				self.__cachedData[key].data = decodedData
				self.__cachedData[key].updateTime = keyInfo.UpdatedTime
				self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
				self.__cachedData[key].uploadedToDatastore = true
			end

			return decodedData
		end
	end

	return returnCachedData
end

function CacheStore.Set(self: CacheStore, key: string, value: unknown)
	if self.__cachedData[key].data == value then
		return
	end

	if self.StoreType == "Ordered" and typeof(value) ~= "number" then
		error("Ordered Store Type requires number value!")
	end

	self.__cachedData[key] = {
		data = value,
		updateTime = DateTime.now().UnixTimestamp,
		cacheTime = DateTime.now().UnixTimestamp,
		uploadedToDatastore = false,
		removeOnSync = false,
	}
end

function CacheStore.Delete(self: CacheStore, key: string)
	if self.__cachedData[key].data == nil then
		return
	end

	self.__cachedData[key] = {
		data = nil,
		updateTime = DateTime.now().UnixTimestamp,
		cacheTime = DateTime.now().UnixTimestamp,
		uploadedToDatastore = false,
		removeOnSync = false,
	}
end

function CacheStore.RemoveOnSync(self: CacheStore, key: string)
	if not self.__cachedData[key] then
		return
	end

	self.__cachedData[key].removeOnSync = true
end

function CacheStore.CancelRemoveOnSync(self: CacheStore, key: string)
	if not self.__cachedData[key] then
		return
	end

	self.__cachedData[key].removeOnSync = false
end

function CacheStore.GetSortedAsync(self: CacheStore, ascending: boolean, pagesize: number, minValue: number?, maxValue: number?): DataStorePages
	if self.StoreType ~= "Ordered" then
		error("GetSortedAsync can't be run on Normal datastore!")
	end
	
	return (self.__store :: OrderedDataStore):GetSortedAsync(ascending, pagesize, minValue, maxValue) :: DataStorePages
end

function CacheStore.__syncToDatastore(self: CacheStore, key: string)
	if self.__cachedData[key].uploadedToDatastore then
		return
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) then
		-- can't sync cause out of quota to check if datastore have been updated before
		return
	end

	local success, datastoreData, keyInfo: DataStoreKeyInfo = pcall(function()
		return self.__store:GetAsync(key)
	end)

	if not success then
		-- Can't sync, we can't check if cache over ridden yet
		return
	end

	local decodedData = if self.StoreType == "Ordered" then datastoreData else HttpService:JSONDecode(datastoreData)

	if decodedData == self.__cachedData[key].data then
		if self.__cachedData[key].removeOnSync then
			self.__cachedData[key] = nil
		else
			self.__cachedData[key].updateTime = math.min(keyInfo.UpdatedTime, self.__cachedData[key].updateTime)
			self.__cachedData[key].uploadedToDatastore = true
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
		end
		return
	end

	if keyInfo.UpdatedTime >= self.__cachedData[key].updateTime then
		if self.__cachedData[key].removeOnSync then
			self.__cachedData[key] = nil
		else
			self.__cachedData[key].uploadedToDatastore = true
			self.__cachedData[key].data = decodedData
			self.__cachedData[key].updateTime = keyInfo.UpdatedTime
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
		end
		return
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) then
		-- can't sync cause out of quota to set the value
		return
	end

	local success = pcall(function()
		return self.__store:SetAsync(
			key,
			if self.StoreType == "Ordered"
				then self.__cachedData[key].data
				else HttpService:JSONEncode(self.__cachedData[key].data)
		)
	end)

	if not success then
		return
	end

	if self.__cachedData[key].removeOnSync then
		self.__cachedData[key] = nil
	else
		self.__cachedData[key].uploadedToDatastore = true
		self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
	end
end

function CacheStore.Destroy(self: CacheStore)
	task.cancel(self.__syncThread)

	self.Destroyed = true

	self.__store = nil :: any
	self.__cachedData = nil :: any
	self.__syncThread = nil :: any
	self.SyncTime = nil :: any
	self.CacheTimeout = nil :: any
end

return CacheStore

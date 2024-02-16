--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local function EncodeToDatastore<T>(input: { data: T, updateTime: number }): string
	return HttpService:JSONEncode({
		input.updateTime,
		input.data,
	} :: { unknown })
end

local function DecodeFromDatastore<T>(input: string): { data: T?, updateTime: number }
	local decodedData = HttpService:JSONDecode(input)
	return { data = decodedData[2], updateTime = decodedData[1] }
end

type CacheStoreImpl = {
	__index: CacheStoreImpl,

	new: (name: string, scope: string?, options: DataStoreOptions?) -> CacheStore,

	Get: <T>(self: CacheStore, key: string) -> T?,
	Set: (self: CacheStore, key: string, value: unknown) -> (),
	Delete: (self: CacheStore, key: string) -> (),

	Destroy: (self: CacheStore) -> (),

	__syncToDatastore: (self: CacheStore, key: string) -> (),
}

type CacheStoreProto = {
	__store: DataStore,
	-- UnixTimestamp for updateTime
	-- cacheTime - keeps track of when cache is invalidated
	-- updateTime - the time when the data was updated
	__cachedData: { [string]: { data: unknown, updateTime: number, cacheTime: number, uploadedToDatastore: boolean } },
	__syncThread: thread,

	-- unit second
	CacheTimeout: number,
	SyncTime: number,

	Destroyed: boolean,
}

export type CacheStore = typeof(setmetatable({} :: CacheStoreProto, {} :: CacheStoreImpl))

local CacheStore = {}
CacheStore.__index = CacheStore

function CacheStore.new(name: string, scope: string?, options: DataStoreOptions?): CacheStore
	local self = setmetatable({}, CacheStore) :: CacheStore

	self.__store = DataStoreService:GetDataStore(name, scope, options)
	self.__cachedData = {}

	self.Destroyed = false
	self.CacheTimeout = 10
	self.SyncTime = 10

	self.__syncThread = task.spawn(function()
		while task.wait(self.SyncTime) do
			for k, v in self.__cachedData do
				if v.uploadedToDatastore then
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

		local success, datastoreData = pcall(function()
			return self.__store:GetAsync(key)
		end)

		if not success then
			return returnCachedData
		end

		local decodedData = DecodeFromDatastore(datastoreData)

		if decodedData.data == self.__cachedData[key].data then
			self.__cachedData[key].updateTime = math.min(decodedData.updateTime, self.__cachedData[key].updateTime)
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
			return returnCachedData
		end

		-- Data is still fresh, keep it
		if DateTime.now().UnixTimestamp >= decodedData.updateTime then
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
			return returnCachedData
		else
			-- Data is not fresh, update it
			self.__cachedData[key].data = decodedData.data
			self.__cachedData[key].updateTime = decodedData.updateTime
			self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
			self.__cachedData[key].uploadedToDatastore = true

			return decodedData.data
		end
	end

	return returnCachedData
end

function CacheStore.Set(self: CacheStore, key: string, value: unknown)
	if self.__cachedData[key].data == value then
		return
	end

	self.__cachedData[key] = {
		data = value,
		updateTime = DateTime.now().UnixTimestamp,
		cacheTime = DateTime.now().UnixTimestamp,
		uploadedToDatastore = false,
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
	}
end

function CacheStore.__syncToDatastore(self: CacheStore, key: string)
	if self.__cachedData[key].uploadedToDatastore then
		return
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) then
		-- can't sync cause out of quota to check if datastore have been updated before
		return
	end

	local success, datastoreData = pcall(function()
		return self.__store:GetAsync(key)
	end)

	if not success then
		-- Can't sync, we can't check if cache over ridden yet
		return
	end

	local decodedData = DecodeFromDatastore(datastoreData)

	if decodedData == self.__cachedData[key].data then
		self.__cachedData[key].updateTime = math.min(decodedData.updateTime, self.__cachedData[key].updateTime)
		self.__cachedData[key].uploadedToDatastore = true
		self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
		return
	end

	if decodedData.updateTime >= self.__cachedData[key].updateTime then
		self.__cachedData[key].uploadedToDatastore = true
		self.__cachedData[key].data = decodedData.data
		self.__cachedData[key].updateTime = decodedData.updateTime
		self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
		return
	end

	if 0 >= DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync) then
		-- can't sync cause out of quota to set the value
		return
	end

	local success = pcall(function()
		return self.__store:SetAsync(key, EncodeToDatastore(self.__cachedData[key]))
	end)

	if not success then
		return
	end

	self.__cachedData[key].uploadedToDatastore = true
	self.__cachedData[key].cacheTime = DateTime.now().UnixTimestamp
end

function CacheStore.Destroy(self: CacheStore)
	task.cancel(self.__syncThread)

	self.Destroyed = true

	self.__cachedData = nil :: any
	self.SyncTime = nil :: any
	self.CacheTimeout = nil :: any

	self.__store:Destroy()
end

return CacheStore

--!strict
--!native

-- Adapted from http://lua-users.org/wiki/CopyTable
local function InnerDeepCopy<K, V>(orig: { [any]: any } | any, copies: { [any]: any }?): { [K]: V } | any
	local cp: { [any]: any } = copies or {}

	local copy: ({ [K]: V } | any)?

	if typeof(orig) == "table" then
		if cp[orig] then
			copy = cp[orig]
		else
			copy = {}
			cp[orig] = copy
			for k, v in next, orig, nil do
				(copy :: any)[InnerDeepCopy(k, cp)] = InnerDeepCopy(v, cp)
			end
			setmetatable(copy :: any, InnerDeepCopy(getmetatable(orig :: any), cp))
		end
	else
		copy = orig
	end

	return copy
end

local function DeepCopy<K, V>(table: { [K]: V }): { [K]: V }
	return InnerDeepCopy(table)
end

return DeepCopy

--!strict

--TODO: Figure out how to not use TestService

local TestService = game:GetService("TestService")
local RunService = game:GetService("RunService")

type LoggerImpl = {
	__index: LoggerImpl,

	new: () -> Logger,

	__log: (self: Logger, level: "ERROR" | "WARN" | "INFO", message: string) -> (),

	Info: (self: Logger, ...any) -> (),
	Warn: (self: Logger, ...any) -> (),
	Error: (self: Logger, ...any) -> (),
}

type LoggerProto = {
	name: string,
}

export type Logger = typeof(setmetatable({} :: LoggerProto, {} :: LoggerImpl))

local Logger = {} :: LoggerImpl
Logger.__index = Logger

function listOfObjectToString(...: any): string
	local convertedString = {}

	for _, v in { ... } do
		table.insert(convertedString, tostring(v))
	end

	return table.concat(convertedString, " ")
end

function Logger.new(name: string?): Logger
	local self = setmetatable({}, Logger)

	self.name = name or "UNKNOWN"

	return self
end

function Logger:__log(level: "ERROR" | "WARN" | "INFO", message: string): ()
	if level == "WARN" then
		warn(`[{self.name}] [WARN] {message}`)
	else
		print(`[{self.name}] [{level}] {message}`)
	end
end

function Logger:Info(...: any): ()
	self:__log("INFO", listOfObjectToString(...))
end

function Logger:Warn(...: any): ()
	self:__log("WARN", listOfObjectToString(...))
end

function Logger:Error(...: any): ()
	local currentTime = DateTime.now().UnixTimestampMillis
	-- local msTime = (currentTime / 1000) - math.floor(currentTime / 1000)

	local tracebackList = {}

	do
		local i = 0

		while true do
			local data = {
				debug.info(2 + i, "s"),
				debug.info(2 + i, "l"),
				debug.info(2 + i, "n"),
				debug.info(2 + i, "f"),
			}

			if not data[1] and not data[2] and not data[3] and not data[4] then
				break
			end

			table.insert(tracebackList, data)

			i += 1
		end
	end

	local errorMessage = listOfObjectToString(...)
	errorMessage = if errorMessage == "" then "Error occurred, no output from Lua." else errorMessage
	errorMessage = `[{self.name}] [ERROR] {errorMessage}`

	if RunService:IsStudio() then
		-- os.date("%X", math.floor(currentTime / 1000)) .. "." .. (math.round(msTime*1000))/1000
		TestService:Error(errorMessage)
		TestService:Message("Stack Begin")
		for _, v in tracebackList do
			TestService:Message(`Script '{v[1]}', Line {v[2]}{if v[3] ~= "" then ` - function {v[3]}` else ""}`)
		end
		TestService:Message("Stack End")
	else
		-- Make the non studio version of text looks abit nicer :)
		errorMessage = `\n{os.date("%X", math.floor(currentTime / 1000))} -- ` .. errorMessage
		errorMessage = errorMessage .. "\n    Stack Begin"
		for _, v in tracebackList do
			errorMessage = errorMessage
				.. `\n    Script '{v[1]}', Line {v[2]}{if v[3] ~= "" then ` - function {v[3]}` else ""}`
		end
		errorMessage = errorMessage .. "\n    Stack End"
		TestService:Error(errorMessage)
	end
end

return Logger

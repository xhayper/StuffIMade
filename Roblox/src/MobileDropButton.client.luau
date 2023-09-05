--!strict

-- Put this in `StarterPlayer -> StarterPlayerScripts`

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local BYPASS_MOBILE_CHECK = false
local BUTTON_POSITION = UDim2.new(0.7, 0, 0.5, -100)

local player = Players.LocalPlayer
local character: Model? = player.Character

function isMobile(): boolean
	return (
		UserInputService.TouchEnabled
			and not UserInputService.KeyboardEnabled
			and not UserInputService.MouseEnabled
	) and (not GuiService:IsTenFootInterface())
end

if not BYPASS_MOBILE_CHECK and not isMobile() then
	return
end

function registerDropButton(func: (string, Enum.UserInputState, InputObject) -> ())
	ContextActionService:BindAction("Drop", func, true)
	ContextActionService:SetTitle("Drop", "Drop")
	ContextActionService:SetDescription("Drop", "Drop equipped item")
	ContextActionService:SetPosition("Drop", BUTTON_POSITION)
end

function unregisterDropButton()
	ContextActionService:UnbindAction("Drop")
end

function handleDropAction(_: string, state: Enum.UserInputState, inputObject: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return
	end

	if not character then
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if not child:IsA("Tool") then
			continue
		end

		local tool = child :: Tool

		if tool.CanBeDropped then
			tool.Parent = workspace
			break
		end
	end

	checkCharacterForTool()
end

function hasDroppableToolEquipped(character: Model): boolean
	for _, child in character:GetChildren() do
		if not child:IsA("Tool") then
			continue
		end

		local tool = child :: Tool

		if tool.CanBeDropped then
			return true
		end
	end

	return false
end

function checkCharacterForTool()
	if not character then
		return
	end

	if hasDroppableToolEquipped(character) then
		if not BYPASS_MOBILE_CHECK and not isMobile() then
			return
		end

		registerDropButton(handleDropAction)
	else
		unregisterDropButton()
	end
end

function handleCharacterAdded(char: Model)
	character = char

	checkCharacterForTool()

	char.ChildAdded:Connect(checkCharacterForTool)
	char.ChildRemoved:Connect(checkCharacterForTool)
end

if character then
	handleCharacterAdded(character)
end

player.CharacterAdded:Connect(handleCharacterAdded)


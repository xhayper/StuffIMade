--!strict

local Players = game:GetService("Players")

local ToolHelper = {}
ToolHelper.__index = ToolHelper

function ToolHelper.new(tool: Tool)
	local self = setmetatable({}, ToolHelper)

	self.Utility = {
		GetPlayerFromInstance = function(instance: Instance): Player?
			local player: Player?
			local temp: Instance? = instance

			repeat
				if temp then
					if temp:IsA("Player") then
						player = temp
					end

					if temp:IsA("Model") then
						player = Players:GetPlayerFromCharacter(temp)
					end

					if player then
						break
					end

					temp = temp.Parent
				end
			until player or not temp or not temp.Parent or temp.Parent == game

			return player
		end,
	}

	self.Tool = tool

	self.Equipped = false
	self.Activated = false
	self.Mouse = nil :: Mouse?

	self.Owner = nil :: Player?
	self.Character = nil :: Model?

	self._Deleted = Instance.new("BindableEvent")
	self._OwnerChanged = Instance.new("BindableEvent")
	self._CharacterChanged = Instance.new("BindableEvent")

	self.Deleted = self._Deleted.Event
	self.OwnerChanged = self._OwnerChanged.Event
	self.CharacterChanged = self._CharacterChanged.Event

	self._PlayerConnections = {} :: { RBXScriptConnection }

	local function UpdateCharacter()
		local NewCharacter = self.Owner and self.Owner.Character or nil

		if self.Character == NewCharacter then
			return
		end
		self.Character = NewCharacter

		self._CharacterChanged:Fire(self.Character)
	end

	local function UpdateOwner()
		local toolParent = tool.Parent
		local newOwner = toolParent and toolParent.Parent and toolParent.Parent:IsA("Player") and toolParent.Parent
			or nil

		if not newOwner and toolParent and toolParent:IsA("Model") then
			newOwner = Players:GetPlayerFromCharacter(toolParent)
		end

		if self.Owner == newOwner then
			return
		end
		self.Owner = newOwner

		for _, v in ipairs(self._PlayerConnections) do
			v:Disconnect()
		end

		self._OwnerChanged:Fire(self.Owner)

		if self.Owner then
			table.insert(self._PlayerConnections, self.Owner.CharacterRemoving:Connect(UpdateCharacter))
			table.insert(self._PlayerConnections, self.Owner.CharacterAdded:Connect(UpdateCharacter))
		end

		UpdateCharacter()
	end

	tool.Destroying:Connect(function()
		self.Tool = (nil :: any) :: Tool
		self:Destroy()
	end)

	tool.AncestryChanged:Connect(UpdateOwner)

	tool.Activated:Connect(function()
		self.Activated = true
	end)

	tool.Deactivated:Connect(function()
		self.Activated = false
	end)

	tool.Equipped:Connect(function(mouse)
		self.Mouse = mouse
		self.Equipped = true

		UpdateOwner()
	end)

	tool.Unequipped:Connect(function()
		self.Mouse = nil
		self.Equipped = false
		self.Activated = false

		UpdateOwner()
	end)

	UpdateOwner()

	return self
end

function ToolHelper:Destroy()
	if self.Tool then
		self.Tool:Destroy()
	else
		for _, v in ipairs(self._PlayerConnections) do
			v:Disconnect()
		end

		self.Equipped = false
		self.Mouse = nil

		self.Owner = nil
		self.Character = nil

		self._Deleted:Fire()

		self._Deleted:Destroy()
		self._OwnerChanged:Destroy()
		self._CharacterChanged:Destroy()
	end
end

return ToolHelper

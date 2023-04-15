--!strict

local Players = game:GetService("Players")

---------------------------------------------

local ToolAnimation = {}
ToolAnimation.__index = ToolAnimation

export type ToolAnimation = typeof(ToolAnimation.new(nil :: any, nil :: any))

function ToolAnimation.new(helper: ToolHelper, animation: Animation)
	local self = setmetatable({}, ToolAnimation)

	self.Loaded = false

	self.AnimationTrack = nil :: AnimationTrack?
	self.Animation = animation

	self.Helper = helper

	self._DidLoop = Instance.new("BindableEvent")
	self._Ended = Instance.new("BindableEvent")
	self._KeyframeReached = Instance.new("BindableEvent")
	self._Stopped = Instance.new("BindableEvent")
	self._TrackChanged = Instance.new("BindableEvent")

	self._ConnectionList = {} :: { RBXScriptConnection }
	self._AnimationTrackConnectionList = {} :: { RBXScriptConnection }

	self.DidLoop = self._DidLoop.Event
	self.Ended = self._Ended.Event
	self.KeyframeReached = self._KeyframeReached.Event
	self.Stopped = self._Stopped.Event
	self.TrackChanged = self._TrackChanged.Event

	local function OnCharacterUpdate(character: Model?)
		if self.AnimationTrack then
			for _, conn in ipairs(self._AnimationTrackConnectionList) do
				conn:Disconnect()
			end

			self.AnimationTrack:Stop()
			self.AnimationTrack:Destroy()
			self.AnimationTrack = nil
		end

		self.Loaded = false
		
		if not character then return end
		
		task.wait() -- Wait 1 frame
		local Humanoid = character:FindFirstChildOfClass("Humanoid")

		if not Humanoid then return end

		local Animator = Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		Animator.Parent = Humanoid

		self.AnimationTrack = Animator:LoadAnimation(self.Animation)
		self.Loaded = true

		if self.AnimationTrack then			
			table.insert(self._AnimationTrackConnectionList, self.AnimationTrack.DidLoop:Connect(function()
				self._DidLoop:Fire()
			end))

			table.insert(self._AnimationTrackConnectionList, self.AnimationTrack.Ended:Connect(function()
				self._Ended:Fire()
			end))

			table.insert(self._AnimationTrackConnectionList, self.AnimationTrack.KeyframeReached:Connect(function(keyframeName)
				self._KeyframeReached:Fire(keyframeName)
			end))

			table.insert(self._AnimationTrackConnectionList, self.AnimationTrack.Stopped:Connect(function()
				self._Stopped:Fire()
			end))

			self._TrackChanged:Fire()
		end
	end

	table.insert(self._ConnectionList, self.Helper.CharacterChanged:Connect(OnCharacterUpdate))

	if self.Helper.Character then
		OnCharacterUpdate(self.Helper.Character)
	end

	return self
end

function ToolAnimation:AdjustSpeed(speed: number)
	if self.AnimationTrack then
		self.AnimationTrack:AdjustSpeed(speed)
	end
end

function ToolAnimation:AdjustWeight(weight: number, fadeTime: number?)
	if self.AnimationTrack then
		self.AnimationTrack:AdjustWeight(weight, fadeTime)
	end
end

function ToolAnimation:GetMarkerReachedSignal(name: string): RBXScriptSignal?
	if self.AnimationTrack then
		return self.AnimationTrack:GetMarkerReachedSignal(name)
	end

	return nil
end

function ToolAnimation:GetTimeOfKeyframe(keyframeName: string): number?
	if self.AnimationTrack then
		return self.AnimationTrack:GetTimeOfKeyframe(keyframeName)
	end

	return nil
end

function ToolAnimation:Play(fadeTime: number?, weight: number?, speed: number?)
	if self.AnimationTrack then
		self.AnimationTrack:Play(fadeTime, weight, speed)
	end
end

function ToolAnimation:Stop(fadeTime: number?)
	if self.AnimationTrack then
		self.AnimationTrack:Stop(fadeTime)
	end
end

function ToolAnimation:Destroy()
	self.Loaded = false

	self.Helper.AnimationList[self.Animation.AnimationId] = nil

	if self.AnimationTrack then
		self.AnimationTrack:Stop()
		self.AnimationTrack:Destroy()
	end

	for _, conn in ipairs(self._ConnectionList) do
		conn:Disconnect()
	end
end

---------------------------------------------

local ToolHelper = {}
ToolHelper.__index = ToolHelper

export type ToolHelper = typeof(ToolHelper.new(nil :: any))

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
						break
					end

					if temp:IsA("Model") then
						player = Players:GetPlayerFromCharacter(temp)

						if player then
							break
						end
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
	self.AnimationList = {} :: { [string]: ToolAnimation }

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

function ToolHelper:LoadAnimation(animation: Animation | string): ToolAnimation
	local anim: Animation
	if typeof(animation) == "string" then
		anim = Instance.new("Animation")
		anim.AnimationId = animation
	else
		anim = animation
	end

	local toolAnimation = self.AnimationList[anim.AnimationId] or ToolAnimation.new(self, anim)
	self.AnimationList[anim.AnimationId] = toolAnimation

	return toolAnimation
end

function ToolHelper:Destroy()
	if self.Tool then
		self.Tool:Destroy()
	else
		for _, v in ipairs(self._PlayerConnections) do
			v:Disconnect()
		end
		
		for _, anim in pairs(self.AnimationList) do
			anim:Destroy()
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

--!strict
--!native

local Players = game:GetService("Players")

---------------------------------------------

export type ToolAnimationImpl = {
	__index: ToolAnimationImpl,
	new: (helper: ToolHelper, animation: Animation) -> ToolAnimation,

	AdjustSpeed: (self: ToolAnimation, speed: number) -> (),
	AdjustWeight: (self: ToolAnimation, weight: number, fadeTime: number?) -> (),
	GetMarkerReachedSignal: (self: ToolAnimation, name: string) -> RBXScriptSignal?,
	GetTimeOfKeyframe: (self: ToolAnimation, keyframeName: string) -> number?,
	Play: (self: ToolAnimation, fadeTime: number?, weight: number?, speed: number?) -> (),
	Stop: (self: ToolAnimation, fadeTime: number?) -> (),
	Destroy: (self: ToolAnimation) -> (),
}

export type ToolAnimationProto = {
	Loaded: boolean,

	AnimationTrack: AnimationTrack?,
	Animation: Animation,

	Helper: ToolHelper,

	DidLoop: RBXScriptSignal,
	Ended: RBXScriptSignal,
	KeyframeReached: RBXScriptSignal,
	Stopped: RBXScriptSignal,
	TrackChanged: RBXScriptSignal,

	_DidLoop: BindableEvent,
	_Ended: BindableEvent,
	_KeyframeReached: BindableEvent,
	_Stopped: BindableEvent,
	_TrackChanged: BindableEvent,
	_ConnectionList: { RBXScriptConnection },
	_AnimationTrackConnectionList: { RBXScriptConnection },
}

export type ToolAnimation = typeof(setmetatable({} :: ToolAnimationProto, {} :: ToolAnimationImpl))

---------------------------------------------

local ToolAnimation = {}
ToolAnimation.__index = ToolAnimation

function ToolAnimation.new(helper: ToolHelper, animation: Animation): ToolAnimation
	local self = (setmetatable({}, ToolAnimation) :: any) :: ToolAnimation

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

	local animationLoadThread: thread?
	local function OnCharacterUpdate(character: Model?)
		if animationLoadThread then
			task.cancel(animationLoadThread)
		end

		if self.AnimationTrack then
			for _, conn in self._AnimationTrackConnectionList do
				conn:Disconnect()
			end
			self._AnimationTrackConnectionList = {}

			self.AnimationTrack:Stop()
			self.AnimationTrack:Destroy()
			self.AnimationTrack = nil
		end

		self.Loaded = false

		if not character then
			return
		end

		task.wait() -- Wait 1 frame
		local Humanoid = character:FindFirstChildOfClass("Humanoid")

		if not Humanoid then
			return
		end

		local Animator = Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		Animator.Parent = Humanoid

		animationLoadThread = task.spawn(function()
			repeat
				local success = pcall(function()
					self.AnimationTrack = Animator:LoadAnimation(self.Animation)
				end)
			until success

			self.Loaded = true

			if self.AnimationTrack then
				table.insert(
					self._AnimationTrackConnectionList,
					self.AnimationTrack.DidLoop:Connect(function()
						self._DidLoop:Fire()
					end)
				)

				table.insert(
					self._AnimationTrackConnectionList,
					self.AnimationTrack.Ended:Connect(function()
						self._Ended:Fire()
					end)
				)

				table.insert(
					self._AnimationTrackConnectionList,
					self.AnimationTrack.KeyframeReached:Connect(function(keyframeName)
						self._KeyframeReached:Fire(keyframeName)
					end)
				)

				table.insert(
					self._AnimationTrackConnectionList,
					self.AnimationTrack.Stopped:Connect(function()
						self._Stopped:Fire()
					end)
				)
			end

			self._TrackChanged:Fire()

			animationLoadThread = nil
		end)
	end

	table.insert(self._ConnectionList, self.Helper.CharacterChanged:Connect(OnCharacterUpdate))

	if self.Helper.Character then
		OnCharacterUpdate(self.Helper.Character)
	end

	return self
end

function ToolAnimation.AdjustSpeed(self: ToolAnimation, speed: number)
	if self.AnimationTrack then
		self.AnimationTrack:AdjustSpeed(speed)
	end
end

function ToolAnimation.AdjustWeight(self: ToolAnimation, weight: number, fadeTime: number?)
	if self.AnimationTrack then
		self.AnimationTrack:AdjustWeight(weight, fadeTime)
	end
end

function ToolAnimation.GetMarkerReachedSignal(self: ToolAnimation, name: string): RBXScriptSignal?
	if self.AnimationTrack then
		return self.AnimationTrack:GetMarkerReachedSignal(name)
	end

	return nil
end

function ToolAnimation.GetTimeOfKeyframe(self: ToolAnimation, keyframeName: string): number?
	if self.AnimationTrack then
		return self.AnimationTrack:GetTimeOfKeyframe(keyframeName)
	end

	return nil
end

function ToolAnimation.Play(self: ToolAnimation, fadeTime: number?, weight: number?, speed: number?)
	if self.AnimationTrack then
		self.AnimationTrack:Play(fadeTime, weight, speed)
	end
end

function ToolAnimation.Stop(self: ToolAnimation, fadeTime: number?)
	if self.AnimationTrack then
		self.AnimationTrack:Stop(fadeTime)
	end
end

function ToolAnimation.Destroy(self: ToolAnimation)
	self.Loaded = false

	table.remove(self.Helper.AnimationList, table.find(self.Helper.AnimationList, self))

	if self.AnimationTrack then
		self.AnimationTrack:Stop()
		self.AnimationTrack:Destroy()
	end

	for _, conn in self._ConnectionList do
		conn:Disconnect()
	end
	self._ConnectionList = {}

	self._DidLoop:Destroy()
	self._Ended:Destroy()
	self._KeyframeReached:Destroy()
	self._Stopped:Destroy()
	self._TrackChanged:Destroy()
end

---------------------------------------------

export type ToolHelperImpl = {
	__index: ToolHelperImpl,
	new: (tool: Tool) -> ToolHelper,
	LoadAnimation: (self: ToolHelper, animation: Animation | string) -> ToolAnimation,
	Destroy: (self: ToolHelper) -> (),
}

export type ToolHelperProto = {
	Tool: Tool,
	AnimationList: { ToolAnimation },
	Utility: {
		GetPlayerFromInstance: (instance: Instance) -> Player?,
	},

	Destroyed: boolean,
	Equipped: boolean,
	Activated: boolean,
	Dropped: boolean,

	Mouse: Mouse?,
	Owner: Player?,
	Character: Model?,

	Deleted: RBXScriptSignal,
	DroppedChanged: RBXScriptSignal,
	OwnerChanged: RBXScriptSignal,
	CharacterChanged: RBXScriptSignal,

	_Deleted: BindableEvent,
	_OwnerChanged: BindableEvent,
	_CharacterChanged: BindableEvent,
	_DroppedChanged: BindableEvent,
	_PlayerConnections: { RBXScriptConnection },
}

export type ToolHelper = typeof(setmetatable({} :: ToolHelperProto, {} :: ToolHelperImpl))

---------------------------------------------

local ToolHelper = {}
ToolHelper.__index = ToolHelper

function ToolHelper.new(tool: Tool): ToolHelper
	local self = (setmetatable({}, ToolHelper) :: any) :: ToolHelper

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

	self.Destroyed = false
	self.Equipped = false
	self.Activated = false
	self.Dropped = false

	self.Mouse = nil :: Mouse?
	self.Owner = nil :: Player?
	self.Character = nil :: Model?
	self.AnimationList = {} :: { ToolAnimation }

	self._Deleted = Instance.new("BindableEvent")
	self._OwnerChanged = Instance.new("BindableEvent")
	self._CharacterChanged = Instance.new("BindableEvent")
	self._DroppedChanged = Instance.new("BindableEvent")

	self.Deleted = self._Deleted.Event
	self.DroppedChanged = self._DroppedChanged.Event
	self.OwnerChanged = self._OwnerChanged.Event
	self.CharacterChanged = self._CharacterChanged.Event

	self._PlayerConnections = {} :: { RBXScriptConnection }

	local function UpdateDropped()
		if self.Character == nil and self.Tool:IsDescendantOf(workspace) then
			self.Dropped = true
		else
			self.Dropped = false
		end

		self._DroppedChanged:Fire()
	end

	local function UpdateCharacter()
		local NewCharacter

		if self.Owner then
			NewCharacter = self.Owner.Character
		else
			local toolParent = tool.Parent
			if toolParent and toolParent.ClassName == "Model" then
				NewCharacter = toolParent :: Model
			end
		end

		if self.Character == NewCharacter then
			return
		end
		self.Character = NewCharacter

		self._CharacterChanged:Fire(self.Character)

		UpdateDropped()
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

		for _, v in self._PlayerConnections do
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

	tool:GetPropertyChangedSignal("Parent"):Connect(UpdateOwner)

	tool.Changed:Connect(function(property)
		if property ~= "Parent" then
			return
		end
		UpdateOwner()
	end)

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

	return self :: any
end

function ToolHelper.LoadAnimation(self: ToolHelper, animation: Animation | string): ToolAnimation
	if self.Destroyed then
		return nil :: any
	end

	local anim: Animation
	if typeof(animation) == "string" then
		anim = Instance.new("Animation")
		anim.AnimationId = animation
	else
		anim = animation
	end

	local toolAnimation = ToolAnimation.new(self, anim)
	table.insert(self.AnimationList, toolAnimation)

	return toolAnimation
end

function ToolHelper.Destroy(self: ToolHelper)
	if self.Tool then
		self.Tool:Destroy()
	else
		self.Destroyed = true

		for _, anim in self.AnimationList do
			anim:Destroy()
		end
		self.AnimationList = {}

		for _, v in self._PlayerConnections do
			v:Disconnect()
		end
		self._PlayerConnections = {}

		self.Equipped = false
		self.Mouse = nil

		self.Owner = nil
		self.Character = nil

		self._Deleted:Fire()

		self._Deleted:Destroy()
		self._OwnerChanged:Destroy()
		self._CharacterChanged:Destroy()
		self._DroppedChanged:Destroy()
	end
end

return ToolHelper

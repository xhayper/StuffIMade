--!strict
--!native

-- Roact Mock
local Roact = {}

function Roact.createElement(a: string, b: { [string]: unknown }): Instance
	local i = Instance.new(a)
	for k, v in b do
		(i :: any)[k] = v
	end
	return i
end

-- https://github.com/tiffany352/Roblox-Tag-Editor/blob/f07eaf883491eda403d9b9383484714508c983dc/src/Util.lua
local function GenerateOutline(
	props: { Adornee: Instance, Size: Vector3, Color3: Color3?, Box: boolean? }
): { Instance }
	local OutlineVertices = {
		{ 1, 1, -1 },
		{ -1, 1, -1 },
		{ -1, 1, -1 },
		{ -1, 1, 1 },
		{ -1, 1, 1 },
		{ 1, 1, 1 },
		{ 1, 1, 1 },
		{ 1, 1, -1 },
		{ 1, -1, -1 },
		{ -1, -1, -1 },
		{ -1, -1, -1 },
		{ -1, -1, 1 },
		{ -1, -1, 1 },
		{ 1, -1, 1 },
		{ 1, -1, 1 },
		{ 1, -1, -1 },
		{ 1, 1, -1 },
		{ 1, -1, -1 },
		{ -1, -1, -1 },
		{ -1, 1, -1 },
		{ 1, 1, 1 },
		{ 1, -1, 1 },
		{ -1, -1, 1 },
		{ -1, 1, 1 },
	}
	local Corners = {}
	for _, Vector in OutlineVertices do
		table.insert(
			Corners,
			(CFrame.new(props.Size.X / 2 * Vector[1], props.Size.Y / 2 * Vector[2], props.Size.Z / 2 * Vector[3])).Position
		)
	end
	local Instances = {}
	for i, _ in Corners do
		if i % 2 == 0 then
			continue
		end
		local displacement = Corners[i] - Corners[i + 1]
		table.insert(
			Instances,
			Roact.createElement("CylinderHandleAdornment", {
				Color3 = props.Color3,
				Adornee = props.Adornee,
				AlwaysOnTop = true,
				Height = displacement.Magnitude,
				CFrame = CFrame.lookAt(Corners[i], Corners[i + 1]) * CFrame.new(0, 0, -displacement.Magnitude / 2),
				Radius = 0.033,
				ZIndex = 0,
			})
		)
	end
	if props.Box then
		table.insert(
			Instances,
			Roact.createElement("BoxHandleAdornment", {
				Color3 = props.Color3,
				Transparency = 0.7,
				Adornee = props.Adornee,
				AlwaysOnTop = true,
				Size = props.Size,
				ZIndex = 0,
			})
		)
	end
	return Instances
end

local Storage: Instance = workspace.Terrain:FindFirstChild("HighlightList") or Instance.new("Folder")
Storage.Name = "HighlightList"
Storage.Parent = workspace.Terrain
Storage:ClearAllChildren()

for _, v in workspace:GetDescendants() do
	if not v:IsA("BasePart") or v.Anchored then
		continue
	end

	local InstanceList = GenerateOutline({
		Adornee = v,
		Size = (v :: BasePart).Size,
		Color3 = Color3.fromRGB(255, 75, 75),
		Box = true,
	})

	for _, v2 in InstanceList do
		v2.Parent = Storage
	end
end

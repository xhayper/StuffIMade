return function(origin: Vector3, direction: Vector3, raycastResult: RaycastResult?): Part
	local rayPart = Instance.new("Part")
	rayPart.Archivable = false
	rayPart.CanCollide = false
	rayPart.CastShadow = false
	rayPart.CanQuery = false
	rayPart.CanTouch = false
	rayPart.Anchored = true
	rayPart.Locked = true

	if raycastResult then
		rayPart.Color = Color3.fromRGB(75, 255, 75)
		rayPart.Size = Vector3.new(0, 0, (origin - raycastResult.Position).Magnitude)
		rayPart.CFrame = CFrame.new((origin + raycastResult.Position) / 2, raycastResult.Position)
	else
		local endPos = origin + direction
		rayPart.Color = Color3.fromRGB(255, 75, 75)
		rayPart.Size = Vector3.new(0, 0, (origin - direction).Magnitude)
		rayPart.CFrame = CFrame.new((origin + endPos) / 2, endPos)
	end

	return rayPart
end

--!strict
--!native

return function(part: BasePart, increment: number?): { Vector3 }
	local inc: number = increment or 0.5
	local partSize = part.Size

	local startX, startY, startZ =
		-(inc * ((partSize.X / 2) / inc)), -(inc * ((partSize.Y / 2) / inc)), -(inc * ((partSize.Z / 2) / inc))

	local positionTable = {}

	for x = startX, -startX, inc do
		for y = startY, -startY, inc do
			for z = startZ, -startZ, inc do
				table.insert(positionTable, Vector3.new(x, y, z))
			end
		end
	end

	return positionTable
end

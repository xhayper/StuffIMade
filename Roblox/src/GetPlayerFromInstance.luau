--!strict
--!native

local Players = game:GetService("Players")

return function(instance: Instance?): Player?
	local temp: Instance? = instance

	while temp and temp.Parent and temp.Parent ~= game do
		if temp:IsA("Player") then
			return temp
		elseif temp:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(temp)
			if player then
				return player
			end
		end

		temp = temp.Parent
	end

	return nil
end

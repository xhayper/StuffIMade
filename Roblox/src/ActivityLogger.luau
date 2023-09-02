--!strict

local repr = require(3148021300)

local function HandleInstance(v: Instance)
	if v:IsA("RemoteEvent") then
		pcall(function()
			v.OnServerEvent:Connect(function(player, ...)
				print(`{player.Name} => {v:GetFullName()}: {repr({ ... })}`)
			end)
		end)
	elseif v:IsA("ClickDetector") then
		pcall(function()
			v.MouseClick:Connect(function(player)
				print(`{player.Name} => {v:GetFullName()}: CLICK DETECTOR`)
			end)
		end)
	elseif v:IsA("ProximityPrompt") then
		pcall(function()
			v.Triggered:Connect(function(player)
				print(`{player.Name} => {v:GetFullName()}: PROXIMITY PROMPT`)
			end)
		end)
	end
end

for _, v in game:GetDescendants() do
	HandleInstance(v)
end

game.DescendantAdded:Connect(HandleInstance)

local Players = game:GetService("Players")

return function(instance: Instance): Player?
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
            end

            temp = temp.Parent
        end
    until player or not temp or not temp.Parent or temp.Parent == game

    return player
end

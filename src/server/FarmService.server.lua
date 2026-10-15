-- FarmService: server-side farm ownership (runtime only, no persistence yet).
local Players = game:GetService("Players")

local farmsFolder = workspace:WaitForChild("Farms")

local farms = {}          -- usable Farm models, sorted by number
local ownerByFarm = {}    -- [farm] = player
local farmByPlayer = {}   -- [player] = farm
local waitlist = {}       -- players waiting for a free farm
local handled = {}        -- [player] = true once set up

for _, farm in ipairs(farmsFolder:GetChildren()) do
	if farm:IsA("Model") and farm:FindFirstChild("FarmSpawn") then
		farm:SetAttribute("OwnerUserId", 0) -- nobody owns anything at server start
		table.insert(farms, farm)
	else
		warn("[FarmService] Skipping invalid farm: " .. farm:GetFullName())
	end
end
table.sort(farms, function(a, b)
	return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
end)

local function claimFarm(player)
	if farmByPlayer[player] then
		return farmByPlayer[player]
	end
	for _, farm in ipairs(farms) do
		if farm.Parent and not ownerByFarm[farm] then
			ownerByFarm[farm] = player
			farmByPlayer[player] = farm
			farm:SetAttribute("OwnerUserId", player.UserId)
			return farm
		end
	end
	return nil
end

local function teleportToFarm(player)
	local farm = farmByPlayer[player]
	local character = player.Character
	if not farm or not character then
		return
	end
	local spawnPart = farm:FindFirstChild("FarmSpawn")
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not spawnPart or not root or not character.Parent or farmByPlayer[player] ~= farm then
		return
	end
	character:PivotTo(spawnPart.CFrame * CFrame.new(0, 3.5, 0))
end

local function assignFromWaitlist()
	while #waitlist > 0 do
		local player = waitlist[1]
		if player.Parent ~= Players then
			table.remove(waitlist, 1)
		elseif claimFarm(player) then
			table.remove(waitlist, 1)
			task.spawn(teleportToFarm, player)
		else
			return -- still full
		end
	end
end

local function onPlayerAdded(player)
	if handled[player] then
		return
	end
	handled[player] = true

	if not claimFarm(player) then
		table.insert(waitlist, player)
		warn("[FarmService] All farms occupied; " .. player.Name .. " is waiting for a free farm")
	end

	player.CharacterAdded:Connect(function()
		task.spawn(teleportToFarm, player)
	end)
	if player.Character then
		task.spawn(teleportToFarm, player)
	end
end

local function onPlayerRemoving(player)
	handled[player] = nil
	local index = table.find(waitlist, player)
	if index then
		table.remove(waitlist, index)
	end
	local farm = farmByPlayer[player]
	if farm then
		farmByPlayer[player] = nil
		ownerByFarm[farm] = nil
		if farm.Parent then
			farm:SetAttribute("OwnerUserId", 0) -- release ownership only; contents are left untouched
		end
		assignFromWaitlist()
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

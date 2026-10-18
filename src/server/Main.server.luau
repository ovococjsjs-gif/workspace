--[=[
	Сервер «СТАИ»: рекорды + примитивная защита от невозможных результатов.
	Сама игра считается на клиенте (аркадный однопользовательский режим),
	сервер не доверяет клиенту в части рекорда: проверяет правдоподобность
	(использует ровно те же правила, что и юнит-тесты) и хранит лучший результат.
]=]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Score = require(Shared.Score)

local STORE_NAME = "flock_best_v1"

local remotes = Instance.new("Folder")
remotes.Name = "FlockRemotes"
remotes.Parent = ReplicatedStorage

local submitRemote = Instance.new("RemoteEvent")
submitRemote.Name = "SubmitScore"
submitRemote.Parent = remotes

local requestRemote = Instance.new("RemoteEvent")
requestRemote.Name = "RequestBest"
requestRemote.Parent = remotes

local bestRemote = Instance.new("RemoteEvent")
bestRemote.Name = "BestScore"
bestRemote.Parent = remotes

local bestStore = DataStoreService:GetDataStore(STORE_NAME)
local bestScores: { [Player]: number } = {}

local function pushBest(player: Player)
	local value = bestScores[player]
	if value then
		pcall(function()
			bestRemote:FireClient(player, value)
		end)
	end
end

local function loadBest(player: Player)
	local ok, value = pcall(function()
		return bestStore:GetAsync("u_" .. tostring(player.UserId))
	end)
	if ok and typeof(value) == "number" then
		bestScores[player] = value
		pushBest(player)
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(loadBest, player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	bestScores[player] = nil
end)

requestRemote.OnServerEvent:Connect(function(player: Player)
	pushBest(player)
end)

submitRemote.OnServerEvent:Connect(function(player: Player, score: any, elapsed: any)
	if typeof(score) ~= "number" or typeof(elapsed) ~= "number" then
		return
	end
	-- Отсекаем явно невозможные результаты (правила покрыты юнит-тестами).
	if not Score.isPlausible(score, elapsed) then
		return
	end
	local current = bestScores[player] or 0
	if score > current then
		bestScores[player] = score
		pcall(function()
			bestStore:SetAsync("u_" .. tostring(player.UserId), score)
		end)
		pushBest(player)
	end
end)

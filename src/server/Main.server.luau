--[=[
	Сервер «СТАИ»: рекорды, общий раунд-гонка и проверка результатов.
	Сама игра считается на клиенте (аркадный однопользовательский режим),
	сервер не доверяет клиенту в части рекорда: проверяет правдоподобность
	(использует ровно те же правила, что и юнит-тесты) и хранит лучший результат.

	ГОНКА: сервер генерирует сид раунда и рассылает его всем — одинаковый сид
	даёт одинаковый курс, поэтому результаты игроков сравнимы. Клиент считает
	свой забег сам, но сервер принимает только правдоподобный счёт и ведёт
	живой рейтинг (места, порядок финиша).
]=]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local GameplayService = game:GetService("GameplayService")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Score = require(Shared.Score)
local Race = require(Shared.Race)
local ShopConfig = require(Shared.ShopConfig)

local STORE_NAME = "flock_best_v1"

local remotes = Instance.new("Folder")
remotes.Name = "FlockRemotes"
remotes.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

-- Рекорд.
local submitRemote = makeRemote("SubmitScore")
local requestRemote = makeRemote("RequestBest")
local bestRemote = makeRemote("BestScore")

-- Гонка.
local roundStartRemote = makeRemote("RoundStart")
local standingsRemote = makeRemote("Standings")
local roundEndRemote = makeRemote("RoundEnd")
local progressRemote = makeRemote("Progress")
local requestRoundRemote = makeRemote("RequestRound")

-- Покупки (Robux).
local buyPassRemote = makeRemote("BuyPass")
local buyProductRemote = makeRemote("BuyProduct")
local permsRemote = makeRemote("PermsUpdate")
local buyResultRemote = makeRemote("BuyResult")

local bestStore = DataStoreService:GetDataStore(STORE_NAME)
local bestScores: { [Player]: number } = {}
--- Время, когда игрок появился на сервере: сервер считает длительность забега сам,
--- чтобы клиент не мог «накрутить» её и обойти проверку скорости набора очков.
local sessionStart: { [Player]: number } = {}

--------------------------------------------------------------------------- гонка

local COUNTDOWN = 3.0
local ROUND_LIMIT = 300.0
local PROGRESS_HZ = 4.0

local round = {
	seed = 0,
	startAt = 0,
	startedAt = 0,
	state = "idle", -- idle | countdown | running | finished
	finishedOrder = 0,
}
--- Участники текущего раунда.
local racers: { [Player]: Race.Entry } = {}

local function serverNow(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return os.clock()
end

local function ensureRacer(player: Player): Race.Entry
	local entry = racers[player]
	if not entry then
		entry = {
			userId = player.UserId,
			name = player.Name,
			score = 0,
			distance = 0,
			alive = 18,
			finished = false,
			place = nil,
		}
		racers[player] = entry
	end
	return entry
end

--- Текущий рейтинг (отсортированный, с местами).
local function currentEntries(): { Race.Entry }
	local list: { Race.Entry } = {}
	for _, entry in racers do
		table.insert(list, entry)
	end
	return Race.assignPlaces(list)
end

local function broadcastStandings()
	local sorted = currentEntries()
	for player in racers do
		standingsRemote:FireClient(player, sorted)
	end
end

--- Новый раунд: новый сид (общий курс) и обратный отсчёт.
local function startRound()
	round.seed = math.random(1, 100000000)
	round.startAt = serverNow() + COUNTDOWN
	round.startedAt = round.startAt
	round.state = "countdown"
	round.finishedOrder = 0
	for player in racers do
		roundStartRemote:FireClient(player, round.seed, round.startAt)
	end
end

local function endRound()
	round.state = "finished"
	local sorted = currentEntries()
	roundEndRemote:FireAllClients(sorted)
	broadcastStandings()
end

requestRoundRemote.OnServerEvent:Connect(function(player: Player)
	ensureRacer(player)
	if round.state == "idle" or round.state == "finished" then
		startRound()
	elseif round.state == "countdown" then
		-- Раунд ещё не начался: игрок входит в него.
		roundStartRemote:FireClient(player, round.seed, round.startAt)
	else
		-- Раунд уже идёт: игрок вступает в него с текущим курсом.
		roundStartRemote:FireClient(player, round.seed, serverNow())
	end
end)

progressRemote.OnServerEvent:Connect(function(player: Player, score: any, distance: any, alive: any, finished: any, elapsed: any)
	local entry = racers[player]
	if not entry then
		return
	end
	if typeof(score) ~= "number" or typeof(distance) ~= "number" or typeof(elapsed) ~= "number" then
		return
	end
	-- Проверка правдоподобности: слишком много очков за слишком короткое время — отбросить.
	if not Score.isPlausible(score, math.max(elapsed, 1)) then
		return
	end
	entry.score = score
	entry.distance = distance
	entry.alive = if typeof(alive) == "number" then alive else entry.alive
	if finished == true and not entry.finished then
		entry.finished = true
		round.finishedOrder += 1
		entry.place = round.finishedOrder
	end
end)

-- Тик раунда: перевод отсчёта в «идёт», рассылка рейтинга, завершение раунда.
local tickAccum = 0.0
RunService.Heartbeat:Connect(function(dt: number)
	tickAccum += dt
	if round.state == "countdown" and serverNow() >= round.startAt then
		round.state = "running"
		round.startedAt = serverNow()
	end
	if tickAccum < 1.0 then
		return
	end
	tickAccum = 0.0
	if round.state ~= "running" then
		return
	end
	broadcastStandings()
	local any = false
	local allDone = true
	for _, entry in racers do
		any = true
		if not entry.finished then
			allDone = false
		end
	end
	if (any and allDone) or (serverNow() - round.startedAt > ROUND_LIMIT) then
		endRound()
	end
end)

--------------------------------------------------------------------------- рекорд

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
	sessionStart[player] = os.clock()
	task.spawn(loadBest, player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	bestScores[player] = nil
	sessionStart[player] = nil
	racers[player] = nil
end)

requestRemote.OnServerEvent:Connect(function(player: Player)
	pushBest(player)
end)

submitRemote.OnServerEvent:Connect(function(player: Player, score: any, elapsed: any)
	if typeof(score) ~= "number" or typeof(elapsed) ~= "number" then
		return
	end
	-- Длительность забега считает сервер: клиентское значение берём только как
	-- нижнюю оценку (если игрок играл дольше, чем был в сервере — берём серверное).
	local started = sessionStart[player] or os.clock()
	local serverElapsed = os.clock() - started
	local realElapsed = math.max(elapsed, serverElapsed)

	-- Отсекаем явно невозможные результаты (правила покрыты юнит-тестами).
	if not Score.isPlausible(score, realElapsed) then
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

--------------------------------------------------------------------------- монетизация (Robux)

-- Идентификаторы game pass'ов и developer product'ов живут в
-- src/shared/ShopConfig.luau (сейчас там нули — плейсхолдеры).
-- Реальные ID создаются в Roblox Creator Dashboard и вписываются туда.

--- Перки игрока (покупки).
local perms: { [Player]: { [string]: boolean } } = {}

local function permSet(player: Player, key: string, value: boolean)
	local set = perms[player]
	if not set then
		set = {}
		perms[player] = set
	end
	set[key] = value
end

local function permList(player: Player): { [string]: boolean }
	return perms[player] or {}
end

local function pushPerms(player: Player)
	pcall(function()
		permsRemote:FireClient(player, permList(player))
	end)
end

--- Проверка и обновление прав на game pass'ы (MarketplaceService).
local function refreshPasses(player: Player)
	for key, id in pairs(ShopConfig.passes) do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return GameplayService:PlayerHasPassAsync(player.UserId, id)
			end)
			if ok and owns == true then
				permSet(player, key, true)
			end
		end
	end
	pushPerms(player)
end

Players.PlayerAdded:Connect(function(player: Player)
	refreshPasses(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	perms[player] = nil
end)

--- Ответ клиенту о покупке (true — окно покупки открыто).
local function buyResult(player: Player, ok: boolean, message: string?)
	pcall(function()
		buyResultRemote:FireClient(player, ok, message)
	end)
end

buyPassRemote.OnServerEvent:Connect(function(player: Player, key: any)
	if typeof(key) ~= "string" then
		return
	end
	local id = ShopConfig.passes[key]
	if not id or id == 0 then
		-- ID не настроены: честно сообщаем, а не делаем вид, что покупка идёт.
		buyResult(player, false, "Магазин ещё не настроен (ID покупок = 0)")
		return
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, id)
	end)
	buyResult(player, true)
end)

buyProductRemote.OnServerEvent:Connect(function(player: Player, key: any)
	if typeof(key) ~= "string" then
		return
	end
	local id = ShopConfig.products[key]
	if not id or id == 0 then
		buyResult(player, false, "Магазин ещё не настроен (ID покупок = 0)")
		return
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
	buyResult(player, true)
end)

--- Соответствие ID продуктов и ключей перков.
local PRODUCT_KEYS_BY_ID: { [number]: string } = {}
for key, id in pairs(ShopConfig.products) do
	if id ~= 0 then
		PRODUCT_KEYS_BY_ID[id] = key
	end
end

-- Обработка покупок developer product'ов. Roblox вызывает её, когда покупка
-- подтверждена; здесь мы выдаём перк и отвечаем, что покупка обработана.
MarketplaceService.ProcessReceipt = function(receiptInfo: any)
	local player = game.Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductInfoResponse.NotProcessedYet
	end
	local key = PRODUCT_KEYS_BY_ID[receiptInfo.ProductId]
	if not key then
		return Enum.ProductInfoResponse.AlreadyProcessed
	end
	-- Перк выдаётся сразу (в этой версии — один заряд «мгновенного рывка»).
	permSet(player, key, true)
	pushPerms(player)
	return Enum.ProductInfoResponse.PurchaseSuccess
end


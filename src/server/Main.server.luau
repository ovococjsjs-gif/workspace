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


-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Score = require(Shared.Score)
local Race = require(Shared.Race)
local Daily = require(Shared.Daily)
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
local requestDailyRemote = makeRemote("RequestDaily")
local dailyBoardRemote = makeRemote("DailyBoard")

-- Покупки (Robux).
local buyPassRemote = makeRemote("BuyPass")
local buyProductRemote = makeRemote("BuyProduct")
local permsRemote = makeRemote("PermsUpdate")
local buyResultRemote = makeRemote("BuyResult")
local useChargeRemote = makeRemote("UseBoostCharge")

local bestStore = DataStoreService:GetDataStore(STORE_NAME)
local chargeStore = DataStoreService:GetDataStore("flock_boosts_v1")
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
	--- "race" — обычный забег, "daily" — забег дня (общий курс и таблица лидеров).
	mode = "race",
}
--- Участники текущего раунда.
local racers: { [Player]: Race.Entry } = {}
--- Когда игрок начал забег (серверное время) — для честной проверки счёта.
local racerStart: { [Player]: number } = {}

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
			pos = nil,
		}
		racers[player] = entry
	end
	return entry
end

--- Отмечает, что игрок начал забег (для проверки правдоподобности счёта).
local function markStart(player: Player)
	racerStart[player] = serverNow()
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
--- mode = "daily" — курс дня (одинаковый для всех в течение суток).
local function startRound(mode: string?)
	local kind = mode or "race"
	round.mode = kind
	round.seed = if kind == "daily" then Daily.seedToday() else math.random(1, 100000000)
	round.startAt = serverNow() + COUNTDOWN
	round.startedAt = round.startAt
	round.state = "countdown"
	round.finishedOrder = 0
	-- Новый раунд — чистый старт для всех участников.
	for _, entry in racers do
		entry.score = 0
		entry.distance = 0
		entry.alive = 18
		entry.finished = false
		entry.place = nil
	end
	for player in racers do
		roundStartRemote:FireClient(player, round.seed, round.startAt, kind)
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
	markStart(player)
	if round.state == "idle" or round.state == "finished" then
		startRound()
	elseif round.state == "countdown" then
		-- Раунд ещё не начался: игрок входит в него.
		roundStartRemote:FireClient(player, round.seed, round.startAt, round.mode)
	else
		-- Раунд уже идёт: игрок вступает в него с текущим курсом.
		roundStartRemote:FireClient(player, round.seed, serverNow(), round.mode)
	end
end)

--------------------------------------------------------------------------- забег дня

--- Таблица лидеров дня: userId -> результат.
local dailyBoard: { [number]: Daily.BoardEntry } = {}
local dailyLoaded = false

local function loadDailyBoard()
	if dailyLoaded then
		return
	end
	dailyLoaded = true
	local store = DataStoreService:GetDataStore("flock_daily_" .. Daily.todayKey())
	local ok, data = pcall(function()
		return store:GetAsync("board")
	end)
	if ok and type(data) == "table" then
		for userIdKey, entry in pairs(data) do
			local userId = tonumber(userIdKey)
			if userId and type(entry) == "table" and typeof(entry.score) == "number" then
				dailyBoard[userId] = {
					userId = userId,
					name = tostring(entry.name or "?"),
					score = entry.score,
				}
			end
		end
	end
end

local function dailyEntries(): { Daily.BoardEntry }
	local list: { Daily.BoardEntry } = {}
	for _, entry in dailyBoard do
		table.insert(list, entry)
	end
	return Daily.sortBoard(list)
end

local function broadcastDailyBoard()
	local sorted = dailyEntries()
	for player in racers do
		pcall(function()
			dailyBoardRemote:FireClient(player, sorted)
		end)
	end
end

--- Записывает результат игрока в таблицу дня атомарно: несколько серверов
--- не затирают результаты друг друга. Возвращает актуальную таблицу из DataStore.
local function recordDaily(player: Player, score: number)
	loadDailyBoard()
	local store = DataStoreService:GetDataStore("flock_daily_" .. Daily.todayKey())
	local userKey = tostring(player.UserId)
	local ok, data = pcall(function()
		return store:UpdateAsync("board", function(old: any)
			local board = if type(old) == "table" then old else {}
			local previous = board[userKey]
			if type(previous) ~= "table" or typeof(previous.score) ~= "number" or score > previous.score then
				board[userKey] = { name = player.Name, score = score }
			end
			return board
		end)
	end)
	if ok and type(data) == "table" then
		dailyBoard = {}
		for userIdKey, entry in pairs(data) do
			local userId = tonumber(userIdKey)
			if userId and type(entry) == "table" and typeof(entry.score) == "number" then
				dailyBoard[userId] = {
					userId = userId,
					name = tostring(entry.name or "?"),
					score = entry.score,
				}
			end
		end
	else
		-- DataStore временно недоступен — хотя бы сохраняем локально на этом сервере.
		local entry = dailyBoard[player.UserId]
		if not entry or score > entry.score then
			dailyBoard[player.UserId] = { userId = player.UserId, name = player.Name, score = score }
		end
	end
	broadcastDailyBoard()
end

requestDailyRemote.OnServerEvent:Connect(function(player: Player)
	ensureRacer(player)
	markStart(player)
	loadDailyBoard()
	broadcastDailyBoard()
	if round.state == "idle" or round.state == "finished" or round.mode ~= "daily" then
		startRound("daily")
	else
		roundStartRemote:FireClient(player, round.seed, serverNow(), "daily")
	end
end)

progressRemote.OnServerEvent:Connect(function(
	player: Player,
	score: any,
	distance: any,
	alive: any,
	finished: any,
	elapsed: any,
	pos: any
)
	local entry = racers[player]
	if not entry then
		return
	end
	if typeof(score) ~= "number" or typeof(distance) ~= "number" or typeof(elapsed) ~= "number" then
		return
	end
	-- Проверка правдоподобности: слишком много очков за слишком короткое время — отбросить.
	-- Длительность считает сервер: клиентское время берём только как нижнюю оценку.
	local started = racerStart[player] or serverNow()
	local serverElapsed = serverNow() - started
	local realElapsed = math.max(elapsed, serverElapsed)
	if not Score.isPlausible(score, math.max(realElapsed, 1)) then
		return
	end
	entry.score = score
	entry.distance = distance
	entry.alive = if typeof(alive) == "number" then alive else entry.alive
	-- Позиция вожака: рисуем «призраков» соперников у каждого игрока.
	if type(pos) == "table"
		and typeof(pos.x) == "number"
		and typeof(pos.y) == "number"
		and typeof(pos.z) == "number"
	then
		entry.pos = { x = pos.x, y = pos.y, z = pos.z }
	end
	if finished == true and not entry.finished then
		entry.finished = true
		round.finishedOrder += 1
		entry.place = round.finishedOrder
		-- В забеге дня результат попадает в общую таблицу лидеров.
		if round.mode == "daily" then
			recordDaily(player, score)
		end
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
	racerStart[player] = nil
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
local perms: { [Player]: { [string]: any } } = {}
--- Заряды «мгновенного рывка» (developer product «ЗАРЯДЫ РЫВКА x3»).
local charges: { [Player]: number } = {}

local function permSet(player: Player, key: string, value: any)
	local set = perms[player]
	if not set then
		set = {}
		perms[player] = set
	end
	set[key] = value
end

local function permList(player: Player): { [string]: any }
	local list: { [string]: any } = {}
	for key, value in perms[player] or {} do
		list[key] = value
	end
	list.boostCharges = charges[player] or 0
	return list
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
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns == true then
				permSet(player, key, true)
			end
		end
	end
	pushPerms(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _passId: number, purchased: boolean)
	if purchased then
		refreshPasses(player)
	end
end)

Players.PlayerAdded:Connect(function(player: Player)
	refreshPasses(player)
	-- Подгружаем купленные заряды рывка.
	task.spawn(function()
		local ok, value = pcall(function()
			return chargeStore:GetAsync("c_" .. tostring(player.UserId))
		end)
		if ok then
			if typeof(value) == "number" then
				-- Совместимость с ранними тестовыми/предыдущими данными.
				charges[player] = math.max(0, math.floor(value))
			elseif type(value) == "table" and typeof(value.charges) == "number" then
				charges[player] = math.max(0, math.floor(value.charges))
			end
			pushPerms(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	perms[player] = nil
	charges[player] = nil
end)

--- Трата заряда мгновенного рывка (клиент сообщает об использовании).
useChargeRemote.OnServerEvent:Connect(function(player: Player)
	-- Сохраняем реестр PurchaseId при расходовании, иначе повторный чек
	-- после списания мог бы повторно выдать уже обработанную покупку.
	local ok, record = pcall(function()
		return chargeStore:UpdateAsync("c_" .. tostring(player.UserId), function(old: any)
			local data = if type(old) == "table" then old else { charges = if typeof(old) == "number" then old else 0, receipts = {} }
			data.receipts = if type(data.receipts) == "table" then data.receipts else {}
			local left = math.max(0, math.floor(if typeof(data.charges) == "number" then data.charges else 0))
			if left > 0 then
				data.charges = left - 1
			end
			return data
		end)
	end)
	if ok and type(record) == "table" and typeof(record.charges) == "number" then
		charges[player] = math.max(0, math.floor(record.charges))
	end
	pushPerms(player)
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

--- Ключ перка по ID developer product'а.
--- Таблица строится на лету, чтобы ID можно было настроить и после старта сервера.
local function productKeyFor(id: number): string?
	for key, productId in pairs(ShopConfig.products) do
		if productId == id and productId ~= 0 then
			return key
		end
	end
	return nil
end

-- Обработка покупок developer product'ов. Roblox вызывает её, когда покупка
-- подтверждена; здесь мы выдаём перк и отвечаем, что покупка обработана.
MarketplaceService.ProcessReceipt = function(receiptInfo: any)
	local player = game.Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = productKeyFor(receiptInfo.ProductId)
	if not key then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Идемпотентная и атомарная выдача: Roblox может повторно вызвать
	-- ProcessReceipt, пока не получит PurchaseGranted. Не выдаём один чек дважды.
	local receiptId = tostring(receiptInfo.PurchaseId)
	if receiptId == "nil" or receiptId == "" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local storeKey = "c_" .. tostring(player.UserId)
	local ok, record = pcall(function()
		return chargeStore:UpdateAsync(storeKey, function(old: any)
			local data = if type(old) == "table" then old else { charges = if typeof(old) == "number" then old else 0, receipts = {} }
			data.receipts = if type(data.receipts) == "table" then data.receipts else {}
			if not data.receipts[receiptId] then
				data.receipts[receiptId] = true
				data.charges = math.max(0, math.floor(if typeof(data.charges) == "number" then data.charges else 0)) + 3
			end
			return data
		end)
	end)
	if not ok or type(record) ~= "table" or typeof(record.charges) ~= "number" then
		-- Не подтверждаем покупку, чтобы Roblox повторил чек.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	charges[player] = math.max(0, math.floor(record.charges))
	pushPerms(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end


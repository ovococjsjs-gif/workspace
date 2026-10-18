--[=[
	СТАЯ — клиентский слой.
	Вся логика игры живёт в чистом модуле ReplicatedStorage.FlockShared.Game
	(её можно прогнать headless — см. tests/test_simulation.luau).
	Здесь: ввод, камера, визуал, звук, HUD, обмен с сервером (рекорд).
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Vec = require(Shared.Vec)
local Config = require(Shared.Config)
local Course = require(Shared.Course)
local Game = require(Shared.Game)
local Score = require(Shared.Score)
local Race = require(Shared.Race)
local Perms = require(Shared.Perms)

local Input = require(script.Parent.Input)
local World = require(script.Parent.World)
local Views = require(script.Parent.Views)
local HUD = require(script.Parent.HUD)
local Audio = require(script.Parent.Audio)

local player = Players.LocalPlayer
local UP = Vec.new(0, 1, 0)

type ClientState = {
	mode: string, -- "menu" | "playing" | "over"
	game: Game.Game?,
	best: number,
	--- Рекорд уже побит в текущем забеге (для одного раза праздновать).
	beatBest: boolean,
	--- Сид общего забега (задаёт курс; одинаковый у всех игроков).
	roundSeed: number?,
	--- Серверное время старта забега.
	roundStartAt: number?,
	--- Ждём ответа сервера на запрос забега.
	roundRequested: boolean,
	--- Крайний срок ожидания ответа сервера (запасной вариант).
	roundDeadline: number,
	--- Живой рейтинг забега.
	standings: { Race.Entry },
	--- Перки игрока (покупки за Robux).
	perms: Perms.Perms,
	--- Итоговое место игрока в забеге.
	place: number?,
	--- Сколько игроков в забеге.
	players: number,
	--- Счётчик отправки прогресса серверу.
	progressTimer: number,
	--- Итоговый счёт последнего забега (нужен для финального экрана).
	finalScore: number,
	--- Статистика последнего забега.
	finalStats: string,
}

local state: ClientState = {
	mode = "menu", -- "menu" | "playing" | "over"
	game = nil,
	best = 0,
	beatBest = false,
	roundSeed = nil,
	roundStartAt = nil,
	roundRequested = false,
	roundDeadline = 0,
	standings = {},
	perms = Perms.new(),
	place = nil,
	players = 0,
	progressTimer = 0,
	finalScore = 0,
	finalStats = "",
}

--- Кто мы для сервера: нужен UserId, чтобы подсветить свою строку в рейтинге.
local MY_USER_ID = player.UserId

--- Перерисовывает финальный экран (используется, когда пришли итоги забега).
local showEndScreen: () -> ()

local panicWarned = false
local camera = Workspace.CurrentCamera
local camPos = Vec.new(0, 36, -30)
--- Дистанция камеры (плавно отъезжает на рывке) и поле зрения.
local camBack = 30
local camFov = 78

--------------------------------------------------------------------------- рекорд

local function setupRemotes()
	local ok, remotes = pcall(function()
		return ReplicatedStorage:WaitForChild("FlockRemotes", 10)
	end)
	if not ok or not remotes then
		return nil
	end
	return remotes
end

local remotes = setupRemotes()

--- Достаёт ремоут по имени (nil, если сервер ещё не создал).
local function remote(name: string): RemoteEvent?
	if not remotes then
		return nil
	end
	local found = remotes:FindFirstChild(name)
	return if found then (found :: RemoteEvent) else nil
end

local submitRemote = remote("SubmitScore")
local bestRemote = remote("BestScore")
local requestRemote = remote("RequestBest")
local roundStartRemote = remote("RoundStart")
local standingsRemote = remote("Standings")
local roundEndRemote = remote("RoundEnd")
local progressRemote = remote("Progress")
local requestRoundRemote = remote("RequestRound")
local buyPassRemote = remote("BuyPass")
local buyProductRemote = remote("BuyProduct")
local permsRemote = remote("PermsUpdate")
local buyResultRemote = remote("BuyResult")
local useChargeRemote = remote("UseBoostCharge")

if bestRemote then
	bestRemote.OnClientEvent:Connect(function(value: number)
		if typeof(value) == "number" then
			state.best = value
			HUD.setBest(state.best)
		end
	end)
end

local function requestBest()
	if requestRemote then
		pcall(function()
			requestRemote:FireServer()
		end)
	end
end

--------------------------------------------------------------------------- гонка

--- Серверное время (одинаково у всех клиентов сервера).
local function serverNow(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return os.clock()
end

--- Запросить общий забег: сервер ответит сидом и временем старта.
local function requestRound()
	state.mode = "menu"
	state.roundRequested = true
	state.roundDeadline = os.clock() + 3
	state.roundStartAt = nil
	HUD.showEnd(false, 0, 0, "")
	HUD.showStart(false)
	HUD.setCountdown("ПОДГОТОВКА")
	if requestRoundRemote then
		pcall(function()
			requestRoundRemote:FireServer()
		end)
	end
end

if roundStartRemote then
	roundStartRemote.OnClientEvent:Connect(function(seed: any, startAt: any)
		if typeof(seed) ~= "number" then
			return
		end
		state.roundSeed = seed
		state.roundStartAt = if typeof(startAt) == "number" then startAt else serverNow()
		state.roundRequested = false
	end)
end

--- Приём рейтинга забега.
local function applyStandings(entries: any)
	if type(entries) ~= "table" then
		return
	end
	local list: { Race.Entry } = {}
	for _, entry in entries do
		if type(entry) == "table" then
			table.insert(list, entry)
		end
	end
	state.standings = list
	state.players = #list
	state.place = Race.placeOf(list, MY_USER_ID)
	HUD.setStandings(list, MY_USER_ID)
	-- «Призраки» соперников: видно, где летят другие стаи.
	Views.updateGhosts(list, MY_USER_ID)
	-- Если забег уже закончился, обновляем финальный экран (появилось место).
	if state.mode == "over" then
		showEndScreen()
	end
end

if standingsRemote then
	standingsRemote.OnClientEvent:Connect(applyStandings)
end

if roundEndRemote then
	roundEndRemote.OnClientEvent:Connect(function(entries: any)
		applyStandings(entries)
		if state.mode == "over" then
			showEndScreen()
		end
	end)
end

--------------------------------------------------------------------------- перки (покупки)

if permsRemote then
	permsRemote.OnClientEvent:Connect(function(data: any)
		state.perms = Perms.fromTable(data)
		HUD.setShopState(state.perms)
		-- Перки применяются к текущему забегу сразу.
		if state.game then
			state.game.perms = state.perms
		end
	end)
end

if buyResultRemote then
	buyResultRemote.OnClientEvent:Connect(function(ok: any, message: any)
		if ok == true then
			HUD.toast("ОКНО ПОКУПКИ ОТКРЫТО", HUD.COLOR_ACCENT)
		elseif typeof(message) == "string" then
			HUD.toast(string.upper(message), HUD.COLOR_BAD)
		end
	end)
end

--- Купить перк (game pass) или продукт (developer product).
local function buy(key: string)
	if key == "boostPack" then
		if buyProductRemote then
			pcall(function()
				buyProductRemote:FireServer(key)
			end)
		end
		return
	end
	if buyPassRemote then
		pcall(function()
			buyPassRemote:FireServer(key)
		end)
	end
end

--------------------------------------------------------------------------- жизненный цикл

local function resetRun()
	state.game = Game.new(state.roundSeed, state.perms)
	local game = state.game
	HUD.setScore(0)
	HUD.setCombo(1)
	HUD.setFlock(Game.flockTotal(game), Game.flockTotal(game))
	HUD.setPhase(Game.phase(game).name, 1)
	HUD.setHint("WASD — курс, Space/Shift — высота")
	HUD.setDanger(0)
	HUD.setCalm(1)
	state.beatBest = false
	HUD.setTime(0)
	HUD.setPhaseProgress(0)
	HUD.setBoost(0, Config.leader.boostDuration + Config.leader.boostCooldown, false)
	Input.consumeBoost() -- сбросить клик, сделанный в меню
	panicWarned = false
	HUD.setRingTimer(nil, nil)
	Views.reset()
end

local function endRun(finalScore: number)
	if state.mode ~= "playing" then
		return
	end
	state.mode = "over"
	Input.enabled = false
	HUD.setTouchStick(false, 0, 0, 0, 0)
	-- Итоговая статистика забега: кольца, чистые кольца, макс. комбо, время.
	local stats = ""
	local game = state.game
	if game then
		local sc = game.score
		local minutes = math.floor(game.time / 60)
		local seconds = math.floor(game.time % 60)
		local alive = Game.flockAlive(game)
		local bonus = Score.endFlockBonus(alive, Game.flockTotal(game))
		stats = string.format(
			"КОЛЕЦ %d  ·  ЧИСТЫХ %d  ·  МАКС. КОМБО ×%d  ·  ВРЕМЯ %d:%02d",
			sc.rings, sc.perfects, sc.bestCombo, minutes, seconds
		)
		if bonus > 0 then
			stats ..= string.format("  ·  БОНУС ЗА СТАЮ +%d", bonus)
		end
	end
	state.finalScore = finalScore
	state.finalStats = stats
	showEndScreen()
	Audio.fail()
	if submitRemote then
		pcall(function()
			submitRemote:FireServer(finalScore, state.game and state.game.time or 0)
		end)
	end
end

--- Финальный экран: счёт, рекорд, статистика и место в забеге.
showEndScreen = function()
	HUD.showEnd(
		true,
		state.finalScore,
		math.max(state.best, state.finalScore),
		state.finalStats,
		state.place,
		state.players
	)
end

local function startRun()
	state.mode = "playing"
	Input.enabled = true
	HUD.showStart(false)
	HUD.showEnd(false, 0, 0, "")
	HUD.setCountdown(nil)
	state.roundStartAt = nil
	state.place = nil
	resetRun()
	Audio.ui()
end

--------------------------------------------------------------------------- обработка событий игры

local function handleEvent(event: Game.GameEvent)
	if event.phaseIndex and event.phaseName then
		HUD.setPhase(event.phaseName, event.phaseIndex)
		World.setPhase(event.phaseIndex)
		HUD.setHint(Game.phase(state.game).hint)
		HUD.toast("ФАЗА " .. tostring(event.phaseIndex) .. ": " .. event.phaseName, HUD.COLOR_ACCENT)
	end

	for _ = 1, event.recovered do
		HUD.toast("ПТИЦА В СТРОЮ +" .. tostring(Config.score.recoverBonus), HUD.COLOR_GOOD)
		Audio.recover()
	end
	if event.scattered > 0 then
		HUD.toast("ПТИЦА ПОТЕРЯНА", HUD.COLOR_BAD)
	end

	for _, ring in event.rings do
		if ring.result == "perfect" then
			Views.popRing(ring.id, state.game and state.game.time or 0)
			HUD.toast("ЧИСТО! " .. tostring(ring.passedCount) .. "/" .. tostring(ring.totalCount) .. "  +" .. tostring(ring.points), HUD.COLOR_GOOD)
			HUD.flashScreen(HUD.COLOR_GOOD, 0.22)
			HUD.setCombo(state.game and state.game.score.combo or 1)
			Audio.perfect(state.game and state.game.score.combo or 1)
		elseif ring.result == "partial" then
			HUD.toast(
				"ЧАСТИЧНО " .. tostring(ring.passedCount) .. "/" .. tostring(ring.totalCount) .. "  +" .. tostring(ring.points),
				HUD.COLOR_ACCENT
			)
			HUD.setCombo(state.game and state.game.score.combo or 1)
			Audio.ring(state.game and state.game.score.combo or 1)
		else
			HUD.toast("КОЛЬЦО ПРОПУЩЕНО", HUD.COLOR_BAD)
			HUD.flashScreen(Color3.fromRGB(255, 90, 80), 0.18)
			HUD.shake(0.9)
			HUD.setCombo(state.game and state.game.score.combo or 1)
			Audio.fail()
		end
		HUD.setScore(state.game and state.game.score.score or 0)
	end

	if event.mercy then
		HUD.toast("ЗАТИШЬЕ — ПОСЛЕДНИЙ ШАНС СОБРАТЬ СТАЮ", HUD.COLOR_GOOD)
		Audio.recover()
	end

	if event.boost then
		HUD.toast("РЫВОК!", HUD.COLOR_ACCENT)
		Audio.boost()
	end

	if event.gameOver then
		local game = state.game
		local final = 0
		if game then
			final = Score.finalScore(game.score, Game.flockAlive(game), Game.flockTotal(game))
		end
		endRun(final)
	end
end

--- Указывает стрелкой на ближайшую потерянную птицу.
local function updateStrayArrow(game: Game.Game)
	if not camera then
		HUD.setStrayDirection(nil, nil)
		return
	end
	local camPos = camera.CFrame.Position
	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	local forward = camera.CFrame.LookVector

	local bestAngle: number? = nil
	local bestDist = math.huge
	for _, bird in game.flock.birds do
		if bird.mode == "lost" then
			local toBird = Vec.sub(bird.pos, camPos)
			local dist = Vec.len(toBird)
			if dist < bestDist then
				bestDist = dist
				local sx = toBird.x * right.x + toBird.y * right.y + toBird.z * right.z
				local sy = toBird.x * up.x + toBird.y * up.y + toBird.z * up.z
				local sz = toBird.x * forward.x + toBird.y * forward.y + toBird.z * forward.z
				local angle = math.atan2(-sy, sx)
				-- Птица за спиной: стрелка должна показывать «назад».
				if sz < 0 then
					angle = angle + math.pi
				end
				bestAngle = angle
			end
		end
	end
	HUD.setStrayDirection(bestAngle, bestDist)
end

--------------------------------------------------------------------------- камера

local function updateCamera(dt: number)
	if not camera or not state.game then
		return
	end
	local game = state.game
	local cp = Course.pointAt(game.leaderPos.z)
	-- На рывке камера отъезжает и добавляет перспективы: видно, что скорость выросла.
	local boosting = game.boostTime > 0
	local wantBack = if boosting then 39 else 30
	camBack = camBack + (wantBack - camBack) * math.clamp(dt * 4, 0, 1)
	local target = Vec.add(game.leaderPos, Vec.scale(cp.tangent, -camBack))
	target = Vec.add(target, Vec.new(0, 16, 0))
	local k = math.clamp(dt * 6, 0, 1)
	camPos = Vec.lerp(camPos, target, k)
	local look = Vec.add(game.leaderPos, Vec.scale(cp.tangent, 14))
	local shake = HUD.getShakeOffset()
	camera.CFrame = CFrame.lookAt(
		Vector3.new(camPos.x + shake.X, camPos.y + shake.Y, camPos.z + shake.Z),
		Vector3.new(look.x, look.y, look.z)
	)
	-- Поле зрения плавно раскрывается на рывке.
	local wantFov = if boosting then 92 else 78
	camFov = camFov + (wantFov - camFov) * math.clamp(dt * 8, 0, 1)
	camera.FieldOfView = camFov
end

--- Прячем стандартного персонажа: игрок управляет «кайтом», а не телом.
local function hideCharacter(character: Model?)
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		end
	end
	pcall(function()
		character:PivotTo(CFrame.new(0, -400, 0))
	end)
end

--------------------------------------------------------------------------- запуск

local function boot()
	hideCharacter(player.Character)
	player.CharacterAdded:Connect(function(character: Model)
		task.defer(hideCharacter, character)
	end)

	World.build()
	World.setPhase(1)
	Views.build(Config.flockSize)
	HUD.build()
	Input.start()
	resetRun()
	HUD.showStart(true)
	HUD.setBest(state.best)
	requestBest()

	if HUD.startButton then
		HUD.startButton.MouseButton1Click:Connect(function()
			if state.mode == "menu" then
				requestRound()
			end
		end)
	end
	if HUD.againButton then
		HUD.againButton.MouseButton1Click:Connect(function()
			if state.mode == "over" then
				requestRound()
			end
		end)
	end
	if HUD.shopButton then
		HUD.shopButton.MouseButton1Click:Connect(function()
			HUD.showShop(true)
		end)
	end
	if HUD.shopCloseButton then
		HUD.shopCloseButton.MouseButton1Click:Connect(function()
			HUD.showShop(false)
		end)
	end
	-- Кнопки покупок в магазине.
	for key, button in pairs(HUD.shopButtons or {}) do
		local itemKey = key
		local itemButton = button
		itemButton.MouseButton1Click:Connect(function()
			buy(itemKey)
		end)
	end
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(dt, 1 / 20)
		HUD.updateShake(step)

		-- Обратный отсчёт и старт общего забега.
		if state.mode == "menu" then
			if state.roundStartAt then
				local remaining = state.roundStartAt - serverNow()
				if remaining <= 0 then
					state.roundStartAt = nil
					HUD.setCountdown(nil)
					startRun()
				else
					local sec = math.ceil(remaining)
					if sec <= 3 then
						HUD.setCountdown(tostring(sec))
					else
						HUD.setCountdown("ПОДГОТОВКА")
					end
				end
			elseif state.roundRequested and os.clock() > state.roundDeadline then
				-- Сервер не ответил: не блокируем игру, стартуем локально.
				state.roundRequested = false
				state.roundSeed = math.random(1, 100000000)
				HUD.setCountdown(nil)
				startRun()
			end
		end

		local game = state.game
		if state.mode == "playing" and game then
			local ax, ay, az = Input.getAxes()
			local boostRequest = Input.consumeBoost()
			-- Заряд «мгновенного рывка»: срабатывает, даже когда обычный рывок на перезарядке.
			if boostRequest and state.perms.boostCharges > 0 and game.boostCooldown > 0 then
				state.perms.boostCharges -= 1
				game.boostTime = Config.leader.boostDuration
				game.boostCooldown = 0
				boostRequest = false
				if useChargeRemote then
					pcall(function()
						useChargeRemote:FireServer()
					end)
				end
				HUD.toast("РЫВОК ЗА ЗАРЯД!", HUD.COLOR_ACCENT)
			end
			local events = Game.step(game, step, { x = ax, y = ay, z = az, boost = boostRequest })
			for _, event in events do
				handleEvent(event)
			end
			HUD.setFlock(Game.flockAlive(game), Game.flockTotal(game))
			HUD.setBoost(
				game.boostCooldown,
				Config.leader.boostDuration + Config.leader.boostCooldown,
				game.boostTime > 0
			)
			local panic = game.flock.panic
			HUD.setCalm(1 - panic)
			HUD.setTime(game.time)
			if not state.beatBest and state.best > 0 and game.score.score > state.best then
				state.beatBest = true
				HUD.toast("НОВЫЙ РЕКОРД!", HUD.COLOR_ACCENT)
				HUD.flashScreen(HUD.COLOR_ACCENT, 0.25)
				Audio.perfect(5)
			end
			HUD.setMercy(game.mercyTime > 0, game.mercyTime)
			local touchActive, touchOx, touchOy, touchCx, touchCy = Input.getTouchStick()
			HUD.setTouchStick(touchActive, touchOx, touchOy, touchCx, touchCy)
			local wind = Game.windVector(game)
			local side = 0
			if camera then
				local right = camera.CFrame.RightVector
				side = wind.x * right.x + wind.y * right.y + wind.z * right.z
			end
			HUD.setWind(Vec.len(wind), side)
			HUD.setPhaseProgress((game.phaseIndex - 1) / 3)
			updateStrayArrow(game)
			if panic > 0.55 and not panicWarned then
				panicWarned = true
				Audio.panic(panic)
				HUD.toast("СТАЯ ПАНИКУЕТ — ВЕДИ СПОКОЙНЕЕ", HUD.COLOR_BAD)
				HUD.shake(0.5)
			elseif panic < 0.3 then
				panicWarned = false
			end
			local alive = Game.flockAlive(game)
			HUD.setDanger(1 - (alive / math.max(1, Game.flockTotal(game))))
			HUD.setRingTimer(game.ringGraceLeft, game.ringGraceTotal)

			-- Прогресс для живого рейтинга (4 раза в секунду).
			state.progressTimer += step
			if state.progressTimer >= 0.25 then
				state.progressTimer = 0
				if progressRemote then
					pcall(function()
						progressRemote:FireServer(
							game.score.score,
							game.leaderPos.z,
							Game.flockAlive(game),
							game.mode == "over",
							game.time,
							{ x = game.leaderPos.x, y = game.leaderPos.y, z = game.leaderPos.z }
						)
					end)
				end
			end
		end

		if state.game then
			local cp = Course.pointAt(state.game.leaderPos.z)
			World.update(state.game.leaderPos)
			Views.updateLeader(
				state.game.leaderPos,
				state.game.leaderVel,
				cp.tangent,
				state.game.flock.panic,
				state.game.boostTime > 0
			)
			Views.updateBirds(state.game.flock)
			Views.updateRings(state.game.rings, step, state.game.time)
			Views.updateObstacles(state.game.obstacles, state.game.time)
		end
		updateCamera(step)
	end)
end

boot()

-- Небольшой хук для headless-проверок (в Roblox значение LocalScript игнорируется).
return {
	getState = function(): ClientState
		return state
	end,
}

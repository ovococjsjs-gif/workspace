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
local Flock = require(Shared.Flock)

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
}

local state: ClientState = {
	mode = "menu", -- "menu" | "playing" | "over"
	game = nil,
	best = 0,
}

local panicWarned = false
local camera = Workspace.CurrentCamera
local camPos = Vec.new(0, 36, -30)

--------------------------------------------------------------------------- рекорд

local function setupRemotes()
	local ok, remotes = pcall(function()
		return ReplicatedStorage:WaitForChild("FlockRemotes", 10)
	end)
	if not ok or not remotes then
		return nil, nil, nil
	end
	return remotes:FindFirstChild("SubmitScore"),
		remotes:FindFirstChild("BestScore"),
		remotes:FindFirstChild("RequestBest")
end

local submitRemote, bestRemote, requestRemote = setupRemotes()

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

--------------------------------------------------------------------------- жизненный цикл

local function resetRun()
	state.game = Game.new()
	local game = state.game
	HUD.setScore(0)
	HUD.setCombo(1)
	HUD.setFlock(Game.flockTotal(game), Game.flockTotal(game))
	HUD.setPhase(Game.phase(game).name, 1)
	HUD.setHint("WASD — курс, Space/Shift — высота")
	HUD.setDanger(0)
	HUD.setCalm(1)
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
	HUD.showEnd(true, finalScore, math.max(state.best, finalScore))
	Audio.fail()
	if submitRemote then
		pcall(function()
			submitRemote:FireServer(finalScore, state.game and state.game.time or 0)
		end)
	end
end

local function startRun()
	state.mode = "playing"
	Input.enabled = true
	HUD.showStart(false)
	HUD.showEnd(false, 0, 0)
	resetRun()
	Audio.ui()
end

--------------------------------------------------------------------------- обработка событий игры

local function handleEvent(event: Game.GameEvent)
	if event.phaseIndex and event.phaseName then
		HUD.setPhase(event.phaseName, event.phaseIndex)
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
			HUD.toast("ЧИСТО! +" .. tostring(ring.points), HUD.COLOR_GOOD)
			HUD.flashScreen(HUD.COLOR_GOOD, 0.22)
			HUD.setCombo(state.game and state.game.score.combo or 1)
			Audio.perfect(state.game and state.game.score.combo or 1)
		elseif ring.result == "partial" then
			HUD.toast("ЧАСТИЧНО +" .. tostring(ring.points), HUD.COLOR_ACCENT)
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

	if event.boost then
		HUD.toast("РЫВОК!", HUD.COLOR_ACCENT)
		Audio.boost()
	end

	if event.gameOver then
		endRun(state.game and state.game.score.score or 0)
	end
end

--------------------------------------------------------------------------- камера

local function updateCamera(dt: number)
	if not camera or not state.game then
		return
	end
	local cp = Course.pointAt(state.game.leaderPos.z)
	local target = Vec.add(state.game.leaderPos, Vec.scale(cp.tangent, -30))
	target = Vec.add(target, Vec.new(0, 16, 0))
	local k = math.clamp(dt * 6, 0, 1)
	camPos = Vec.lerp(camPos, target, k)
	local look = Vec.add(state.game.leaderPos, Vec.scale(cp.tangent, 14))
	local shake = HUD.getShakeOffset()
	camera.CFrame = CFrame.lookAt(
		Vector3.new(camPos.x + shake.X, camPos.y + shake.Y, camPos.z + shake.Z),
		Vector3.new(look.x, look.y, look.z)
	)
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
				startRun()
			end
		end)
	end
	if HUD.againButton then
		HUD.againButton.MouseButton1Click:Connect(function()
			if state.mode == "over" then
				startRun()
			end
		end)
	end
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	RunService.Heartbeat:Connect(function(dt: number)
		local step = math.min(dt, 1 / 20)
		HUD.updateShake(step)

		local game = state.game
		if state.mode == "playing" and game then
			local ax, ay, az = Input.getAxes()
			local events = Game.step(game, step, { x = ax, y = ay, z = az, boost = Input.consumeBoost() })
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

return {}

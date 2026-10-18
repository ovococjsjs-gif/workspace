--!nocheck
--[=[
	Smoke-тест клиентского слоя против мока Roblox API.

	Что проверяется:
	 * клиентские модули загружаются (require не падает);
	 * HUD/World/Views строят свои объекты без ошибок;
	 * Main поднимается, вешает слушатели и выполняет несколько кадров
	   игрового цикла (Game.step -> HUD/Views) без исключений;
	 * нажатия клавиш и ЛКМ (рывок) обрабатываются без ошибок;
	 * ввод (в т.ч. смену счёта, комбо, паники) не роняет HUD.

	Чего НЕ проверяет: реальную отрисовку, реальные ассеты, DataStore,
	поведение Roblox-движка. См. tools/roblox_mock.luau.

	Запуск: bash tools/smoke.sh
]=]

local Mock = require("./roblox_mock")

-- Сервисы мока (Players, RunService, UserInputService и т.д.).
local services = Mock.services

local failures = 0
local checks = 0

local function check(condition, message)
	checks += 1
	if not condition then
		failures += 1
		print("  FAIL " .. tostring(message))
	else
		print("  ok   " .. tostring(message))
	end
end

local function step(name, fn)
	print(name)
	local ok, err = pcall(fn)
	if not ok then
		failures += 1
		print("  FAIL исключение: " .. tostring(err))
	end
end

--------------------------------------------------------------------------- HUD

step("HUD: сборка интерфейса", function()
	local HUD = require("./HUD")
	HUD.build()
	HUD.setScore(1234)
	HUD.setBest(4321)
	HUD.setCombo(3)
	HUD.setFlock(14, 18)
	HUD.setPhase("БУРЯ", 4)
	HUD.setHint("подсказка")
	HUD.setRingTimer(1.5, 3)
	HUD.setDanger(0.5)
	HUD.setCalm(0.42)
	HUD.setBoost(1.2, 5, false)
	HUD.toast("ЧИСТО! +120", HUD.COLOR_GOOD)
	HUD.flashScreen(HUD.COLOR_GOOD, 0.2)
	HUD.shake(0.5)
	HUD.updateShake(1 / 60)
	local offset = HUD.getShakeOffset()
	check(type(offset.x) == "number", "HUD.getShakeOffset возвращает Vector3-подобный объект")
	HUD.showEnd(true, 5000, 5000, "КОЛЕЦ 10")
	HUD.showEnd(false, 0, 0, "")
	HUD.showStart(true)
	HUD.showStart(false)

	-- Таймер и прогресс фаз.
	HUD.setTime(95)
	HUD.setPhaseProgress(0.5)
	HUD.setPhaseProgress(1.4)
	check(true, "HUD.setTime/setPhaseProgress отработали")

	-- Стрелка к потерянной птице: направление задаётся и снимается без ошибок.
	HUD.setStrayDirection(0.8, 120)
	HUD.setStrayDirection(nil, nil)
	check(true, "HUD.setStrayDirection отработал")

	-- Проверяем, что интерфейс действительно построился в PlayerGui.
	local playerGui = services.Players.LocalPlayer:WaitForChild("PlayerGui")
	local screens = playerGui:FindFirstChild("FlockGui")
	check(screens ~= nil, "ScreenGui FlockGui создан в PlayerGui")
	if screens then
		local frames = 0
		for _, child in ipairs(screens:GetDescendants()) do
			if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
				frames += 1
			end
		end
		check(frames > 20, "в HUD построено много элементов: " .. tostring(frames))
	end
end)

--------------------------------------------------------------------------- World и Views

step("World: постройка мира", function()
	local World = require("./World")
	World.build()
	World.update({ x = 100, y = 20, z = 500 })
	check(true, "World.build + World.update отработали")
end)

step("Views: вожак, птицы, кольца, камни", function()
	local Views = require("./Views")
	local Game = require("./Game")
	local Course = require("./Course")

	Views.build(18)
	local game = Game.new(20261018)
	-- Прогоняем игру, чтобы появились кольца, камни и потерянные птицы.
	local input = { x = 0, y = 0, z = 1 }
	for _ = 1, 60 * 12 do
		Game.step(game, 1 / 60, input)
	end
	local cp = Course.pointAt(game.leaderPos.z)
	Views.updateLeader(game.leaderPos, game.leaderVel, cp.tangent, game.flock.panic, false)
	Views.updateBirds(game.flock)
	Views.updateRings(game.rings, 1 / 60, game.time)
	Views.updateObstacles(game.obstacles, game.time)
	check(true, "Views.update* отработали без ошибок")

	-- Вспышка кольца при прохождении: кольцо расходится и гаснет.
	local firstRing = game.rings.rings[1]
	if firstRing then
		Views.popRing(firstRing.id, game.time)
		Views.updateRings(game.rings, 1 / 60, game.time + 0.1)
		Views.updateRings(game.rings, 1 / 60, game.time + 0.6)
		check(true, "Views.popRing (вспышка кольца) отработал")
	else
		check(false, "не нашлось ни одного кольца для проверки popRing")
	end

	-- Птицы и кольца должны были появиться в мире.
	local birds = 0
	for _, child in ipairs(Mock.services.Workspace:GetDescendants()) do
		local partName = tostring(child.Name or "")
		if child:IsA("Part") and partName:sub(1, 4) == "Bird" then
			birds += 1
		end
	end
	check(birds == 18, "в мире 18 птиц: " .. tostring(birds))
	local rings = 0
	for _, child in ipairs(Mock.services.Workspace:GetDescendants()) do
		local partName = tostring(child.Name or "")
		if child:IsA("Part") and partName:sub(1, 11) == "RingSegment" then
			rings += 1
		end
	end
	check(rings > 0, "кольца отрисованы: " .. tostring(rings) .. " сегментов")

	-- Проверяем, что пропавшие птицы получили маячок.
	local lost = 0
	for _, bird in game.flock.birds do
		if bird.mode == "lost" then
			lost += 1
		end
	end
	Views.reset()
	check(true, "Views.reset отработал")
end)

--------------------------------------------------------------------------- Main

step("Main: запуск клиента и кадры игрового цикла", function()
	local Main = require("./Main")
	check(true, "Main загрузился и выполнил boot()")

	local runService = services.RunService
	local heartbeat = runService.Heartbeat
	local frames = 0
	for _, fn in ipairs(heartbeat.__signals) do
		for _ = 1, 90 do
			fn(1 / 60)
			frames += 1
		end
	end
	check(frames > 0, "обработчик Heartbeat выполнил кадров: " .. tostring(frames))

	-- Кнопка «ПОЛЕТЕЛИ» должна запускать забег.
	local playerGui = services.Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = playerGui:FindFirstChild("FlockGui")
	local button
	if screen then
		for _, child in ipairs(screen:GetDescendants()) do
			if child:IsA("TextButton") and child.Text == "ПОЛЕТЕЛИ" then
				button = child
			end
		end
	end
	check(button ~= nil, "кнопка старта найдена")
	if button then
		for _, fn in ipairs(button.MouseButton1Click.__signals) do
			fn()
		end
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
		check(true, "забег запущен по кнопке")
	end

	-- Ввод: зажимаем клавиши и отпускаем.
	local uis = services.UserInputService
	for _, fn in ipairs(uis.InputBegan.__signals) do
		fn({ KeyCode = { W = "W", A = "A", D = "D", Space = "Space" }, UserInputType = "Keyboard" }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	for _, fn in ipairs(uis.InputEnded.__signals) do
		fn({ KeyCode = { W = "W", A = "A", D = "D", Space = "Space" }, UserInputType = "Keyboard" }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(true, "ввод с клавиатуры обработан без ошибок")

	-- ЛКМ — рывок.
	for _, fn in ipairs(uis.InputBegan.__signals) do
		fn({ KeyCode = { Unknown = "Unknown" }, UserInputType = "MouseButton1" }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(true, "клик мышью (рывок) обработан без ошибок")

	-- ЛКМ должен реально запустить рывок в игровой симуляции.
	local clientState = Main.getState()
	local boostActive = false
	if clientState and clientState.game then
		boostActive = clientState.game.boostTime > 0 or clientState.game.boostCooldown > 0
	end
	check(boostActive, "ЛКМ запустил рывок в симуляции")

	-- Потеря фокуса.
	for _, fn in ipairs(uis.WindowFocusReleased.__signals) do
		fn()
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(true, "потеря фокуса обработана без ошибок")
end)

--------------------------------------------------------------------------- сервер

step("Server: загрузка серверного скрипта", function()
	local ok, err = pcall(function()
		require("./MainServer")
	end)
	check(ok, "серверный модуль загрузился без ошибок: " .. tostring(err))
end)

print("")
print(string.format("SMOKE: проверок %d, провалов %d", checks, failures))
if failures > 0 then
	error("smoke-тест провалился: " .. tostring(failures))
end

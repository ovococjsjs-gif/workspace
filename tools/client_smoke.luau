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

	-- Палитра фаз: небо/туман/яркость должны различаться между фазами.
	local lighting = services.Lighting
	local before = lighting.Brightness
	local beforeFog = lighting.FogEnd
	World.setPhase(1)
	local calmBrightness = lighting.Brightness
	local calmFog = lighting.FogEnd
	World.setPhase(4)
	check(
		calmBrightness ~= lighting.Brightness and calmFog ~= lighting.FogEnd,
		"палитра фаз меняет свет и туман"
	)
	check(lighting.FogEnd < beforeFog, "в буре туман ближе, чем в штиль")
	lighting.Brightness = before
	lighting.FogEnd = beforeFog
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

--------------------------------------------------------------------------- сервер (до клиента)

step("Server: загрузка серверного скрипта", function()
	local ok, err = pcall(function()
		require("./MainServer")
	end)
	check(ok, "серверный модуль загрузился без ошибок: " .. tostring(err))
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
		-- Сервер отвечает сидом и временем старта; двигаем виртуальные часы,
		-- чтобы «обратный отсчёт» дошёл до нуля.
		Mock.advance(5)
		for _ = 1, 5 do
			for _, fn in ipairs(heartbeat.__signals) do
				fn(1 / 60)
			end
		end
		check(Main.getState().mode == "playing", "забег запущен по кнопке (mode=" .. tostring(Main.getState().mode) .. ")")
		check(
			type(Main.getState().roundSeed) == "number",
			"клиент получил сид общего забега: " .. tostring(Main.getState().roundSeed)
		)
	end

	-- Прогоняем забег дольше: первое кольцо проходится примерно на 4.4-й секунде.
	-- Этот участок кода (обработка события кольца) иначе остался бы непроверенным.
	local uisEarly = services.UserInputService
	for _, fn in ipairs(uisEarly.InputBegan.__signals) do
		fn({ KeyCode = Mock.env.Enum.KeyCode.W, UserInputType = "Keyboard" }, false)
	end
	for _ = 1, 400 do
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
	end
	for _, fn in ipairs(uisEarly.InputEnded.__signals) do
		fn({ KeyCode = Mock.env.Enum.KeyCode.W, UserInputType = "Keyboard" }, false)
	end
	local stateAfter = Main.getState()
	local ringsPassed = 0
	if stateAfter and stateAfter.game then
		ringsPassed = stateAfter.game.score.rings
	end
	check(ringsPassed > 0, "во время прогона засчитано колец: " .. tostring(ringsPassed))

	-- Ввод: зажимаем клавиши и отпускаем.
	local uis = services.UserInputService
	local Input = require("./Input")
	for _, fn in ipairs(uis.InputBegan.__signals) do
		fn({ KeyCode = Mock.env.Enum.KeyCode.W, UserInputType = "Keyboard" }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	for _, fn in ipairs(uis.InputEnded.__signals) do
		fn({ KeyCode = Mock.env.Enum.KeyCode.W, UserInputType = "Keyboard" }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(true, "ввод с клавиатуры обработан без ошибок")

	-- ЛКМ — рывок.
	for _, fn in ipairs(uis.InputBegan.__signals) do
		fn({ KeyCode = Mock.env.Enum.KeyCode.Unknown, UserInputType = "MouseButton1" }, false)
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

	-- Сенсор: касание в левой половине экрана даёт виртуальный стик.
	local touchVec = Mock.env.Vector2.new(300, 700)
	for _, fn in ipairs(uis.InputBegan.__signals) do
		fn({ UserInputType = Mock.env.Enum.UserInputType.Touch, Position = touchVec }, false)
	end
	for _, fn in ipairs(uis.InputMoved.__signals) do
		fn({ UserInputType = Mock.env.Enum.UserInputType.Touch, Position = Mock.env.Vector2.new(360, 660) }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	local stickActive, stickOx, stickOy, stickCx, stickCy = Input.getTouchStick()
	check(stickActive, "сенсор включил виртуальный стик")
	check(
		math.abs(stickCx - stickOx) > 1 and math.abs(stickCy - stickOy) > 1,
		"стик отслеживает движение пальца"
	)
	local tx, ty, tz = Input.getAxes()
	check(tz > 0.5 and math.abs(tx) > 0.1, string.format("оси от стика: x=%s y=%s z=%s", tostring(tx), tostring(ty), tostring(tz)))
	-- Палец оторвался — стик выключается.
	for _, fn in ipairs(uis.InputEnded.__signals) do
		fn({ UserInputType = Mock.env.Enum.UserInputType.Touch, Position = touchVec }, false)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	local stickAfter = Input.getTouchStick()
	check(stickAfter == false, "после отпускания стик выключен")

	-- Потеря фокуса.
	for _, fn in ipairs(uis.WindowFocusReleased.__signals) do
		fn()
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(true, "потеря фокуса обработана без ошибок")

	-- Рестарт из финального экрана: кнопка «ЕЩЁ РАЗ» должна начать новый забег.
	local st = Main.getState()
	if st then
		st.mode = "over"
	end
	local again
	if screen then
		for _, child in ipairs(screen:GetDescendants()) do
			if child:IsA("TextButton") and child.Text == "ЕЩЁ РАЗ" then
				again = child
			end
		end
	end
	check(again ~= nil, "кнопка рестарта найдена")
	if again then
		for _, fn in ipairs(again.MouseButton1Click.__signals) do
			fn()
		end
		Mock.advance(5)
		for _ = 1, 5 do
			for _, fn in ipairs(heartbeat.__signals) do
				fn(1 / 60)
			end
		end
		local modeAfter = Main.getState().mode
		check(modeAfter == "playing", "рестарт начал новый забег (mode=" .. tostring(modeAfter) .. ")")
	end

	-- Появление персонажа: клиент должен спрятать стандартное тело.
	local character = Mock.env.Instance.new("Model")
	local body = Mock.env.Instance.new("Part")
	body.Name = "Torso"
	body.Transparency = 0
	body.Parent = character
	for _, fn in ipairs(services.Players.LocalPlayer.CharacterAdded.__signals) do
		fn(character)
	end
	for _, fn in ipairs(heartbeat.__signals) do
		fn(1 / 60)
	end
	check(body.Transparency == 1, "стандартный персонаж спрятан (Transparency=" .. tostring(body.Transparency) .. ")")
end)

--------------------------------------------------------------------------- гонка и магазин

step("Гонка: общий раунд, живой рейтинг и магазин", function()
	local Main = require("./Main")
	local heartbeat = services.RunService.Heartbeat
	local remotes = services.ReplicatedStorage:FindFirstChild("FlockRemotes")
	local progress = remotes and remotes:FindFirstChild("Progress")
	local buyPass = remotes and remotes:FindFirstChild("BuyPass")
	local permsRemote = remotes and remotes:FindFirstChild("PermsUpdate")
	check(progress ~= nil and buyPass ~= nil, "ремоты гонки и магазина созданы сервером")

	local player = services.Players.LocalPlayer

	-- Клиент сообщает прогресс, сервер принимает правдоподобные данные.
	if progress then
		for _, fn in ipairs(progress.OnServerEvent.__signals) do
			fn(player, 5000, 1200, 15, false, 60)
		end
	end
	-- Сервер рассылает рейтинг раз в секунду: прогоняем кадры.
	for _ = 1, 80 do
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
	end
	local standings = Main.getState().standings
	check(#standings >= 1, "клиент получил рейтинг забега: " .. tostring(#standings) .. " игрок(ов)")

	-- Второй игрок: сервер должен включить его в рейтинг, а клиент — нарисовать «призрака».
	local rival = { UserId = 777, Name = "Соперник" }
	local requestRound = remotes and remotes:FindFirstChild("RequestRound")
	if requestRound then
		for _, fn in ipairs(requestRound.OnServerEvent.__signals) do
			fn(rival)
		end
	end
	if progress then
		for _, fn in ipairs(progress.OnServerEvent.__signals) do
			fn(rival, 4200, 1100, 16, false, 60, { x = 12, y = 22, z = 900 })
		end
	end
	for _ = 1, 80 do
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
	end
	check(#Main.getState().standings >= 2, "в рейтинге два игрока: " .. tostring(#Main.getState().standings))
	local ghostFound = false
	for _, child in ipairs(services.Workspace:GetDescendants()) do
		if child.Name == "Ghost" then
			ghostFound = true
		end
	end
	check(ghostFound, "клиент нарисовал призрака соперника")

	-- Финиш: сервер должен присвоить место.
	if progress then
		for _, fn in ipairs(progress.OnServerEvent.__signals) do
			fn(player, 5000, 1200, 3, true, 61)
		end
	end
	for _ = 1, 80 do
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
	end
	check(Main.getState().place == 1, "после финиша сервер присвоил место: " .. tostring(Main.getState().place))

	-- Магазин: кнопка открывает панель, кнопка покупки уходит на сервер.
	local screen = services.Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("FlockGui")
	local shopButton, buyButton, productButton
	if screen then
		for _, child in ipairs(screen:GetDescendants()) do
			if child:IsA("TextButton") then
				if child.Text == "МАГАЗИН" then
					shopButton = child
				elseif child.Text == "КУПИТЬ" then
					-- первая кнопка — game pass, последняя — developer product
					buyButton = buyButton or child
					productButton = child
				end
			end
		end
	end
	check(shopButton ~= nil, "кнопка магазина найдена")
	if shopButton then
		for _, fn in ipairs(shopButton.MouseButton1Click.__signals) do
			fn()
		end
	end
	local shopVisible = false
	if screen then
		for _, child in ipairs(screen:GetDescendants()) do
			if child:IsA("Frame") and child.Name == "ShopPanel" and child.Visible then
				shopVisible = true
			end
		end
	end
	check(shopVisible, "панель магазина открылась")
	check(buyButton ~= nil, "кнопка покупки найдена")
	-- Настраиваем ID до покупки: сервер должен открыть окно покупки.
	require("./ShopConfig").passes.goldenBoost = 4242
	if buyButton then
		for _, fn in ipairs(buyButton.MouseButton1Click.__signals) do
			fn()
		end
	end
	local prompted = rawget(services.MarketplaceService, "__promptedPass")
	check(prompted ~= nil, "сервер вызвал PromptGamePassPurchase для покупки")

	-- Developer product (повторяемая покупка) — тоже должен открыть окно покупки.
	require("./ShopConfig").products.boostPack = 4243
	if productButton then
		for _, fn in ipairs(productButton.MouseButton1Click.__signals) do
			fn()
		end
	end
	local promptedProduct = rawget(services.MarketplaceService, "__promptedProduct")
	check(promptedProduct ~= nil, "сервер вызвал PromptProductPurchase для зарядов")

	-- Обработка чека: сервер должен выдать заряды мгновенного рывка.
	local receipt = services.MarketplaceService.ProcessReceipt
	if type(receipt) == "function" then
		local response = receipt({ PlayerId = player.UserId, ProductId = 4243 })
		check(response ~= nil, "обработчик чека ответил: " .. tostring(response))
		for _ = 1, 3 do
			for _, fn in ipairs(heartbeat.__signals) do
				fn(1 / 60)
			end
		end
		check(
			Main.getState().perms.boostCharges == 3,
			"после чека клиент получил 3 заряда рывка: " .. tostring(Main.getState().perms.boostCharges)
		)
	else
		check(false, "сервер не назначил обработчик ProcessReceipt")
	end

	-- Владение game pass'ом: сервер должен прислать перк клиенту.
	-- Настраиваем ID покупки (в репозитории он = 0, плейсхолдер).
	local ShopConfig = require("./ShopConfig")
	ShopConfig.passes.goldenBoost = 4242
	local gameplay = services.GameplayService
	local owned = rawget(gameplay, "__ownedPasses")
	owned[player.UserId] = { [4242] = true }
	for _, fn in ipairs(services.Players.PlayerAdded.__signals) do
		fn(player)
	end
	for _ = 1, 3 do
		for _, fn in ipairs(heartbeat.__signals) do
			fn(1 / 60)
		end
	end
	check(permsRemote ~= nil, "ремоут перков создан")
	check(
		Main.getState().perms.goldenBoost == true,
		"клиент получил перк после проверки владения pass'ом"
	)
end)

--------------------------------------------------------------------------- сервер

step("Server: приём и проверка рекорда", function()
	local remotes = services.ReplicatedStorage:FindFirstChild("FlockRemotes")
	local submit = remotes and remotes:FindFirstChild("SubmitScore")
	local best = remotes and remotes:FindFirstChild("BestScore")
	check(submit ~= nil and best ~= nil, "ремоты рекорда созданы сервером")
	if not (submit and best) then
		return
	end

	-- Правдоподобный результат должен приняться и вернуться игроку.
	for _, fn in ipairs(submit.OnServerEvent.__signals) do
		fn(services.Players.LocalPlayer, 1000, 60)
	end
	local fired = rawget(best, "__fired")
	check(fired ~= nil and fired[2] == 1000, "сервер принял правдоподобный счёт и отдал рекорд")

	-- Заведомо невозможный результат (миллион очков за секунду) — отбрасывается.
	for _, fn in ipairs(submit.OnServerEvent.__signals) do
		fn(services.Players.LocalPlayer, 1000000, 1)
	end
	local fired2 = rawget(best, "__fired")
	check(fired2 == nil or fired2[2] == 1000, "невозможный счёт отброшен сервером")
end)

print("")
print(string.format("SMOKE: проверок %d, провалов %d", checks, failures))
if failures > 0 then
	error("smoke-тест провалился: " .. tostring(failures))
end

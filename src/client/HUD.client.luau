--[=[
	HUD: счёт, комбо, состояние стаи, окно кольца, тосты, экраны старта/финала.
	Всё строится кодом (никаких Gui-объектов в репозитории).
]=]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Config = require(Shared.Config)

local HUD = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local scoreLabel: TextLabel? = nil
local bestLabel: TextLabel? = nil
local comboLabel: TextLabel? = nil
local comboStroke: UIStroke? = nil
local flockLabel: TextLabel? = nil
local flockBar: Frame? = nil
local flockBarFill: Frame? = nil
local calmLabel: TextLabel? = nil
local calmBar: Frame? = nil
local calmBarFill: Frame? = nil
local boostLabel: TextLabel? = nil
local boostBar: Frame? = nil
local boostBarFill: Frame? = nil
local phaseLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local toastLabel: TextLabel? = nil
local timerBar: Frame? = nil
local timerFill: Frame? = nil
local timerLabel: TextLabel? = nil
local flash: Frame? = nil
local vignette: Frame? = nil
local startScreen: Frame? = nil
local endScreen: Frame? = nil
local endTitle: TextLabel? = nil
local endScore: TextLabel? = nil
local endBest: TextLabel? = nil
local endStats: TextLabel? = nil
local reticle: Frame? = nil
local strayArrow: TextLabel? = nil
local timeLabel: TextLabel? = nil
local phaseBar: Frame? = nil
local phaseBarFill: Frame? = nil
local shakeOffset = Vector3.zero

HUD.COLOR_TEXT = Color3.fromRGB(255, 255, 255)
HUD.COLOR_ACCENT = Color3.fromRGB(255, 196, 84)
HUD.COLOR_GOOD = Color3.fromRGB(120, 240, 190)
HUD.COLOR_BAD = Color3.fromRGB(255, 110, 96)

local COLOR_TEXT = HUD.COLOR_TEXT
local COLOR_ACCENT = HUD.COLOR_ACCENT
local COLOR_GOOD = HUD.COLOR_GOOD
local COLOR_BAD = HUD.COLOR_BAD

local function new(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	return inst
end

local function textLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLOR_TEXT,
		TextSize = 20,
		Text = "",
		Size = UDim2.fromOffset(400, 30),
		Position = UDim2.fromOffset(0, 0),
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function roundCorners(inst: Instance, radius: number)
	local corner = new("UICorner", { CornerRadius = UDim.new(0, radius) })
	corner.Parent = inst
end

function HUD.build()
	if gui then
		return
	end

	gui = new("ScreenGui", {
		Name = "FlockGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 10,
	})
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Вспышка по всему экрану (чистое кольцо / провал).
	flash = new("Frame", {
		BackgroundColor3 = COLOR_TEXT,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})
	flash.Parent = gui

	-- Виньетка снизу — «опасность» (стая рассыпается).
	vignette = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(190, 40, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	})
	vignette.Parent = gui

	-- Счёт (слева сверху).
	scoreLabel = textLabel(gui, {
		Position = UDim2.fromOffset(28, 18),
		Size = UDim2.fromOffset(320, 54),
		TextSize = 42,
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local scoreStroke = new("UIStroke", { Thickness = 5, Color = Color3.fromRGB(20, 24, 30), Transparency = 0.25 })
	scoreStroke.Parent = scoreLabel

	bestLabel = textLabel(gui, {
		Position = UDim2.fromOffset(30, 74),
		Size = UDim2.fromOffset(320, 24),
		TextSize = 16,
		Text = "РЕКОРД 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR_ACCENT,
	})

	-- Комбо (по центру сверху).
	comboLabel = textLabel(gui, {
		Position = UDim2.new(0.5, -120, 0, 20),
		Size = UDim2.fromOffset(240, 70),
		TextSize = 54,
		Text = "x1",
		TextTransparency = 1,
	})
	comboStroke = new("UIStroke", { Thickness = 4, Color = COLOR_ACCENT, Transparency = 0.2 })
	comboStroke.Parent = comboLabel

	-- Стая (справа сверху).
	flockLabel = textLabel(gui, {
		Position = UDim2.new(1, -268, 0, 20),
		Size = UDim2.fromOffset(240, 30),
		TextSize = 20,
		Text = "СТАЯ 18/18",
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	flockBar = new("Frame", {
		Position = UDim2.new(1, -268, 0, 54),
		Size = UDim2.fromOffset(240, 12),
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	})
	flockBar.Parent = gui
	roundCorners(flockBar, 6)
	flockBarFill = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_GOOD,
		BorderSizePixel = 0,
	})
	flockBarFill.Parent = flockBar
	roundCorners(flockBarFill, 6)

	-- Спокойствие стаи (под полосой стаи): главный «навыковый» индикатор.
	calmLabel = textLabel(gui, {
		Position = UDim2.new(1, -268, 0, 72),
		Size = UDim2.fromOffset(240, 20),
		TextSize = 13,
		Text = "СПОКОЙСТВИЕ",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COLOR_GOOD,
	})
	calmBar = new("Frame", {
		Position = UDim2.new(1, -268, 0, 94),
		Size = UDim2.fromOffset(240, 8),
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	})
	calmBar.Parent = gui
	roundCorners(calmBar, 4)
	calmBarFill = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_GOOD,
		BorderSizePixel = 0,
	})
	calmBarFill.Parent = calmBar
	roundCorners(calmBarFill, 4)

	-- Рывок: перезарядка (под шкалой спокойствия).
	boostLabel = textLabel(gui, {
		Position = UDim2.new(1, -268, 0, 108),
		Size = UDim2.fromOffset(240, 18),
		TextSize = 13,
		Text = "РЫВОК (ЛКМ)",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COLOR_ACCENT,
	})
	boostBar = new("Frame", {
		Position = UDim2.new(1, -268, 0, 128),
		Size = UDim2.fromOffset(240, 8),
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	})
	boostBar.Parent = gui
	roundCorners(boostBar, 4)
	boostBarFill = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_ACCENT,
		BorderSizePixel = 0,
	})
	boostBarFill.Parent = boostBar
	roundCorners(boostBarFill, 4)

	-- Фаза + подсказка (снизу).
	phaseLabel = textLabel(gui, {
		Position = UDim2.new(0, 0, 1, -118),
		Size = UDim2.fromScale(1, 34),
		TextSize = 22,
		Text = "ФАЗА 1 — ШТИЛЬ",
		TextColor3 = COLOR_ACCENT,
	})
	hintLabel = textLabel(gui, {
		Position = UDim2.new(0, 0, 1, -88),
		Size = UDim2.fromScale(1, 28),
		TextSize = 16,
		Text = "WASD — курс, Space/Shift — высота",
		TextTransparency = 0.25,
	})

	-- Окно кольца (по центру снизу).
	timerBar = new("Frame", {
		Position = UDim2.new(0.5, -150, 1, -60),
		Size = UDim2.fromOffset(300, 14),
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
	})
	timerBar.Parent = gui
	roundCorners(timerBar, 7)
	timerFill = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR_ACCENT,
		BorderSizePixel = 0,
	})
	timerFill.Parent = timerBar
	roundCorners(timerFill, 7)
	timerLabel = textLabel(gui, {
		Position = UDim2.new(0.5, -160, 1, -84),
		Size = UDim2.fromOffset(320, 24),
		TextSize = 15,
		Text = "КОЛЬЦО ЗАКРОЕТСЯ",
		TextColor3 = COLOR_ACCENT,
		Visible = false,
	})

	-- Тост (всплывающий текст события).
	toastLabel = textLabel(gui, {
		Position = UDim2.new(0.5, -250, 0.5, -90),
		Size = UDim2.fromOffset(500, 60),
		TextSize = 38,
		Text = "",
		TextTransparency = 1,
	})

	-- Прицел.
	reticle = new("Frame", {
		Position = UDim2.new(0.5, -16, 0.5, -16),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = COLOR_TEXT,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	reticle.Parent = gui
	roundCorners(reticle, 16)

	-- Таймер забега (по центру сверху, под комбо).
	timeLabel = textLabel(gui, {
		Position = UDim2.new(0.5, -100, 0, 92),
		Size = UDim2.fromOffset(200, 26),
		TextSize = 18,
		Text = "0:00",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 0.35,
	})

	-- Полоска прогресса фаз (под таймером).
	phaseBar = new("Frame", {
		Position = UDim2.new(0.5, -150, 0, 120),
		Size = UDim2.fromOffset(300, 6),
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	})
	phaseBar.Parent = gui
	roundCorners(phaseBar, 3)
	phaseBarFill = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLOR_ACCENT,
		BorderSizePixel = 0,
	})
	phaseBarFill.Parent = phaseBar
	roundCorners(phaseBarFill, 3)

	-- Стрелка к ближайшей потерянной птице: показывает, куда её искать.
	strayArrow = textLabel(gui, {
		Position = UDim2.new(0.5, -20, 0.5, -180),
		Size = UDim2.fromOffset(40, 40),
		TextSize = 34,
		Text = "▼",
		TextColor3 = COLOR_BAD,
		Visible = false,
	})
	strayArrow.Parent = gui

	-- Экран старта.
	startScreen = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 16, 24),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
	})
	startScreen.Parent = gui
	local startTitle = textLabel(startScreen, {
		Position = UDim2.new(0.5, -400, 0.5, -170),
		Size = UDim2.fromOffset(800, 110),
		TextSize = 92,
		Text = "СТАЯ",
		TextColor3 = COLOR_ACCENT,
	})
	local startStroke = new("UIStroke", { Thickness = 6, Color = Color3.fromRGB(20, 24, 30), Transparency = 0.2 })
	startStroke.Parent = startTitle
	local startSub = textLabel(startScreen, {
		Position = UDim2.new(0.5, -430, 0.5, -95),
		Size = UDim2.fromOffset(860, 190),
		TextSize = 21,
		Text = "Ты — вожак стаи из 18 птиц. Проведи их через кольца-ворота.\n"
			.. "Кольцо засчитывается, только если прошла ВСЯ стая.\n"
			.. "Веди спокойно: резкое управление пугает стаю — и она разваливается.\n"
			.. "Потерянных птиц догони и верни в строй (маячок + магнит).\n\n"
			.. "WASD — курс    Space / Shift — высота    ЛКМ — рывок",
		TextTransparency = 0.1,
	})
	local startButton = new("TextButton", {
		BackgroundColor3 = COLOR_ACCENT,
		BorderSizePixel = 0,
		Text = "ПОЛЕТЕЛИ",
		TextSize = 30,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(24, 26, 30),
		Position = UDim2.new(0.5, -130, 0.5, 110),
		Size = UDim2.fromOffset(260, 68),
		AutoButtonColor = true,
		ZIndex = 11,
	})
	startButton.Parent = startScreen
	roundCorners(startButton, 18)
	HUD.startButton = startButton

	-- Финальный экран.
	endScreen = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 16, 24),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
	})
	endScreen.Parent = gui
	endTitle = textLabel(endScreen, {
		Position = UDim2.new(0.5, -400, 0.5, -160),
		Size = UDim2.fromOffset(800, 90),
		TextSize = 60,
		Text = "СТАЯ РАССЫПАЛАСЬ",
		TextColor3 = COLOR_BAD,
	})
	endScore = textLabel(endScreen, {
		Position = UDim2.new(0.5, -400, 0.5, -60),
		Size = UDim2.fromOffset(800, 60),
		TextSize = 40,
		Text = "СЧЁТ 0",
		TextColor3 = COLOR_TEXT,
	})
	endBest = textLabel(endScreen, {
		Position = UDim2.new(0.5, -400, 0.5, -10),
		Size = UDim2.fromOffset(800, 40),
		TextSize = 22,
		Text = "РЕКОРД 0",
		TextColor3 = COLOR_ACCENT,
	})
	endStats = textLabel(endScreen, {
		Position = UDim2.new(0.5, -400, 0.5, 30),
		Size = UDim2.fromOffset(800, 32),
		TextSize = 18,
		Text = "",
		TextColor3 = COLOR_TEXT,
		TextTransparency = 0.25,
	})
	local againButton = new("TextButton", {
		BackgroundColor3 = COLOR_ACCENT,
		BorderSizePixel = 0,
		Text = "ЕЩЁ РАЗ",
		TextSize = 28,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(24, 26, 30),
		Position = UDim2.new(0.5, -130, 0.5, 70),
		Size = UDim2.fromOffset(260, 64),
		ZIndex = 11,
	})
	againButton.Parent = endScreen
	roundCorners(againButton, 18)
	HUD.againButton = againButton
end

--- Всплывающее сообщение по центру экрана.
function HUD.toast(text: string, color: Color3)
	if not toastLabel then
		return
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = color
	toastLabel.TextTransparency = 0
	toastLabel.Position = UDim2.new(0.5, -250, 0.5, -60)
	TweenService:Create(toastLabel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
	task.delay(0.9, function()
		if toastLabel then
			TweenService:Create(toastLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				Position = UDim2.new(0.5, -250, 0.5, -110),
			}):Play()
		end
	end)
end

--- Короткая вспышка экрана.
function HUD.flashScreen(color: Color3, strength: number)
	if not flash then
		return
	end
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

--- Тряска камеры (значение в секундах, затухает сама).
function HUD.shake(amount: number)
	shakeOffset = Vector3.new(
		(math.random() - 0.5) * amount,
		(math.random() - 0.5) * amount,
		(math.random() - 0.5) * amount
	)
end

function HUD.updateShake(dt: number)
	if shakeOffset.Magnitude > 0.01 then
		shakeOffset = shakeOffset * math.max(0, 1 - dt * 6)
	else
		shakeOffset = Vector3.zero
	end
end

function HUD.getShakeOffset(): Vector3
	return shakeOffset
end

function HUD.setScore(value: number)
	if scoreLabel then
		scoreLabel.Text = tostring(value)
	end
end

function HUD.setBest(value: number)
	if bestLabel then
		bestLabel.Text = "РЕКОРД " .. tostring(value)
	end
end

function HUD.setCombo(combo: number)
	if not comboLabel then
		return
	end
	if combo <= 1 then
		comboLabel.TextTransparency = 1
		return
	end
	comboLabel.Text = "x" .. tostring(combo)
	comboLabel.TextTransparency = 0
	comboLabel.TextColor3 = COLOR_ACCENT
	comboLabel.Size = UDim2.fromOffset(240, 70) * 1.0
	TweenService:Create(comboLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(280, 82),
	}):Play()
	task.delay(0.25, function()
		if comboLabel then
			TweenService:Create(comboLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(240, 70),
			}):Play()
		end
	end)
end

function HUD.setFlock(alive: number, total: number)
	if flockLabel then
		flockLabel.Text = string.format("СТАЯ %d/%d", alive, total)
	end
	if flockBarFill then
		local ratio = if total > 0 then alive / total else 0
		TweenService:Create(flockBarFill, TweenInfo.new(0.2), {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = if ratio > 0.6 then COLOR_GOOD elseif ratio > 0.3 then COLOR_ACCENT else COLOR_BAD,
		}):Play()
	end
end

--- Спокойствие стаи: 1 — стая спокойна, 0 — паника.
function HUD.setCalm(calm: number)
	local value = math.clamp(calm, 0, 1)
	if calmBarFill then
		TweenService:Create(calmBarFill, TweenInfo.new(0.15), {
			Size = UDim2.fromScale(value, 1),
			BackgroundColor3 = if value > 0.65 then COLOR_GOOD elseif value > 0.4 then COLOR_ACCENT else COLOR_BAD,
		}):Play()
	end
	if calmLabel then
		if value > 0.65 then
			calmLabel.Text = "СПОКОЙСТВИЕ"
			calmLabel.TextColor3 = COLOR_GOOD
		elseif value > 0.4 then
			calmLabel.Text = "СТАЯ ВОЛНУЕТСЯ"
			calmLabel.TextColor3 = COLOR_ACCENT
		else
			calmLabel.Text = "ПАНИКА СТАИ!"
			calmLabel.TextColor3 = COLOR_BAD
		end
	end
end

--- Рывок: cooldown — остаток перезарядки, total — полная перезарядка.
function HUD.setBoost(cooldown: number, total: number, active: boolean)
	if boostBarFill then
		local ratio = if total > 0 then math.clamp(1 - cooldown / total, 0, 1) else 1
		TweenService:Create(boostBarFill, TweenInfo.new(0.1), {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = if active then COLOR_GOOD else COLOR_ACCENT,
		}):Play()
	end
	if boostLabel then
		if active then
			boostLabel.Text = "РЫВОК!"
			boostLabel.TextColor3 = COLOR_GOOD
		elseif cooldown > 0.05 then
			boostLabel.Text = string.format("РЫВОК (ЛКМ) %.1f", cooldown)
			boostLabel.TextColor3 = COLOR_ACCENT
		else
			boostLabel.Text = "РЫВОК (ЛКМ) ГОТОВ"
			boostLabel.TextColor3 = COLOR_GOOD
		end
	end
end

--- Стрелка к потерянной птице: angle — направление на экране (рад.),
--- distance — расстояние (для цвета/размера). nil — прячем стрелку.
function HUD.setStrayDirection(angle: number?, distance: number?)
	if not strayArrow then
		return
	end
	if not angle or not distance then
		strayArrow.Visible = false
		return
	end
	strayArrow.Visible = true
	local radius = 150
	local x = math.cos(angle) * radius
	local y = -math.sin(angle) * radius
	strayArrow.Position = UDim2.new(0.5, x - 20, 0.5, y - 20)
	strayArrow.Rotation = math.deg(angle) + 90
	local far = math.clamp(distance / 400, 0, 1)
	strayArrow.TextTransparency = 0.15 + far * 0.5
	strayArrow.TextSize = 34 - far * 10
end

function HUD.setPhase(name: string, index: number)
	if phaseLabel then
		phaseLabel.Text = string.format("ФАЗА %d — %s", index, name)
	end
end

--- Таймер забега (секунды).
function HUD.setTime(seconds: number)
	if timeLabel then
		local total = math.floor(math.max(seconds, 0))
		timeLabel.Text = string.format("%d:%02d", math.floor(total / 60), total % 60)
	end
end

--- Прогресс по фазам: ratio 0..1 — какая доля «сложности» пройдена.
function HUD.setPhaseProgress(ratio: number)
	if phaseBarFill then
		TweenService:Create(phaseBarFill, TweenInfo.new(0.3), {
			Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
		}):Play()
	end
end

function HUD.setHint(text: string)
	if hintLabel then
		hintLabel.Text = text
	end
end

--- Окно кольца: remaining — сколько секунд осталось (nil = кольца нет).
function HUD.setRingTimer(remaining: number?, total: number?)
	if not timerBar or not timerFill or not timerLabel then
		return
	end
	if not remaining or not total or total <= 0 then
		timerBar.Visible = false
		timerLabel.Visible = false
		return
	end
	timerBar.Visible = true
	timerLabel.Visible = true
	local ratio = math.clamp(remaining / total, 0, 1)
	timerFill.Size = UDim2.fromScale(ratio, 1)
	timerFill.BackgroundColor3 = if ratio < 0.35 then COLOR_BAD else COLOR_ACCENT
	timerLabel.Text = string.format("КОЛЬЦО ЗАКРОЕТСЯ ЧЕРЕЗ %.1f", math.max(remaining, 0))
end

function HUD.setDanger(level: number)
	if not vignette then
		return
	end
	vignette.BackgroundTransparency = 1 - math.clamp(level, 0, 1) * 0.55
end

function HUD.showStart(show: boolean)
	if startScreen then
		startScreen.Visible = show
	end
end

function HUD.showEnd(show: boolean, score: number, best: number, stats: string?)
	if not endScreen then
		return
	end
	endScreen.Visible = show
	if show then
		if endTitle then
			endTitle.Text = "СТАЯ РАССЫПАЛАСЬ"
		end
		if endScore then
			endScore.Text = "СЧЁТ " .. tostring(score)
		end
		if endBest then
			endBest.Text = "РЕКОРД " .. tostring(best)
		end
		if endStats then
			endStats.Text = stats or ""
		end
	end
end

return HUD

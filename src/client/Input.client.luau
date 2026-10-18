--[=[
	Ввод: клавиатура. Возвращает оси движения в системе координат КУРСА
	(x — вправо, y — вверх, z — вперёд по курсу).
	Схема: W/S — вперёд/назад, A/D — влево/вправо, Space — вверх, Shift/C — вниз.
]=]

local UserInputService = game:GetService("UserInputService")

local Input = {}

local keys = {
	up = false,
	down = false,
	left = false,
	right = false,
	raise = false,
	lower = false,
}

local function setKey(key: Enum.KeyCode, down: boolean)
	if key == Enum.KeyCode.W or key == Enum.KeyCode.Up then
		keys.up = down
	elseif key == Enum.KeyCode.S or key == Enum.KeyCode.Down then
		keys.down = down
	elseif key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
		keys.left = down
	elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
		keys.right = down
	elseif key == Enum.KeyCode.Space then
		keys.raise = down
	elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.C then
		keys.lower = down
	end
end

local boostRequested = false

-- Сенсорный ввод (мобильные): левая половина экрана — виртуальный стик,
-- правая — «рывок». Стик задаёт крен и высоту, вперёд стая летит всегда.
local TOUCH_RADIUS = 110 -- экранных пикселей до полного отклонения
local touchActive = false
local touchOriginX = 0
local touchOriginY = 0
local touchX = 0
local touchY = 0

Input.enabled = true

local function viewportWidth(): number
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize and cam.ViewportSize.X > 0 then
		return cam.ViewportSize.X
	end
	return 1920
end

--- Начало касания: левая половина — стик, правая — рывок.
local function beginTouch(position: Vector2)
	if position.X < viewportWidth() * 0.5 then
		if not touchActive then
			touchActive = true
			touchOriginX = position.X
			touchOriginY = position.Y
		end
		touchX = position.X
		touchY = position.Y
	else
		boostRequested = true
	end
end

--- Движение пальца: обновляем стик (только если он активен).
local function moveTouch(position: Vector2)
	if not touchActive then
		return
	end
	if math.abs(position.X - touchOriginX) < TOUCH_RADIUS * 1.6 then
		touchX = position.X
		touchY = position.Y
	end
end

--- Палец оторвался: если это был наш стик — сбрасываем.
local function endTouch(position: Vector2)
	if not touchActive then
		return
	end
	if math.abs(position.X - touchOriginX) < TOUCH_RADIUS * 1.6 then
		touchActive = false
	end
end

function Input.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		setKey(input.KeyCode, true)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		setKey(input.KeyCode, false)
		if input.UserInputType == Enum.UserInputType.Touch and input.Position then
			endTouch(input.Position)
		end
	end)
	-- Сенсор: начало и движение пальца.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and input.Position then
			beginTouch(input.Position)
		end
	end)
	UserInputService.InputMoved:Connect(function(input: InputObject, _gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and input.Position then
			moveTouch(input.Position)
		end
	end)
	-- ЛКМ — «рывок» (edge-triggered: одно нажатие = один рывок).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			boostRequested = true
		end
	end)

	-- На случай потери фокуса не залипаем нажатыми клавишами.
	UserInputService.WindowFocusReleased:Connect(function()
		touchActive = false
		keys.up = false
		keys.down = false
		keys.left = false
		keys.right = false
		keys.raise = false
		keys.lower = false
	end)
end

--- Оси движения (нормированные по диагонали, чтобы движение не было быстрее по диагонали).
function Input.getAxes(): (number, number, number)
	if not Input.enabled then
		return 0, 0, 0
	end
	local x = 0
	local y = 0
	local z = 0
	if keys.left then
		x -= 1
	end
	if keys.right then
		x += 1
	end
	if keys.up then
		z += 1
	end
	if keys.down then
		z -= 1
	end
	if keys.raise then
		y += 1
	end
	if keys.lower then
		y -= 1
	end
	-- Сенсорный стик (если палец на экране) — он главный источник команд.
	if touchActive then
		local dx = (touchX - touchOriginX) / TOUCH_RADIUS
		local dy = (touchOriginY - touchY) / TOUCH_RADIUS
		local mag = math.sqrt(dx * dx + dy * dy)
		if mag > 1 then
			dx /= mag
			dy /= mag
		end
		x = dx
		y = dy
		z = 1
	end

	local mag = math.sqrt(x * x + y * y + z * z)
	if mag > 1 then
		x /= mag
		y /= mag
		z /= mag
	end
	return x, y, z
end

--- Состояние виртуального стика для отрисовки в HUD.
--- Возвращает: активен ли, начало стика (x, y) и текущая позиция пальца (x, y).
function Input.getTouchStick(): (boolean, number, number, number, number)
	return touchActive, touchOriginX, touchOriginY, touchX, touchY
end

--- Забирает запрос на «рывок» (одно нажатие ЛКМ = один рывок).
function Input.consumeBoost(): boolean
	if not boostRequested then
		return false
	end
	boostRequested = false
	return true
end

--- Любая из клавиш "вперёд" нажата (для автопилота/подсказки).
return Input

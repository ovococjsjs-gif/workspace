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

Input.enabled = true

function Input.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		setKey(input.KeyCode, true)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		setKey(input.KeyCode, false)
	end)
	-- На случай потери фокуса не залипаем нажатыми клавишами.
	UserInputService.WindowFocusReleased:Connect(function()
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
	local mag = math.sqrt(x * x + y * y + z * z)
	if mag > 1 then
		x /= mag
		y /= mag
		z /= mag
	end
	return x, y, z
end

--- Любая из клавиш "вперёд" нажата (для автопилота/подсказки).
function Input.isThrusting(): boolean
	return keys.up or keys.down or keys.left or keys.right or keys.raise or keys.lower
end

return Input

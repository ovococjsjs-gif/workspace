--!strict
--[=[
	Кривая сложности: фазы меняются со временем забега, параметры внутри фазы
	плавно интерполируются, чтобы переходы не были «ступеньками».
	Чистый Luau.
]=]

local Config = require(script.Parent.Config)

export type Phase = {
	index: number,
	name: string,
	--- Радиус колец (уменьшается со временем).
	ringRadius: number,
	--- Окно для стаи после пересечения лидером, сек.
	grace: number,
	--- Сила ветра.
	windStrength: number,
	--- Шанс появления препятствия-камня за кольцо, 0..1.
	obstacleChance: number,
	--- Дистанция между кольцами.
	gap: number,
	--- Цвет фазы (для HUD/окружения).
	hint: string,
}

export type PhaseDef = {
	at: number,
	name: string,
	ringRadius: number,
	grace: number,
	windStrength: number,
	obstacleChance: number,
	gap: number,
	hint: string,
}

local PHASES: { PhaseDef } = {
	{
		at = 0,
		name = "ШТИЛЬ",
		ringRadius = 46.0,
		grace = 3.0,
		windStrength = 1.0,
		obstacleChance = 0.0,
		gap = 92.0,
		hint = "Собери стаю и проведи её через кольцо",
	},
	{
		at = 45,
		name = "ВЕТЕР",
		ringRadius = 42.0,
		grace = 2.6,
		windStrength = 3.2,
		obstacleChance = 0.15,
		gap = 84.0,
		hint = "Ветер сносит птиц — держись против него",
	},
	{
		at = 95,
		name = "СКАЛЫ",
		ringRadius = 38.0,
		grace = 2.2,
		windStrength = 5.0,
		obstacleChance = 0.4,
		gap = 78.0,
		hint = "Кольца сужаются. Не теряй птиц",
	},
	{
		at = 150,
		name = "БУРЯ",
		ringRadius = 36.0,
		grace = 1.8,
		windStrength = 7.5,
		obstacleChance = 0.65,
		gap = 72.0,
		hint = "Буря! Собери всех, иначе кольцо закроется",
	},
}

local Difficulty = {}

--- Фаза по времени забега (с плавной интерполяцией внутри фазы).
function Difficulty.phaseAt(elapsed: number): Phase
	local n = #PHASES
	local index = 1
	for i = 1, n do
		if elapsed >= PHASES[i].at then
			index = i
		end
	end
	local current = PHASES[index]
	local nextPhase = PHASES[math.min(index + 1, n)]
	local span = nextPhase.at - current.at
	local t = if span <= 0 then 0 else math.clamp((elapsed - current.at) / span, 0, 1)

	local function mix(a: number, b: number): number
		return a + (b - a) * t
	end

	return {
		index = index,
		name = current.name,
		ringRadius = mix(current.ringRadius, nextPhase.ringRadius),
		grace = mix(current.grace, nextPhase.grace),
		windStrength = mix(current.windStrength, nextPhase.windStrength),
		obstacleChance = mix(current.obstacleChance, nextPhase.obstacleChance),
		gap = mix(current.gap, nextPhase.gap),
		hint = current.hint,
	}
end

--- Индекс фазы (1..4) — для смены оформления/музыки.
function Difficulty.phaseIndex(elapsed: number): number
	local index = 1
	for i = 1, #PHASES do
		if elapsed >= PHASES[i].at then
			index = i
		end
	end
	return index
end

--- Насколько кольцо должно быть маленьким (с учётом базовой настройки).
function Difficulty.ringRadius(elapsed: number): number
	local phase = Difficulty.phaseAt(elapsed)
	return math.min(Config.ring.radius, phase.ringRadius)
end

return Difficulty

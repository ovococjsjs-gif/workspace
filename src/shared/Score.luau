--!strict
--[=[
	Счёт, комбо и проверка правдоподобности результата (анти-чит).
	Чистый Luau: сервер использует ровно те же правила, что и клиент,
	поэтому их можно покрыть тестами.
]=]

local Config = require(script.Parent.Config)

export type ScoreState = {
	score: number,
	combo: number,
	bestCombo: number,
	perfects: number,
	partials: number,
	fails: number,
	recovered: number,
	rings: number,
	elapsed: number,
}

local Score = {}

function Score.new(): ScoreState
	return {
		score = 0,
		combo = 1,
		bestCombo = 1,
		perfects = 0,
		partials = 0,
		fails = 0,
		recovered = 0,
		rings = 0,
		elapsed = 0,
	}
end

--- Начисление за кольцо. Возвращает количество полученных очков.
function Score.awardRing(state: ScoreState, result: string, baseValue: number): number
	state.rings += 1
	if result == "perfect" then
		state.perfects += 1
		local mult = state.combo
		local points = math.floor(baseValue * mult * Config.score.perfectMultiplier)
		state.score += points
		state.combo = math.min(Config.score.maxCombo, state.combo + 1)
		state.bestCombo = math.max(state.bestCombo, state.combo)
		return points
	elseif result == "partial" then
		state.partials += 1
		local points = math.floor(baseValue * Config.score.partialFraction)
		state.score += points
		state.combo = 1
		return points
	else
		state.fails += 1
		state.combo = 1
		return 0
	end
end

--- Очки за подобранную потерянную птицу.
function Score.awardRecovery(state: ScoreState): number
	state.recovered += 1
	state.score += Config.score.recoverBonus
	return Config.score.recoverBonus
end

--- Бонус за идеально собранную стаю в момент пересечения кольца.
function Score.awardPerfectFlock(state: ScoreState): number
	local points = Config.score.perfectFlockBonus * state.combo
	state.score += points
	return points
end

--- Правдоподобен ли результат? Грубая защита от «клиент прислал миллион очков».
function Score.isPlausible(score: number, elapsed: number): boolean
	if score < 0 then
		return false
	end
	if score > Config.antiCheat.maxTotal then
		return false
	end
	local allowed = Config.antiCheat.maxPointsPerSecond * math.max(elapsed, 0) + Config.antiCheat.slack
	return score <= allowed
end

--- Итоговый счёт забега (с бонусом за длительность).
function Score.finalScore(state: ScoreState): number
	return state.score
end

return Score

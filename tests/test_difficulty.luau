--!strict
--[=[
	Тесты кривой сложности и счёта/комбо, а также проверки правдоподобности результата.
]=]

local T = require(script.Parent.Framework)
local Difficulty = require(script.Parent.Difficulty)
local Score = require(script.Parent.Score)
local Config = require(script.Parent.Config)

T.test("фазы меняются по времени", function()
	T.eq(Difficulty.phaseAt(0).name, "ШТИЛЬ")
	T.eq(Difficulty.phaseAt(50).name, "ВЕТЕР")
	T.eq(Difficulty.phaseAt(100).name, "СКАЛЫ")
	T.eq(Difficulty.phaseAt(200).name, "БУРЯ")
end)

T.test("кольца сужаются со временем", function()
	local early = Difficulty.ringRadius(0)
	local late = Difficulty.ringRadius(200)
	T.ok(late < early, string.format("радиус должен уменьшаться: %s -> %s", tostring(early), tostring(late)))
	T.ok(late >= 10, "радиус не должен стать непроходимым")
end)

T.test("сила ветра растёт", function()
	T.ok(Difficulty.phaseAt(200).windStrength > Difficulty.phaseAt(0).windStrength)
end)

T.test("чистое кольцо даёт очки с множителем и повышает комбо", function()
	local s = Score.new()
	local p1 = Score.awardRing(s, "perfect", 120)
	T.eq(p1, 120)
	T.eq(s.combo, 2)
	local p2 = Score.awardRing(s, "perfect", 120)
	T.eq(p2, 240)
	T.eq(s.score, 360)
	T.eq(s.combo, 3)
end)

T.test("комбо ограничен максимумом", function()
	local s = Score.new()
	for _ = 1, 20 do
		Score.awardRing(s, "perfect", 120)
	end
	T.eq(s.combo, Config.score.maxCombo)
end)

T.test("частичное кольцо даёт половину и сбрасывает комбо", function()
	local s = Score.new()
	Score.awardRing(s, "perfect", 120)
	Score.awardRing(s, "perfect", 120)
	T.eq(s.combo, 3)
	local p = Score.awardRing(s, "partial", 120)
	T.eq(p, 60)
	T.eq(s.combo, 1)
end)

T.test("провал кольца не даёт очков и сбрасывает комбо", function()
	local s = Score.new()
	Score.awardRing(s, "perfect", 120)
	local p = Score.awardRing(s, "fail", 120)
	T.eq(p, 0)
	T.eq(s.combo, 1)
	T.eq(s.perfects, 1)
	T.eq(s.fails, 1)
end)

T.test("подобранная птица даёт бонус", function()
	local s = Score.new()
	T.eq(Score.awardRecovery(s), Config.score.recoverBonus)
	T.eq(s.recovered, 1)
end)

T.test("бонус за собранную стаю начисляется на чистом кольце", function()
	local state = Score.new()
	local base = Score.awardRing(state, "perfect", 100)
	T.ok(base > 0, "чистое кольцо даёт очки")
	local bonus = Score.awardPerfectFlock(state)
	T.ok(bonus > 0, "бонус за собранную стаю должен начисляться")
	T.eq(state.score, base + bonus, "очки чистого кольца складываются с бонусом за стаю")
end)

T.test("итоговый счёт включает бонус за выжившую стаю", function()
	local state = Score.new()
	Score.awardRing(state, "perfect", 100)
	local bonus = Score.endFlockBonus(14, 18)
	T.ok(bonus > 0, "бонус за выживших птиц должен быть больше нуля")
	T.eq(Score.finalScore(state, 14, 18), state.score + bonus, "итог = счёт + бонус")
	T.eq(Score.endFlockBonus(0, 18), 0, "без птиц бонуса нет")
	T.eq(Score.endFlockBonus(30, 18), Score.endFlockBonus(18, 18), "бонус не может превысить размер стаи")
end)

T.test("проверка правдоподобности отсекает невозможный счёт", function()
	T.ok(Score.isPlausible(5000, 60), "нормальный счёт должен проходить")
	T.ok(not Score.isPlausible(9_000_000, 60), "невозможный счёт должен отсекаться")
	T.ok(not Score.isPlausible(-10, 60), "отрицательный счёт невозможен")
	T.ok(not Score.isPlausible(1000, 0), "счёт без времени невозможен")
end)

return T

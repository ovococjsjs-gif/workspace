--!strict
--[=[
	Сценарии поведения пилота для проверки баланса.
	Запуск: bash tools/scenario.sh [calm|reckless|zigzag]
	Печатает состояние стаи: нервозность вожака, панику, расстояния до вожака.
]=]

local Game = require("./Game")
local Flock = require("./Flock")
local Vec = require("./Vec")
local Course = require("./Course")

local MODE = "__MODE__" -- подставляется скриптом запуска
local SECONDS = __SECONDS__ -- длительность забега, сек

local function pilot(g: Game.Game, mode: string): Game.Input
	local boost = false
	local cp = Course.pointAt(g.leaderPos.z)
	local x = math.clamp((g.leaderPos.x - cp.pos.x) * 0.06, -1, 1)
	local y = math.clamp((20 - g.leaderPos.y) * 0.05, -1, 1)
	local z = 1.0
	if mode == "reckless" then
		x = math.sin(g.time * 5.5)
		y = math.sin(g.time * 3.1) * 0.6
		z = 0.5 + 0.5 * math.sin(g.time * 2.3)
	elseif mode == "zigzag" then
		x = if g.time % 4 < 2 then 1 else -1
		z = 1
	elseif mode == "booster" then
		local err = Flock.averageSlotError(g.flock, {
			leaderPos = g.leaderPos,
			courseForward = cp.tangent,
			courseRight = cp.right,
			wind = Vec.zero(),
			time = g.time,
		})
		z = if err > 26 then 0.35 elseif err > 14 then 0.7 else 1.0
		-- Рывок раз в 5 секунд (когда стая в порядке).
		boost = g.time % 5 < 0.05
	elseif mode == "calm" then
		local err = Flock.averageSlotError(g.flock, {
			leaderPos = g.leaderPos,
			courseForward = cp.tangent,
			courseRight = cp.right,
			wind = Vec.zero(),
			time = g.time,
		})
		z = if err > 26 then 0.35 elseif err > 14 then 0.7 else 1.0
	end
	return { x = x, y = y, z = z, boost = boost }
end

local game = Game.new(20261018)
local maxDist = 0
for i = 1, 60 * SECONDS do
	local events = Game.step(game, 1 / 60, pilot(game, MODE))
	for _, event in events do
		for _, ring in event.rings do
			print(string.format("  кольцо %d: %s %d/%d", ring.id, ring.result, ring.passedCount, ring.totalCount))
		end
		if event.gameOver then
			print(string.format("[%6.1fs] ИГРА ОКОНЧЕНА: осталось птиц %d", game.time, Flock.inFormation(game.flock)))
		end
	end
	for _, bird in game.flock.birds do
		maxDist = math.max(maxDist, Vec.dist(bird.pos, game.leaderPos))
	end
	if i % 300 == 0 then
		local alive = Flock.inFormation(game.flock)
		print(string.format(
			"[%6.1fs] аг=%0.2f паника=%0.2f живо=%d/18 макс.дист=%0.0f отставание=%0.0f счёт=%d комбо=x%d",
			game.time, game.agitation, game.flock.panic, alive, maxDist,
			Flock.averageLag(game.flock, game.leaderPos), game.score.score, game.score.combo
		))
	end
end
print(string.format("ИТОГО (%s): счёт=%d колец=%d чистых=%d живо=%d макс.дист=%.0f",
	MODE, game.score.score, game.score.rings, game.score.perfects,
	Flock.inFormation(game.flock), maxDist))

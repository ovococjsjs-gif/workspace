--!strict
--[=[
	Диагностический прогон игры без Roblox (для отладки баланса).
	Запуск: bash tools/probe.sh
	Печатает состояние забега по секундам и разбор каждого пересечения кольца.
]=]

local Game = require("./Game")
local Flock = require("./Flock")
local Vec = require("./Vec")
local Course = require("./Course")
local Rings = require("./Rings")

local DT = 1 / 60
local game = Game.new(20261018)

local function autopilot(g: Game.Game): Game.Input
	local cp0 = Course.pointAt(g.leaderPos.z)
	local err = Flock.averageSlotError(g.flock, {
		leaderPos = g.leaderPos,
		courseForward = cp0.tangent,
		courseRight = cp0.right,
		wind = Vec.zero(),
		time = g.time,
	})
	local z = 1.0
	if err > 26 then
		z = 0.35
	elseif err > 14 then
		z = 0.7
	end
	local cp = Course.pointAt(g.leaderPos.z)
	local x = math.clamp((g.leaderPos.x - cp.pos.x) * 0.06, -1, 1)
	local y = math.clamp((20 - g.leaderPos.y) * 0.05, -1, 1)
	return { x = x, y = y, z = z }
end

for i = 1, 60 * 120 do
	local events = Game.step(game, DT, autopilot(game))
	for _, event in events do
		for _, ring in event.rings do
			print(string.format(
				"[%6.1fs] кольцо %d: %s  прошло %d/%d  очки=%d",
				game.time, ring.id, ring.result, ring.passedCount, ring.totalCount, ring.points
			))
			if ring.result ~= "perfect" then
				for _, rr in game.rings.rings do
					if rr.id == ring.id then
						local minR, maxR = 1e9, -1e9
						for _, b in game.flock.birds do
							local rad = Rings.radialDistance(rr, b.pos)
							minR = math.min(minR, rad)
							maxR = math.max(maxR, rad)
						end
						print(string.format("    кольцо z=%.0f радиус=%.1f наклон=%.2f минРадиус=%.1f максРадиус=%.1f лидерZ=%.0f",
							rr.pos.z, rr.radius, Vec.dot(rr.normal, Vec.new(0,0,1)), minR, maxR, game.leaderPos.z))
					end
				end
			end
		end
	end
	if i % 600 == 0 then
		print(string.format(
			"[%6.1fs] лидер=(%.0f,%.0f,%.0f) скорость=%.1f отставание=%.1f в строю=%d/%d счёт=%d комбо=x%d",
			game.time,
			game.leaderPos.x, game.leaderPos.y, game.leaderPos.z,
			Vec.len(game.leaderVel),
			Flock.averageLag(game.flock, game.leaderPos),
			Flock.inFormation(game.flock), #game.flock.birds,
			game.score.score, game.score.combo
		))
	end
end

print("")
print(string.format("ИТОГО: счёт=%d колец=%d чистых=%d частичных=%d провалов=%d собрано=%d",
	game.score.score, game.score.rings, game.score.perfects, game.score.partials, game.score.fails, game.score.recovered))

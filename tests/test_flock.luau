--!strict
--[=[
	Тесты симуляции стаи: строй, потеря птиц, подбор (rally).
]=]

local T = require(script.Parent.Framework)
local Vec = require(script.Parent.Vec)
local Flock = require(script.Parent.Flock)
local Config = require(script.Parent.Config)

local function ctxAt(pos: Vec.Vec3): Flock.FlockContext
	return {
		leaderPos = pos,
		courseForward = Vec.new(0, 0, 1),
		courseRight = Vec.new(1, 0, 0),
		wind = Vec.zero(),
		time = 0,
	}
end

T.test("Flock.new создаёт нужное число птиц в строю", function()
	local flock = Flock.new(12, 1)
	T.eq(#flock.birds, 12)
	T.eq(Flock.inFormation(flock), 12)
	T.near(Flock.cohesion(flock), 1)
end)

T.test("слоты строя симметричны: птицы поровну слева и справа", function()
	local left, right = 0, 0
	for slot = 0, 9 do
		local lateral = Flock.slotOffset(slot)
		if lateral > 0 then
			right += 1
		else
			left += 1
		end
	end
	T.eq(left, right)
end)

T.test("птицы сходятся к своим слотам", function()
	local flock = Flock.new(8, 7)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	-- разбрасываем птиц далеко от лидера
	for i = 1, #flock.birds do
		flock.birds[i].pos = Vec.new(leader.x + 20 + i * 1.5, leader.y + 4, leader.z - 12)
	end
	local before = Flock.averageDistance(flock, leader)
	for _ = 1, 240 do
		Flock.step(flock, 1 / 60, ctx)
	end
	local after = Flock.averageDistance(flock, leader)
	T.ok(after < before, string.format("расстояние должно уменьшиться: %s -> %s", tostring(before), tostring(after)))
	T.ok(after < 40, string.format("птицы должны собраться рядом с лидером, а не %s", tostring(after)))
end)

T.test("птица дальше scatterDistance теряется", function()
	local flock = Flock.new(4, 11)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	flock.birds[1].pos = Vec.new(leader.x + Config.bird.scatterDistance + 30, leader.y, leader.z)
	local events = Flock.step(flock, 1 / 60, ctx)
	T.eq(flock.birds[1].mode, "lost")
	T.eq(#events.scattered, 1)
end)

T.test("подбор (rally): лидер рядом — птица возвращается в строй", function()
	local flock = Flock.new(4, 13)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	-- одна птица "потерялась" и висит рядом с лидером
	flock.birds[1].mode = "lost"
	flock.birds[1].pos = Vec.new(leader.x + 5, leader.y, leader.z)
	flock.birds[1].vel = Vec.zero()

	local recovered = false
	for _ = 1, 600 do
		local events = Flock.step(flock, 1 / 60, ctx)
		if #events.recovered > 0 then
			recovered = true
			break
		end
	end
	T.ok(recovered, "птица должна вернуться в строй")
	T.eq(flock.birds[1].mode, "formation")
end)

T.test("потерянная птица не собирается сама, если лидер далеко", function()
	local flock = Flock.new(4, 17)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	flock.birds[1].mode = "lost"
	flock.birds[1].pos = Vec.new(leader.x + 80, leader.y + 5, leader.z)
	for _ = 1, 120 do
		Flock.step(flock, 1 / 60, ctx)
	end
	T.eq(flock.birds[1].mode, "lost")
end)

T.test("стая не проваливается под землю", function()
	local flock = Flock.new(6, 19)
	local leader = Vec.new(0, 3, 0)
	local ctx = ctxAt(leader)
	for _ = 1, 300 do
		Flock.step(flock, 1 / 60, ctx)
	end
	for i = 1, #flock.birds do
		T.ok(flock.birds[i].pos.y >= 1.9, string.format("птица %d провалилась: y=%s", i, tostring(flock.birds[i].pos.y)))
	end
end)

T.test("ветер сносит потерянных птиц", function()
	local flock = Flock.new(2, 23)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	ctx.wind = Vec.new(20, 0, 0)
	flock.birds[1].mode = "lost"
	flock.birds[1].pos = Vec.new(0, 20, 0)
	flock.birds[1].vel = Vec.zero()
	for _ = 1, 60 do
		Flock.step(flock, 1 / 60, ctx)
	end
	T.ok(flock.birds[1].pos.x > 1, "птица должна сноситься по ветру: x=" .. tostring(flock.birds[1].pos.x))
end)

T.test("симуляция детерминирована при одинаковом сиде", function()
	local a = Flock.new(8, 99)
	local b = Flock.new(8, 99)
	local leader = Vec.new(0, 20, 0)
	local ctx = ctxAt(leader)
	for _ = 1, 120 do
		Flock.step(a, 1 / 60, ctx)
		Flock.step(b, 1 / 60, ctx)
	end
	for i = 1, #a.birds do
		T.vecNear(a.birds[i].pos, b.birds[i].pos, 1e-9, string.format("птица %d разошлась", i))
	end
end)

return T

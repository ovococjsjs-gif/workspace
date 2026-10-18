--!strict
--[=[
	Тесты колец-ворот: пересечение, «чистое» прохождение, частичное, провал.
]=]

local T = require(script.Parent.Framework)
local Vec = require(script.Parent.Vec)
local Rings = require(script.Parent.Rings)
local Config = require(script.Parent.Config)

--- Кольцо, поставленное вручную в начале координат, нормаль — вдоль +Z.
local function testRing(radius: number?): Rings.Ring
	return {
		id = 1,
		pos = Vec.new(0, 0, 0),
		normal = Vec.new(0, 0, 1),
		right = Vec.new(1, 0, 0),
		up = Vec.new(0, 1, 0),
		radius = radius or 20,
		baseScore = Config.ring.baseScore,
		state = "waiting",
		result = "none",
		passedCount = 0,
		totalCount = 0,
		openedAt = 0,
		spawnedAt = 0,
		grace = 1.0,
	}
end

T.test("кольцо ставится впереди по трассе", function()
	local world = Rings.new(5)
	local ring = Rings.spawn(world, 200, 25)
	T.ok(ring.pos.z > 190, "кольцо должно быть на трассе: z=" .. tostring(ring.pos.z))
	T.near(Vec.len(ring.normal), 1, 1e-9)
end)

T.test("птица за плоскостью и внутри радиуса прошла кольцо", function()
	local ring = testRing(20)
	T.ok(Rings.birdPassed(ring, Vec.new(0, 0, 5)), "птица за плоскостью внутри радиуса")
	T.ok(not Rings.birdPassed(ring, Vec.new(0, 0, -5)), "птица ДО плоскости не прошла")
	T.ok(not Rings.birdPassed(ring, Vec.new(40, 0, 5)), "птица вне радиуса не прошла")
end)

T.test("лидер пересекает кольцо — кольцо открывается", function()
	local world = Rings.new(7)
	world.rings = {}
	local ring = testRing(20)
	table.insert(world.rings, ring)
	local events = Rings.update(world, 1 / 60, 0, Vec.new(0, 0, -1), {})
	T.eq(#events, 0)
	T.eq(ring.state, "waiting")
	events = Rings.update(world, 1 / 60, 0.1, Vec.new(0, 0, 1), {})
	T.eq(ring.state, "crossed")
end)

T.test("все птицы прошли — кольцо засчитано как чистое", function()
	local world = Rings.new(7)
	world.rings = {}
	local ring = testRing(20)
	table.insert(world.rings, ring)
	local birds = { Vec.new(0, 0, 2), Vec.new(3, 1, 3), Vec.new(-4, -2, 4) }
	Rings.update(world, 1 / 60, 0, Vec.new(0, 0, -1), birds)
	Rings.update(world, 1 / 60, 0.1, Vec.new(0, 0, 1), birds)
	-- следующий шаг уже проверяет, прошла ли вся стая
	local events = Rings.update(world, 1 / 60, 0.2, Vec.new(0, 0, 2), birds)
	T.eq(#events, 1)
	T.eq(events[1].result, "perfect")
	T.eq(events[1].passedCount, 3)
end)

T.test("часть птиц не прошла — по истечении окна кольцо частичное", function()
	local world = Rings.new(7)
	world.rings = {}
	local ring = testRing(20)
	ring.grace = 0.5
	table.insert(world.rings, ring)
	local birds = { Vec.new(0, 0, 2), Vec.new(0, 0, -30) }
	Rings.update(world, 1 / 60, 0, Vec.new(0, 0, -1), birds)
	Rings.update(world, 1 / 60, 0.1, Vec.new(0, 0, 1), birds)
	local events = Rings.update(world, 1 / 60, 1.0, Vec.new(0, 0, 2), birds)
	T.eq(#events, 1)
	T.eq(events[1].result, "partial")
	T.eq(events[1].passedCount, 1)
end)

T.test("никто не прошёл — кольцо провалено", function()
	local world = Rings.new(7)
	world.rings = {}
	local ring = testRing(20)
	ring.grace = 0.5
	table.insert(world.rings, ring)
	local birds = { Vec.new(0, 0, -30), Vec.new(0, 0, -31) }
	Rings.update(world, 1 / 60, 0, Vec.new(0, 0, -1), birds)
	Rings.update(world, 1 / 60, 0.1, Vec.new(0, 0, 1), birds)
	local events = Rings.update(world, 1 / 60, 1.0, Vec.new(0, 0, 2), birds)
	T.eq(#events, 1)
	T.eq(events[1].result, "fail")
end)

T.test("окно на сбор стаи реально даёт время (grace из конфига)", function()
	T.ok(Config.ring.grace >= 1.0, "окно должно быть достаточно большим")
end)

T.test("кольца спавнятся впереди лидера и не копятся", function()
	local world = Rings.new(3)
	Rings.ensureSpawned(world, 0, 25, 90)
	T.ok(#world.rings >= 1, "должно появиться хотя бы одно кольцо")
	for _, ring in world.rings do
		T.ok(ring.pos.z > 0, "кольцо должно быть впереди")
	end
	local before = #world.rings
	-- лидер уехал далеко — должны появиться новые кольца
	Rings.ensureSpawned(world, 400, 25, 90)
	T.ok(#world.rings > before, "после движения лидера кольца должны добавляться")
end)

return T

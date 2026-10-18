--!strict
--[=[
	Кольца-ворота: генерация, проверка пересечения и подсчёт результата.
	Чистый Luau (без Roblox-глобалов) — тестируется в интерпретаторе.

	Правило игры: лидер пересекает плоскость кольца, после чего у стаи есть
	окно (grace) — нужно, чтобы ВСЕ птицы тоже оказались за плоскостью и
	внутри радиуса кольца. Тогда кольцо засчитывается как «чистое».
]=]

local Vec = require(script.Parent.Vec)
local Config = require(script.Parent.Config)
local Course = require(script.Parent.Course)
local Rng = require(script.Parent.Rng)

export type Vec3 = Vec.Vec3

export type RingResult = "none" | "perfect" | "partial" | "fail"

export type Ring = {
	id: number,
	pos: Vec3,
	normal: Vec3,
	right: Vec3,
	up: Vec3,
	radius: number,
	baseScore: number,
	state: "waiting" | "crossed" | "resolved",
	result: RingResult,
	passedCount: number,
	totalCount: number,
	openedAt: number,
	spawnedAt: number,
	grace: number,
}

export type RingWorld = {
	rings: { Ring },
	nextId: number,
	nextSpawnZ: number,
	rng: Rng.Rng,
	leaderPrevSigned: { [number]: number },
}

export type RingEvent = {
	ring: Ring,
	result: RingResult,
	passedCount: number,
	totalCount: number,
}

local Rings = {}

function Rings.new(seed: number?): RingWorld
	return {
		rings = {},
		nextId = 1,
		nextSpawnZ = Config.ring.firstSpawnAhead,
		rng = Rng.new(seed or 424242),
		leaderPrevSigned = {},
	}
end

--- Ставит кольцо на трассе, немного наклоняя его (чтобы нельзя было тупо лететь по центру).
function Rings.spawn(world: RingWorld, z: number, radius: number): Ring
	local cp = Course.pointAt(z)
	local tilt = Rng.nextRange(world.rng, -Config.ring.maxTilt, Config.ring.maxTilt)
	local roll = Rng.nextRange(world.rng, -Config.ring.maxTilt, Config.ring.maxTilt)

	-- Наклон вокруг касательной и вокруг «вверх» курса.
	local normal = Vec.norm(Vec.add(cp.tangent, Vec.scale(cp.right, tilt)), cp.tangent)
	local baseUp = Vec.norm(Vec.cross(cp.right, normal), Vec.new(0, 1, 0))
	-- Доворачиваем кольцо вокруг оси курса (roll), чтобы кольца не были все одинаковыми.
	local cr, sr = math.cos(roll), math.sin(roll)
	local side = Vec.norm(Vec.cross(normal, baseUp), cp.right)
	local up = Vec.norm(
		Vec.add(Vec.scale(baseUp, cr), Vec.scale(side, sr)),
		baseUp
	)
	local right = Vec.norm(Vec.cross(normal, up), cp.right)

	local ring: Ring = {
		id = world.nextId,
		pos = cp.pos,
		normal = normal,
		right = right,
		up = up,
		radius = radius,
		baseScore = Config.ring.baseScore,
		state = "waiting",
		result = "none",
		passedCount = 0,
		totalCount = 0,
		openedAt = 0,
		spawnedAt = 0,
		grace = Config.ring.grace,
	}
	world.nextId += 1
	table.insert(world.rings, ring)
	return ring
end

--- Подписанное расстояние точки до плоскости кольца (>0 = за кольцом).
function Rings.signedDistance(ring: Ring, pos: Vec3): number
	return Vec.dot(Vec.sub(pos, ring.pos), ring.normal)
end

--- Радиальное расстояние от оси кольца.
function Rings.radialDistance(ring: Ring, pos: Vec3): number
	local delta = Vec.sub(pos, ring.pos)
	local radial = Vec.projectOnPlane(delta, ring.normal)
	return Vec.len(radial)
end

--- Птица «прошла» кольцо, если она за плоскостью и внутри радиуса.
function Rings.birdPassed(ring: Ring, pos: Vec3): boolean
	if Rings.signedDistance(ring, pos) < -2.0 then
		return false
	end
	return Rings.radialDistance(ring, pos) <= ring.radius
end

--- Создаёт кольца впереди лидера, пока не хватает.
function Rings.ensureSpawned(world: RingWorld, leaderZ: number, radius: number, gap: number): ()
	local horizon = leaderZ + Config.ring.firstSpawnAhead + gap
	while world.nextSpawnZ < horizon do
		local r = radius * Rng.nextRange(world.rng, 0.92, 1.08)
		Rings.spawn(world, world.nextSpawnZ, r)
		world.nextSpawnZ += gap * Rng.nextRange(world.rng, 0.92, 1.12)
	end
end

--- Конструктор события (явная аннотация нужна, чтобы literal-типы не расширялись до string).
local function makeEvent(ring: Ring, result: RingResult, passedCount: number, totalCount: number): RingEvent
	return { ring = ring, result = result, passedCount = passedCount, totalCount = totalCount }
end

--- Главный шаг: проверяет пересечения, считает прошедших птиц, резолвит кольца.
--- `birdPositions` — массив позиций птиц.
function Rings.update(
	world: RingWorld,
	dt: number,
	time: number,
	leaderPos: Vec3,
	birdPositions: { Vec3 }
): { RingEvent }
	local events: { RingEvent } = {}

	for i = #world.rings, 1, -1 do
		local ring = world.rings[i]
		ring.totalCount = #birdPositions

		if ring.state == "waiting" then
			local signed = Rings.signedDistance(ring, leaderPos)
			local prev = world.leaderPrevSigned[ring.id] or -1
			if signed >= 0 and prev < 0 then
				ring.state = "crossed"
				ring.openedAt = time
			end
			world.leaderPrevSigned[ring.id] = signed

			if time - ring.spawnedAt > Config.ring.timeout then
				ring.state = "resolved"
				ring.result = "fail"
				table.insert(events, makeEvent(ring, "fail", 0, #birdPositions))
			end
		elseif ring.state == "crossed" then
			local passed = 0
			for b = 1, #birdPositions do
				if Rings.birdPassed(ring, birdPositions[b]) then
					passed += 1
				end
			end
			ring.passedCount = passed

			if passed >= #birdPositions and #birdPositions > 0 then
				ring.state = "resolved"
				ring.result = "perfect"
				table.insert(events, makeEvent(ring, "perfect", passed, #birdPositions))
			elseif time - ring.openedAt > ring.grace then
				ring.state = "resolved"
				local outcome: RingResult = if passed > 0 then "partial" else "fail"
				ring.result = outcome
				table.insert(events, makeEvent(ring, outcome, passed, #birdPositions))
			end
		else
			-- resolved: держим ещё немного для визуала, потом убираем
			if time - ring.openedAt > 3.0 and ring.result ~= "none" then
				table.remove(world.rings, i)
				world.leaderPrevSigned[ring.id] = nil
			end
		end
	end

	return events
end

return Rings

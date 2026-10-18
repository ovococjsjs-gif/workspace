--!strict
--[=[
	Препятствия-камни, висящие в воздухе: отталкивают птиц (и делают поздние фазы
	по-настоящему опасными). Чистый Luau — тестируется в интерпретаторе.
]=]

local Vec = require(script.Parent.Vec)
local Course = require(script.Parent.Course)
local Rng = require(script.Parent.Rng)

export type Vec3 = Vec.Vec3

export type Obstacle = {
	--- Стабильный идентификатор: по нему клиент держит визуалы.
	id: number,
	pos: Vec3,
	radius: number,
	strength: number,
}

export type ObstacleWorld = {
	obstacles: { Obstacle },
	nextSpawnZ: number,
	nextId: number,
	rng: Rng.Rng,
}

export type ObstacleEvents = {
	--- Индексы птиц, которые оттолкнулись в этом шаге.
	pushed: { number },
	--- Индексы птиц, которые попали в камень (для «вспышки»).
	hit: { number },
}

local Obstacles = {}

function Obstacles.new(seed: number?): ObstacleWorld
	return {
		obstacles = {},
		nextSpawnZ = 160,
		nextId = 1,
		rng = Rng.new(seed or 777),
	}
end

--- Ставит камни впереди по трассе (с вероятностью chance на камень).
function Obstacles.ensureSpawned(world: ObstacleWorld, leaderZ: number, chance: number, gap: number): ()
	if chance <= 0 then
		return
	end
	local horizon = leaderZ + 320
	while world.nextSpawnZ < horizon do
		if Rng.nextFloat(world.rng) < chance then
			local cp = Course.pointAt(world.nextSpawnZ)
			local lateral = Rng.nextRange(world.rng, -26, 26)
			local height = Rng.nextRange(world.rng, 8, 42)
			local pos = Vec.add(cp.pos, Vec.scale(cp.right, lateral))
			pos.y = height
			table.insert(world.obstacles, {
				id = world.nextId,
				pos = pos,
				radius = Rng.nextRange(world.rng, 4.5, 8.5),
				strength = Rng.nextRange(world.rng, 60.0, 115.0),
			})
			world.nextId += 1
		end
		world.nextSpawnZ += gap
	end
end

--- Убирает камни, которые остались позади.
function Obstacles.cull(world: ObstacleWorld, leaderZ: number): ()
	local i = 1
	while i <= #world.obstacles do
		if world.obstacles[i].pos.z < leaderZ - 60 then
			table.remove(world.obstacles, i)
		else
			i += 1
		end
	end
end

--- Толкает птиц от камней. Мутирует скорости птиц (birds[i].vel).
function Obstacles.applyPush(world: ObstacleWorld, birds: { any }, dt: number): ObstacleEvents
	local events: ObstacleEvents = { pushed = {}, hit = {} }
	for o = 1, #world.obstacles do
		local obstacle = world.obstacles[o]
		for i = 1, #birds do
			local bird = birds[i]
			local delta = Vec.sub(bird.pos, obstacle.pos)
			local dist = Vec.len(delta)
			local range = obstacle.radius + 9.0
			if dist < range and dist > 0.001 then
				local dir = Vec.scale(delta, 1 / dist)
				local power = obstacle.strength * (1 - dist / range)
				bird.vel = Vec.add(bird.vel, Vec.scale(dir, power * dt))
				table.insert(events.pushed, i)
				if dist < obstacle.radius + 1.5 then
					table.insert(events.hit, i)
				end
			end
		end
	end
	return events
end

return Obstacles

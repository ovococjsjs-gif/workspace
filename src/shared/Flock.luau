--!strict
--[=[
	Стая: чистая симуляция поведения птиц (boids-lite + строй).
	Никаких Roblox-глобалов — модуль полностью тестируется в интерпретаторе Luau.

	Модель:
	  * у каждой птицы есть "слот" в V-образном строю относительно лидера;
	  * птица тянется к своему слоту пружиной, расталкиваясь с соседями;
	  * если птица отстала дальше scatterDistance — она "теряется" (lost):
	    дрейфует по ветру и тонет; лидер может подобрать её (rally);
	  * подобранная птица сначала "returning" (aggressive gain), потом снова в строю.
]=]

local Vec = require(script.Parent.Vec)
local Config = require(script.Parent.Config)
local Rng = require(script.Parent.Rng)

export type Vec3 = Vec.Vec3

export type BirdMode = "formation" | "lost" | "returning"

export type Bird = {
	pos: Vec3,
	vel: Vec3,
	slot: number,
	mode: BirdMode,
	flap: number,
	seed: number,
	lostTime: number,
}

export type Flock = {
	birds: { Bird },
	count: number,
	rng: Rng.Rng,
	--- Текущий уровень паники стаи (0..1).
	panic: number,
}

export type FlockContext = {
	leaderPos: Vec3,
	courseForward: Vec3,
	courseRight: Vec3,
	wind: Vec3,
	time: number,
	--- Насколько вожак "нервничает" (0..1): резкие манёвры пугают стаю.
	leaderAgitation: number?,
	--- Турбулентность ветра (0..1): порыв бьёт по птицам неравномерно,
	--- стая рвётся и вытягивается. В штиль — ноль.
	turbulence: number?,
	--- Переопределение конфигурации стаи (например, увеличенный радиус магнита).
	cfg: FlockConfig?,
}

--- Конфигурация стаи (обычно Config.flock, но перки могут её менять).
export type FlockConfig = typeof(Config.bird)

export type FlockEvents = {
	--- Индексы птиц, которые были подобраны в этом шаге.
	recovered: { number },
	--- Индексы птиц, которые потерялись в этом шаге.
	scattered: { number },
}

local UP = Vec.new(0, 1, 0)

local Flock = {}

--- Смещение слота в строю относительно лидера (в системе координат курса).
--- slot 0 и 1 — первая пара, 2 и 3 — вторая и т.д.
--- ВАЖНО: самый дальний слот должен быть ближе bird.scatterDistance,
--- иначе птица в строю считалась бы "потерянной" (см. тест).
function Flock.slotOffset(slot: number): (number, number, number)
	local rank = math.floor((slot + 1) / 2)
	local side = if slot % 2 == 0 then 1 else -1
	local lateral = side * (4.0 + rank * 2.2)
	local back = 7.0 + rank * 4.4
	local vertical = ((slot % 3) - 1) * 2.4
	return lateral, back, vertical
end

function Flock.new(count: number?, seed: number?): Flock
	local n = count or Config.flockSize
	local rng = Rng.new(seed or 20261018)
	local birds: { Bird } = {}
	for i = 1, n do
		local jitter = Rng.nextInSphere(rng, 3.0)
		birds[i] = {
			pos = Vec.new(jitter.x, 14 + jitter.y, -20 - i * 2.2 + jitter.z),
			vel = Vec.zero(),
			slot = i - 1,
			mode = "formation",
			flap = Rng.nextFloat(rng) * math.pi * 2,
			seed = Rng.nextFloat(rng),
			lostTime = 0,
		}
	end
	return { birds = birds, count = n, rng = rng, panic = 0 }
end

--- Целевая позиция слота в мире.
function Flock.slotTarget(ctx: FlockContext, slot: number): Vec3
	local lateral, back, vertical = Flock.slotOffset(slot)
	local target = Vec.copy(ctx.leaderPos)
	target = Vec.add(target, Vec.scale(ctx.courseRight, lateral))
	target = Vec.add(target, Vec.scale(ctx.courseForward, -back))
	target = Vec.add(target, Vec.scale(UP, vertical))
	return target
end

--- Шаг симуляции стаи. Возвращает события (подбор/потеря птиц).
function Flock.step(flock: Flock, dt: number, ctx: FlockContext): FlockEvents
	local events: FlockEvents = { recovered = {}, scattered = {} }
	-- Перки могут подменять конфиг стаи (например, радиус магнита).
	local cfg = ctx.cfg or Config.bird
	local birds = flock.birds

	-- Уровень паники: растёт от нервозности вожака, затухает со временем.
	local agitation = ctx.leaderAgitation or 0
	flock.panic = math.max(flock.panic * math.max(0, 1 - dt * 0.7), agitation)

	-- Сильная паника вырывает птиц из строя: они разлетаются и их надо собирать.
	if flock.panic > Config.bird.panicBreakAt then
		local chance = (flock.panic - Config.bird.panicBreakAt) * Config.bird.panicBreakRate * dt
		for i = 1, #birds do
			local bird = birds[i]
			if bird.mode == "formation" and Rng.nextFloat(flock.rng) < chance then
				bird.mode = "lost"
				bird.lostTime = 0
				bird.vel = Vec.add(bird.vel, Rng.nextInSphere(flock.rng, 14.0))
				table.insert(events.scattered, i)
			end
		end
	end

	for i = 1, #birds do
		local bird = birds[i]
		bird.flap = bird.flap + dt * (9.0 + bird.seed * 4.0)

		if bird.mode == "lost" then
			-- Дрейф по ветру + медленное падение.
			bird.vel = Vec.add(bird.vel, Vec.scale(ctx.wind, dt))
			bird.vel = Vec.add(bird.vel, Vec.new(0, -cfg.lostSink * dt, 0))
			-- Трение: без него ветром относит потерянную птицу бесконечно.
			bird.vel = Vec.scale(bird.vel, math.max(0, 1 - cfg.lostDrag * dt))
			bird.vel = Vec.clampMag(bird.vel, cfg.maxSpeed)
			bird.pos = Vec.add(bird.pos, Vec.scale(bird.vel, dt))
			-- Земля: птица не проваливается (даже потерянная).
			if bird.pos.y < 2.0 then
				bird.pos.y = 2.0
				if bird.vel.y < 0 then
					bird.vel.y = 0
				end
			end
			bird.lostTime += dt

			-- Магнит: если вожак подошёл близко, птица сама тянется к нему.
			-- Так «подобрать» приятно и не нужно ловить её вручную.
			local toLeader = Vec.sub(ctx.leaderPos, bird.pos)
			local leaderDist = Vec.len(toLeader)
			if leaderDist < cfg.magnetRadius then
				local pull = (1 - leaderDist / cfg.magnetRadius) * cfg.magnetStrength
				bird.vel = Vec.add(bird.vel, Vec.scale(Vec.norm(toLeader, ctx.courseForward), pull * dt))
			end

			if leaderDist <= cfg.rallyRadius then
				bird.mode = "returning"
			end
		else
			local target = Flock.slotTarget(ctx, bird.slot)
			local toTarget = Vec.sub(target, bird.pos)
			local dist = Vec.len(toTarget)

			local gain = if bird.mode == "returning" then cfg.steerGain * 1.9 else cfg.steerGain
			local desiredVel = Vec.scale(Vec.norm(toTarget, ctx.courseForward), math.min(cfg.maxSpeed, dist * cfg.catchupGain))
			local accel = Vec.scale(Vec.sub(desiredVel, bird.vel), gain)

			-- Ветер сносит даже в строю; в бурю бьёт по птицам неравномерно —
			-- именно из-за этого стая вытягивается и рвётся.
			local gust = 1
			if ctx.turbulence and ctx.turbulence > 0 then
				gust = 1 + ctx.turbulence * math.sin(bird.seed * 1.7)
			end
			accel = Vec.add(accel, Vec.scale(ctx.wind, cfg.windOnBirds * 0.9 * gust))

				-- Расталкивание (квадрат расстояния — без лишнего sqrt на каждую пару).
			local sepR = cfg.separationRadius
			local sepR2 = sepR * sepR
			for j = 1, #birds do
				if j ~= i then
					local other = birds[j]
					local d2 = Vec.distSq(bird.pos, other.pos)
					if d2 < sepR2 and d2 > 1e-6 then
						local d = math.sqrt(d2)
						local push = Vec.scale(Vec.sub(bird.pos, other.pos), (sepR - d) / sepR)
						accel = Vec.add(accel, Vec.scale(push, cfg.separationGain))
					end
				end
			end

			-- Паника: если вожак дёргается, стая вскидывается в стороны.
			if cfg.panicGain > 0 and flock.panic > 0.02 then
				local jitter = Rng.nextInSphere(flock.rng, flock.panic * cfg.panicGain * dt)
				accel = Vec.add(accel, jitter)
			end

			accel = Vec.clampMag(accel, cfg.maxAccel)
			bird.vel = Vec.add(bird.vel, Vec.scale(accel, dt))
			bird.vel = Vec.scale(bird.vel, math.max(0, 1 - cfg.damping * dt))
			bird.pos = Vec.add(bird.pos, Vec.scale(bird.vel, dt))

			if bird.pos.y < 2.0 then
				bird.pos.y = 2.0
				bird.vel.y = math.abs(bird.vel.y) * 0.4
			end

			if bird.mode == "returning" then
				if dist <= cfg.joinedDistance then
					bird.mode = "formation"
					table.insert(events.recovered, i)
				end
			elseif Vec.dist(ctx.leaderPos, bird.pos) > cfg.scatterDistance then
				-- Отстала именно от лидера (а не от слота): слот может быть далеко по построению.
				bird.mode = "lost"
				bird.lostTime = 0
				table.insert(events.scattered, i)
			end
		end
	end

	return events
end

--- Сколько птиц сейчас в строю (не потеряно).
function Flock.inFormation(flock: Flock): number
	local n = 0
	for i = 1, #flock.birds do
		if flock.birds[i].mode == "formation" then
			n += 1
		end
	end
	return n
end

--- Доля птиц в строю, 0..1.
function Flock.cohesion(flock: Flock): number
	if #flock.birds == 0 then
		return 0
	end
	return Flock.inFormation(flock) / #flock.birds
end

--- Средняя дистанция от птиц до лидера.
function Flock.averageDistance(flock: Flock, leaderPos: Vec3): number
	if #flock.birds == 0 then
		return 0
	end
	local sum = 0
	for i = 1, #flock.birds do
		sum += Vec.dist(flock.birds[i].pos, leaderPos)
	end
	return sum / #flock.birds
end

--- Среднее отставание стаи по курсу (насколько птицы отстали от лидера ВПЕРЁД по курсу).
--- Это честная метрика «успевает ли стая»: расстояние до лидера включает
--- и естественный разброс строя, а отставание по курсу — нет.
function Flock.averageLag(flock: Flock, leaderPos: Vec3): number
	if #flock.birds == 0 then
		return 0
	end
	local sum = 0
	for i = 1, #flock.birds do
		sum += leaderPos.z - flock.birds[i].pos.z
	end
	return sum / #flock.birds
end

--- Средняя ошибка строя: насколько птицы отстоят от своих слотов.
--- 0 — строй идеален. Не зависит от размера строя, в отличие от расстояния до лидера.
function Flock.averageSlotError(flock: Flock, ctx: FlockContext): number
	if #flock.birds == 0 then
		return 0
	end
	local sum = 0
	for i = 1, #flock.birds do
		local bird = flock.birds[i]
		if bird.mode == "formation" then
			sum += Vec.dist(bird.pos, Flock.slotTarget(ctx, bird.slot))
		else
			sum += 120 -- потерянная птица — считаем как большую ошибку
		end
	end
	return sum / #flock.birds
end


return Flock

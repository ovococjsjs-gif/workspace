--!strict
--[=[
	Игровой цикл «СТАИ» — целиком в чистом Luau (без Roblox-API).

	Это ключевое архитектурное решение: клиент (src/client/Main.client.luau) только
	читает ввод, вызывает Game.step() и рисует состояние. Благодаря этому весь
	игровой цикл можно прогнать headless в интерпретаторе Luau — см. tests/test_simulation.luau.
]=]

local Vec = require(script.Parent.Vec)
local Config = require(script.Parent.Config)
local Course = require(script.Parent.Course)
local Flock = require(script.Parent.Flock)
local Rings = require(script.Parent.Rings)
local Difficulty = require(script.Parent.Difficulty)
local Score = require(script.Parent.Score)
local Perms = require(script.Parent.Perms)
local Obstacles = require(script.Parent.Obstacles)

export type Vec3 = Vec.Vec3

export type Input = {
	x: number,
	y: number,
	z: number,
	--- Запрошен ли «рывок» (ускорение вожака) в этом кадре.
	boost: boolean?,
}

export type RingOutcome = {
	id: number,
	result: string,
	points: number,
	passedCount: number,
	totalCount: number,
}

export type GameEvent = {
	rings: { RingOutcome },
	recovered: number,
	scattered: number,
	phaseIndex: number?,
	phaseName: string?,
	gameOver: boolean,
	--- Вожак пошёл на «рывок».
	boost: boolean,
	--- Началось «затишье» (второй шанс).
	mercy: boolean,
}

export type Game = {
	--- Перки игрока (покупки за Robux), приходят с сервера.
	perms: Perms.Perms,
	--- Конфигурация стаи с учётом перков (радиус магнита и т.п.).
	flockCfg: Flock.FlockConfig,
	--- Сид забега. Один и тот же сид у всех участников гонки даёт
	--- полностью одинаковый курс (кольца, камни, раскладка стаи).
	seed: number,
	mode: string, -- "playing" | "over"
	time: number,
	leaderPos: Vec3,
	leaderVel: Vec3,
	--- Сглаженное направление полёта (для оценки "нервозности" вожака).
	smoothDir: Vec3,
	--- Нервозность вожака (0..1): стая паникует, если вожак дёргается.
	agitation: number,
	--- Предыдущий ввод игрока — для оценки резкости управления.
	prevInput: Input,
	--- Осталось времени активного «рывка», сек.
	boostTime: number,
	--- Осталось до перезарядки «рывка», сек.
	boostCooldown: number,
	--- Осталось времени «затишья» (ветр стихает, камни не спавнятся), сек.
	mercyTime: number,
	--- Был ли рывок активирован в этом кадре (для события/звука).
	boostStarted: boolean,
	flock: Flock.Flock,
	rings: Rings.RingWorld,
	obstacles: Obstacles.ObstacleWorld,
	score: Score.ScoreState,
	phaseIndex: number,
	lostTimer: number,
	ringGraceLeft: number?,
	ringGraceTotal: number?,
	events: { GameEvent },
}

local UP = Vec.new(0, 1, 0)

local Game = {}

function Game.new(seed: number?, perms: Perms.Perms?): Game
	local runSeed = seed or 20261018
	local game: Game = {
		perms = perms or Perms.new(),
		flockCfg = table.clone(Config.bird),
		seed = runSeed,
		mode = "playing",
		time = 0,
		leaderPos = Vec.new(0, 20, 0),
		leaderVel = Vec.zero(),
		smoothDir = Vec.new(0, 0, 1),
		agitation = 0,
		prevInput = { x = 0, y = 0, z = 0 },
		boostTime = 0,
		boostCooldown = 0,
		boostStarted = false,
		mercyTime = 0,
		flock = Flock.new(Config.flockSize, runSeed),
		rings = Rings.new(runSeed + 1),
		obstacles = Obstacles.new(runSeed + 2),
		score = Score.new(),
		phaseIndex = 1,
		lostTimer = 0,
		ringGraceLeft = nil,
		ringGraceTotal = nil,
		events = {},
	}
	Game.reset(game)
	return game
end

--- Полный сброс забега (новая стая, новые кольца, счёт в ноль).
function Game.reset(game: Game): ()
	game.time = 0
	game.leaderPos = Vec.new(0, 20, 0)
	game.leaderVel = Vec.zero()
	game.smoothDir = Vec.new(0, 0, 1)
	game.agitation = 0
	game.prevInput = { x = 0, y = 0, z = 0 }
	game.boostTime = 0
	game.boostCooldown = 0
	game.boostStarted = false
	game.mercyTime = 0
	game.flock = Flock.new(Config.flockSize, game.seed)
	-- Перки меняют параметры стаи: например, «Магнит+» расширяет зону подбора.
	game.flockCfg = table.clone(Config.bird)
	game.flockCfg.magnetRadius = Perms.magnetRadius(game.perms, Config.bird.magnetRadius)
	game.rings = Rings.new(game.seed + 1)
	game.obstacles = Obstacles.new(game.seed + 2)
	game.score = Score.new()
	-- «Форсаж»: забег сразу начинается с двойного комбо.
	game.score.combo = Perms.startCombo(game.perms)
	game.phaseIndex = 1
	game.lostTimer = 0
	game.ringGraceLeft = nil
	game.ringGraceTotal = nil
	game.events = {}
	game.mode = "playing"

	-- Стая стартует сразу за лидером, ровно по слотам строя:
	-- так первый кадр (и стартовый экран) выглядит как собранная стая.
	local cp = Course.pointAt(0)
	local ctx: Flock.FlockContext = {
		leaderPos = game.leaderPos,
		courseRight = cp.right,
		courseForward = cp.tangent,
		wind = Vec.zero(),
		time = 0,
		leaderAgitation = 0,
	}
	for i = 1, #game.flock.birds do
		local bird = game.flock.birds[i]
		bird.pos = Flock.slotTarget(ctx, bird.slot)
		bird.vel = Vec.zero()
	end
end

--- Подпись курса: одинаковый сид — одинаковая подпись.
--- Используется в гонке, чтобы убедиться, что у всех участников один курс.
function Game.courseSignature(game: Game): number
	local h = 2166136261
	local function mix(v: number)
		-- В Luau нет побитовых операций, поэтому обычная модульная арифметика.
		h = (h * 31 + math.floor(v * 1000) % 100000) % 4294967296
	end
	for _, ring in game.rings.rings do
		mix(ring.pos.x)
		mix(ring.pos.y)
		mix(ring.pos.z)
		mix(ring.radius)
	end
	mix(game.seed)
	return h
end

--- Сила ветра: базовая + порывы, растёт от фазы к фазе.
--- Текущий вектор ветра в мировых координатах (для интерфейса).
function Game.windVector(game: Game): Vec3
	local cp = Course.pointAt(game.leaderPos.z)
	local phase = Difficulty.phaseAt(game.time)
	local scale = if game.mercyTime > 0 then Config.mercy.windFactor else 1.0
	-- «Ветрокром»: в интерфейсе ветер тоже не показывается.
	return Vec.scale(
		cp.right,
		Game.windStrength(game.time, phase) * scale * Perms.windFactor(game.perms)
	)
end

function Game.windStrength(time: number, phase: Difficulty.Phase): number
	local period = Config.wind.gustPeriod
	local raw = math.sin(time * (2 * math.pi / period))
	local sharp = math.sign(raw) * math.pow(math.abs(raw), 1 / Config.wind.gustSharpness)
	return phase.windStrength * (1.0 + 0.9 * sharp)
end

local function updateLeader(game: Game, dt: number, wind: Vec3, input: Input): ()
	local cp = Course.pointAt(game.leaderPos.z)

	-- «Рывок»: короткое ускорение вожака. Быстрее едешь — больше очков за
	-- расстояние, но стая (60 ед/с) не успевает и начинает отваливаться.
	if game.boostTime > 0 then
		game.boostTime = math.max(0, game.boostTime - dt)
	end
	if game.boostCooldown > 0 then
		game.boostCooldown = math.max(0, game.boostCooldown - dt)
	end
	game.boostStarted = false
	if input.boost and game.boostCooldown <= 0 and game.boostTime <= 0 then
		game.boostTime = Config.leader.boostDuration
		game.boostCooldown = Config.leader.boostDuration
			+ Perms.boostCooldown(game.perms, Config.leader.boostCooldown)
		game.boostStarted = true
	end
	local boosting = game.boostTime > 0
	local maxSpeed = if boosting then Config.leader.boostSpeed else Config.leader.maxSpeed

	-- Модель полёта: тяга по направлению ввода + сопротивление воздуха.
	-- Так стрейф не гасит движение вперёд, а отпускание газа даёт плавное торможение.
	local thrust = Config.leader.thrust * (if boosting then Config.leader.boostThrust else 1.0)
	local accel = Vec.zero()
	accel = Vec.add(accel, Vec.scale(cp.tangent, input.z * thrust))
	accel = Vec.add(accel, Vec.scale(cp.right, input.x * thrust * Config.leader.strafeFactor))
	accel = Vec.add(accel, Vec.scale(UP, input.y * thrust * Config.leader.strafeFactor))
	accel = Vec.add(accel, Vec.scale(wind, 0.4))

	game.leaderVel = Vec.add(game.leaderVel, Vec.scale(accel, dt))
	game.leaderVel = Vec.scale(game.leaderVel, math.max(0, 1 - Config.leader.drag * dt))
	game.leaderVel = Vec.clampMag(game.leaderVel, maxSpeed)
	game.leaderPos = Vec.add(game.leaderPos, Vec.scale(game.leaderVel, dt))

	-- Мягко держим лидера в коридоре трассы (вдоль «правой» оси курса).
	local offset = Course.lateralOffset(game.leaderPos, cp.pos)
	local limit = Config.leader.corridorRadius
	if math.abs(offset) > limit then
		local excess = (math.abs(offset) - limit) * math.sign(offset)
		game.leaderVel = Vec.sub(game.leaderVel, Vec.scale(cp.right, excess * Config.leader.corridorPull * dt))
	end

	-- Высота.
	if game.leaderPos.y < Config.leader.minHeight then
		game.leaderPos.y = Config.leader.minHeight
		if game.leaderVel.y < 0 then
			game.leaderVel.y = 0
		end
	elseif game.leaderPos.y > Config.leader.maxHeight then
		game.leaderPos.y = Config.leader.maxHeight
		if game.leaderVel.y > 0 then
			game.leaderVel.y = 0
		end
	end
end

--- Один шаг игры. `input` — оси в системе координат курса (x — вправо, y — вверх, z — вперёд).
--- Возвращает список событий (в т.ч. gameOver).
function Game.step(game: Game, dt: number, input: Input): { GameEvent }
	local events: { GameEvent } = {}
	if game.mode ~= "playing" then
		game.events = events
		return events
	end

	game.time += dt
	local phase = Difficulty.phaseAt(game.time)

	local event: GameEvent = {
		rings = {},
		recovered = 0,
		scattered = 0,
		phaseIndex = nil,
		phaseName = nil,
		gameOver = false,
		boost = false,
		mercy = false,
	}
	if game.boostStarted then
		event.boost = true
	end

	if phase.index ~= game.phaseIndex then
		game.phaseIndex = phase.index
		event.phaseIndex = phase.index
		event.phaseName = phase.name
	end

	local cp = Course.pointAt(game.leaderPos.z)

	-- «Затишье»: если стая на грани развала, ветер стихает — второй шанс.
	if game.mercyTime > 0 then
		game.mercyTime = math.max(0, game.mercyTime - dt)
	end
	local aliveNow = Flock.inFormation(game.flock)
	if game.mercyTime <= 0 and aliveNow > 0 and aliveNow <= Config.mercy.aliveThreshold then
		game.mercyTime = Config.mercy.duration
		event.mercy = true
	end
	local mercyActive = game.mercyTime > 0

	-- Ветер — поперечный, в системе координат курса (иначе он «плывёт» вместе с изгибом трассы).
	local windScale = if mercyActive then Config.mercy.windFactor else 1.0
	-- «Ветрокром»: ветер не сносит ни вожака, ни стаю.
	local wind = Vec.scale(
		cp.right,
		Game.windStrength(game.time, phase) * windScale * Perms.windFactor(game.perms)
	)

	updateLeader(game, dt, wind, input)

	-- Нервозность вожака: насколько сильно текущее направление отличается
	-- от сглаженного. Резкие рывки -> паника стаи.
	local curDir = Vec.norm(game.leaderVel, game.smoothDir)
	local blend = math.clamp(dt * 6.0, 0, 1)
	game.smoothDir = Vec.norm(Vec.lerp(game.smoothDir, curDir, blend), curDir)
	local mismatch = 1 - Vec.dot(game.smoothDir, curDir)

	-- Резкость управления: игрок дёргает стиком -> стая нервничает.
	-- Это главный «материальный» навык: чем плавнее ведёшь вожака, тем спокойнее стая.
	local jerk = math.abs(input.x - game.prevInput.x)
		+ math.abs(input.y - game.prevInput.y)
		+ math.abs(input.z - game.prevInput.z)
	game.prevInput = { x = input.x, y = input.y, z = input.z }
	local inputJerk = jerk / math.max(dt, 1e-4) * 0.06

	-- Нервозность — сглаженная величина: одиночный рывок не пугает стаю,
	-- а вот постоянная дёрганая работа — да. Так «спокойствие» — реальный навык.
	-- «Хозяйка»: вожак нервничает меньше — стая спокойнее.
	local raw = math.clamp(math.max(mismatch * 7.0, inputJerk) * Perms.panicFactor(game.perms), 0, 1)
	game.agitation = game.agitation + (raw - game.agitation) * math.clamp(dt * 3.0, 0, 1)

	-- Камни отталкивают птиц (во время затишья их нет).
	Obstacles.ensureSpawned(
		game.obstacles,
		game.leaderPos.z,
		if mercyActive then 0 else phase.obstacleChance,
		120
	)
	Obstacles.cull(game.obstacles, game.leaderPos.z)
	Obstacles.applyPush(game.obstacles, game.flock.birds, dt)

	-- Стая.
	local ctx: Flock.FlockContext = {
		leaderPos = game.leaderPos,
		courseForward = cp.tangent,
		courseRight = cp.right,
		wind = wind,
		time = game.time,
		leaderAgitation = game.agitation,
		turbulence = phase.windStrength * 0.12 * windScale,
		cfg = game.flockCfg,
	}
	local flockEvents = Flock.step(game.flock, dt, ctx)
	event.recovered = #flockEvents.recovered
	event.scattered = #flockEvents.scattered
	for _ in flockEvents.recovered do
		Score.awardRecovery(game.score)
	end

	-- Кольца.
	Rings.ensureSpawned(game.rings, game.leaderPos.z, phase.ringRadius, phase.gap)
	local birdPositions: { Vec3 } = {}
	for i = 1, #game.flock.birds do
		table.insert(birdPositions, game.flock.birds[i].pos)
	end
	local ringEvents = Rings.update(game.rings, dt, game.time, game.leaderPos, birdPositions)
	for _, ringEvent in ringEvents do
		local points = Score.awardRing(game.score, ringEvent.result, ringEvent.ring.baseScore)
		if ringEvent.result == "perfect" then
			-- Бонус за то, что стая собрана целиком.
			points += Score.awardPerfectFlock(game.score)
		end
		table.insert(event.rings, {
			id = ringEvent.ring.id,
			result = ringEvent.result,
			points = points,
			passedCount = ringEvent.passedCount,
			totalCount = ringEvent.totalCount,
		})
	end

	-- Окно кольца для интерфейса.
	local openRing: Rings.Ring? = nil
	for _, ring in game.rings.rings do
		if ring.state == "crossed" then
			openRing = ring
			break
		end
	end
	if openRing then
		game.ringGraceLeft = openRing.grace - (game.time - openRing.openedAt)
		game.ringGraceTotal = openRing.grace
	else
		game.ringGraceLeft = nil
		game.ringGraceTotal = nil
	end

	-- Проигрыш: стая рассыпалась и не собирается.
	-- Считаем не только полную потерю, но и критическую: меньше minAlive птиц
	-- в строю — забег уже не спасти.
	local alive = Flock.inFormation(game.flock)
	if alive <= Config.minAlive then
		game.lostTimer += dt
		if game.lostTimer > 4 then
			game.mode = "over"
			event.gameOver = true
		end
	else
		game.lostTimer = 0
	end

	table.insert(events, event)
	game.events = events
	return events
end

--- Текущее состояние стаи для интерфейса.
function Game.flockAlive(game: Game): number
	return Flock.inFormation(game.flock)
end

function Game.flockTotal(game: Game): number
	return #game.flock.birds
end

--- Текущая фаза.
function Game.phase(game: Game): Difficulty.Phase
	return Difficulty.phaseAt(game.time)
end

return Game

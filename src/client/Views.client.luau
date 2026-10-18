--[=[
	Визуальная часть: лидер («кайт»), птицы, кольца-ворота.
	Симуляция живёт в чистых модулях (src/shared), здесь — только отображение.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)

local Vec = require(Shared.Vec)
local Config = require(Shared.Config)
local Course = require(Shared.Course)
local Flock = require(Shared.Flock)
local Rings = require(Shared.Rings)
local Obstacles = require(Shared.Obstacles)

local Views = {}

export type RingVisual = {
	segments: { Part },
	membrane: Part,
	id: number,
}

local leaderPart: Part? = nil
local leaderHalo: Part? = nil
local tailPart: Part? = nil
local birdBodies: { Part } = {}
local birdWings: { Part } = {}
--- Маячки над потерянными птицами: игрок должен видеть, кого искать.
local birdBeacons: { Part } = {}
local ringVisuals: { [number]: RingVisual } = {}
--- Камни-препятствия: визуализация общих данных Obstacles.
local obstacleVisuals: { [number]: Part } = {}
--- «Призраки» соперников: маркер, нимб и маленькая стая для каждого игрока.
local ghostParts: { [number]: { marker: Part, halo: Part, birds: { Part } } } = {}
--- Сколько птиц рисуем у соперника.
local GHOST_BIRDS = 6

--- Палитра цветов призраков (по кругу).
local GHOST_COLORS = {
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 140, 200),
	Color3.fromRGB(160, 255, 140),
	Color3.fromRGB(255, 220, 110),
	Color3.fromRGB(190, 140, 255),
	Color3.fromRGB(120, 255, 230),
}

local COLOR_LEADER = Color3.fromRGB(255, 176, 64)
local COLOR_BIRD = Color3.fromRGB(250, 246, 232)
local COLOR_BIRD_LOST = Color3.fromRGB(240, 110, 96)
local COLOR_BIRD_BACK = Color3.fromRGB(255, 214, 132)
local COLOR_RING_WAIT = Color3.fromRGB(96, 232, 176)
local COLOR_RING_OPEN = Color3.fromRGB(255, 178, 66)
local COLOR_RING_DONE = Color3.fromRGB(226, 92, 82)

local function makePart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Locked = true
	part.Parent = workspace
	return part
end

function Views.build(flockSize: number)
	if leaderPart then
		return
	end

	-- Лидер: светящийся шар + нимб + след.
	local leader = makePart("Leader", Vector3.new(3.4, 3.4, 3.4), COLOR_LEADER, Enum.Material.Neon, Enum.PartType.Ball)
	leader.LightEmission = 0.7
	leaderPart = leader

	local halo = makePart(
		"LeaderHalo",
		Vector3.new(0.4, 9, 9),
		Color3.fromRGB(255, 220, 150),
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		0.45
	)
	halo.LightEmission = 0.4
	leaderHalo = halo

	local tail = makePart("LeaderTail", Vector3.new(0.2, 0.2, 0.2), COLOR_LEADER, Enum.Material.SmoothPlastic)
	tail.Transparency = 1
	tailPart = tail

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, 0)
	att0.Parent = leader
	local att1 = Instance.new("Attachment")
	att1.Parent = tail

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 206, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 206, 120)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Lifetime = 0.45
	trail.MinLength = 0.1
	trail.MaxLength = 10
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Parent = leader

	-- Птицы: тело + крыло.
	for i = 1, flockSize do
		local body = makePart("Bird" .. i, Vector3.new(1.7, 1.4, 2.4), COLOR_BIRD, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		local wing = makePart("Wing" .. i, Vector3.new(2.6, 0.22, 1.1), COLOR_BIRD, Enum.Material.SmoothPlastic)
		local beacon = makePart(
			"Beacon" .. i,
			Vector3.new(1.1, 1.1, 1.1),
			COLOR_BIRD_LOST,
			Enum.Material.Neon,
			Enum.PartType.Ball,
			0.25
		)
		beacon.LightEmission = 1
		beacon.Transparency = 1
		table.insert(birdBodies, body)
		table.insert(birdWings, wing)
		table.insert(birdBeacons, beacon)
	end
end

local function toVector(v: Vec.Vec3): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

function Views.updateLeader(
	leaderPos: Vec.Vec3,
	leaderVel: Vec.Vec3,
	courseForward: Vec.Vec3,
	panic: number?,
	boost: boolean?
)
	if not leaderPart or not leaderHalo or not tailPart then
		return
	end
	leaderPart.Position = toVector(leaderPos)

	local speed = Vec.len(leaderVel)
	local forward = if speed > 1.5 then Vec.norm(leaderVel) else courseForward
	local haloCFrame = CFrame.lookAt(
		toVector(Vec.add(leaderPos, Vec.new(0, -2.4, 0))),
		toVector(Vec.add(leaderPos, Vec.add(Vec.new(0, -2.4, 0), forward)))
	)
	leaderHalo.CFrame = haloCFrame * CFrame.Angles(0, 0, math.pi / 2)

	local tailPos = Vec.add(leaderPos, Vec.scale(forward, -3.2))
	tailPart.Position = toVector(tailPos)

	-- Во время рывка след вожака становится золотым.
	local trail = leaderPart and leaderPart:FindFirstChildOfClass("Trail")
	if trail then
		local hot = boost == true
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, if hot then Color3.fromRGB(255, 236, 170) else Color3.fromRGB(255, 206, 120)),
			ColorSequenceKeypoint.new(1, if hot then Color3.fromRGB(255, 236, 170) else Color3.fromRGB(255, 206, 120)),
		})
		trail.LightEmission = if hot then 1.0 else 0.5
	end

	-- Нимб краснеет: стая нервничает из-за вожака.
	local level = math.clamp(panic or 0, 0, 1)
	leaderHalo.Color = Color3.fromRGB(
		math.round(255 * level + 255 * (1 - level)),
		math.round(220 * (1 - level) + 120 * level),
		math.round(150 * (1 - level) + 96 * level)
	)
	leaderPart.Color = Color3.fromRGB(
		255,
		math.round(176 - 60 * level),
		math.round(64 - 20 * level)
	)
end

function Views.updateBirds(flock: Flock.Flock)
	for i = 1, #flock.birds do
		local bird = flock.birds[i]
		local body = birdBodies[i]
		local wing = birdWings[i]
		if body and wing then
			local speed = Vec.len(bird.vel)
			local look = if speed > 1.0 then Vec.norm(bird.vel) else Vec.new(0, 0, 1)
			local cf = CFrame.lookAt(toVector(bird.pos), toVector(Vec.add(bird.pos, look)))
			-- Крыло машет: поворот вокруг продольной оси + крен корпуса по скорости.
			local flap = math.sin(bird.flap) * 0.7
			local bank = math.clamp(speed / 60, 0, 1) * 0.25
			local bodyCf = cf * CFrame.Angles(0, 0, bank)
			body.CFrame = bodyCf
			wing.CFrame = bodyCf * CFrame.Angles(0, 0, flap) * CFrame.new(0, 0.15 * math.cos(bird.flap), 0)

			local beacon = birdBeacons[i]
			if bird.mode == "lost" then
				local blink = (math.floor(bird.lostTime * 6) % 2) == 0
				body.Color = if blink then COLOR_BIRD_LOST else COLOR_BIRD
				wing.Color = body.Color
				if beacon then
					-- Пульсирующий маячок над потерянной птицей.
					local pulse = 1 + math.sin(bird.lostTime * 6) * 0.35
					beacon.Position = toVector(Vec.add(bird.pos, Vec.new(0, 7, 0)))
					beacon.Size = Vector3.new(1.6, 1.6, 1.6) * pulse
					beacon.Transparency = 0.15
				end
			elseif bird.mode == "returning" then
				body.Color = COLOR_BIRD_BACK
				wing.Color = COLOR_BIRD_BACK
				if beacon then
					beacon.Position = toVector(Vec.add(bird.pos, Vec.new(0, 7, 0)))
					beacon.Size = Vector3.new(1.4, 1.4, 1.4)
					beacon.Color = COLOR_BIRD_BACK
					beacon.Transparency = 0.35
				end
			else
				body.Color = COLOR_BIRD
				wing.Color = COLOR_BIRD
				if beacon then
					beacon.Transparency = 1
				end
			end
		end
	end
end

local function destroyRingVisual(id: number)
	local visual = ringVisuals[id]
	if not visual then
		return
	end
	for _, segment in visual.segments do
		segment:Destroy()
	end
	visual.membrane:Destroy()
	ringVisuals[id] = nil
end

--- Запускает вспышку кольца (расходится и гаснет) в момент прохождения.
function Views.popRing(id: number, time: number)
	local visual = ringVisuals[id]
	if visual then
		visual.popAt = time
	end
end

--- Создаёт/обновляет визуал колец; удаляет визуалы исчезнувших колец.
function Views.updateRings(ringWorld: Rings.RingWorld, dt: number, time: number)
	local alive: { [number]: boolean } = {}

	for _, ring in ringWorld.rings do
		alive[ring.id] = true
		local visual = ringVisuals[ring.id]
		if not visual then
			local segments: { Part } = {}
			for i = 1, Config.ring.segments do
				local segment = makePart(
					"RingSegment",
					Vector3.new(3.0, 3.0, 4.2),
					COLOR_RING_WAIT,
					Enum.Material.Neon
				)
				segment.LightEmission = 0.6
				table.insert(segments, segment)
			end
			local membrane = makePart(
				"RingMembrane",
				Vector3.new(0.5, ring.radius * 2, ring.radius * 2),
				COLOR_RING_WAIT,
				Enum.Material.Neon,
				Enum.PartType.Cylinder,
				0.86
			)
			membrane.LightEmission = 0.25
			ringVisuals[ring.id] = { segments = segments, membrane = membrane, id = ring.id, popAt = nil }
			visual = ringVisuals[ring.id]
		end

		-- Окно кольца: пока стая не прошла, кольцо «закрывается» — радиус
		-- визуально сжимается, и цвет становится тревожным.
		local window = 1
		if ring.state == "crossed" then
			window = math.clamp(1 - (time - ring.openedAt) / math.max(ring.grace, 0.001), 0, 1)
		end

		-- Цвет кольца по состоянию.
		local color = COLOR_RING_WAIT
		if ring.state == "crossed" then
			color = if window < 0.4 then COLOR_RING_DONE else COLOR_RING_OPEN
		elseif ring.state == "resolved" then
			color = COLOR_RING_DONE
		end
		local pulse = 1 + math.sin(time * 3) * 0.06
		for _, segment in visual.segments do
			segment.Color = color
		end
		visual.membrane.Color = color

		-- Позиции сегментов: кольцо медленно вращается вокруг своей оси.
		local count = #visual.segments
		local spin = time * 0.6 + ring.id
		local visualRadius = ring.radius * (if ring.state == "crossed" then math.max(window, 0.12) else 1)

		-- Вспышка в момент прохождения: кольцо расходится и гаснет.
		local pop = -1
		if visual.popAt then
			pop = time - visual.popAt
			if pop > 0.5 then
				visual.popAt = nil
				pop = -1
				for _, segment in visual.segments do
					segment.Transparency = 0
				end
				visual.membrane.Transparency = 0.86
			else
				visualRadius = visualRadius * (1 + math.max(pop, 0) * 2.2)
			end
		end
		if pop >= 0 then
			local fade = math.clamp(pop * 2.4, 0, 1)
			for _, segment in visual.segments do
				segment.Transparency = fade
			end
			visual.membrane.Transparency = math.clamp(0.86 + fade * 0.14, 0, 1)
		end
		for i = 1, count do
			local angle = (i - 1) / count * math.pi * 2 + spin
			local cosA, sinA = math.cos(angle), math.sin(angle)
			local pos = Vec.add(ring.pos, Vec.add(Vec.scale(ring.right, cosA * visualRadius), Vec.scale(ring.up, sinA * visualRadius)))
			local tangent = Vec.add(Vec.scale(ring.right, -sinA), Vec.scale(ring.up, cosA))
			local segment = visual.segments[i]
			segment.Size = Vector3.new(3.0, 3.0, 4.2) * pulse
			segment.CFrame = CFrame.lookAt(toVector(pos), toVector(Vec.add(pos, tangent)))
		end
		local base = CFrame.fromMatrix(toVector(ring.pos), toVector(ring.right), toVector(ring.up), toVector(ring.normal))
		visual.membrane.CFrame = base * CFrame.Angles(0, math.pi / 2, 0)
		visual.membrane.Size = Vector3.new(0.5, visualRadius * 2, visualRadius * 2)
		visual.membrane.Transparency = if ring.state == "crossed" then 0.55 + 0.35 * (1 - window) else 0.86
	end

	for id in ringVisuals do
		if not alive[id] then
			destroyRingVisual(id)
		end
	end
end

--- Рисует камни-препятствия (общие данные из Obstacles).
function Views.updateObstacles(obstacleWorld: Obstacles.ObstacleWorld, time: number)
	-- Создаём недостающие визуалы (по id, чтобы они не путались при отсеве).
	for _, obstacle in obstacleWorld.obstacles do
		if not obstacleVisuals[obstacle.id] then
			local part = makePart(
				"Obstacle" .. obstacle.id,
				Vector3.new(8, 8, 8),
				Color3.fromRGB(120, 116, 128),
				Enum.Material.Slate
			)
			part.LightEmission = 0.15
			obstacleVisuals[obstacle.id] = part
		end
	end

	local alive: { [number]: boolean } = {}
	for _, obstacle in obstacleWorld.obstacles do
		alive[obstacle.id] = true
		local part = obstacleVisuals[obstacle.id]
		if part then
			part.CFrame = CFrame.new(obstacle.pos.x, obstacle.pos.y, obstacle.pos.z)
				* CFrame.Angles(time * 0.7, time * 0.45, 0)
			part.Size = Vector3.new(obstacle.radius * 2, obstacle.radius * 2, obstacle.radius * 2)
			part.Transparency = 0
		end
	end

	-- Убираем визуалы исчезнувших камней.
	for id, part in obstacleVisuals do
		if not alive[id] then
			part:Destroy()
			obstacleVisuals[id] = nil
		end
	end
end

--- Обновляет «призраков» соперников по рейтингу забега.
--- entry.pos — последняя известная позиция вожака соперника.
function Views.updateGhosts(entries: any, myUserId: number)
	if type(entries) ~= "table" then
		return
	end
	local seen: { [number]: boolean } = {}
	for _, entry in entries do
		if type(entry) == "table"
			and typeof(entry.userId) == "number"
			and entry.userId ~= myUserId
			and type(entry.pos) == "table"
			and typeof(entry.pos.x) == "number"
		then
			local uid = entry.userId
			seen[uid] = true
			local ghost = ghostParts[uid]
			if not ghost then
				local color = GHOST_COLORS[(uid % #GHOST_COLORS) + 1]
				local marker = makePart(
					"Ghost",
					Vector3.new(2.6, 2.6, 2.6),
					color,
					Enum.Material.Neon,
					Enum.PartType.Ball,
					0.35
				)
				marker.LightEmission = 0.5
				local halo = makePart(
					"GhostHalo",
					Vector3.new(0.3, 7, 7),
					color,
					Enum.Material.Neon,
					Enum.PartType.Cylinder,
					0.6
				)
				halo.LightEmission = 0.3
				-- Маленькая стая соперника: птицы строем в V за его вожаком.
				local birds: { Part } = {}
				for i = 1, GHOST_BIRDS do
					local bird = makePart(
						"GhostBird",
						Vector3.new(1.6, 1.2, 2.4),
						color,
						Enum.Material.SmoothPlastic,
						nil,
						0.45
					)
					table.insert(birds, bird)
				end
				ghost = { marker = marker, halo = halo, birds = birds }
				ghostParts[uid] = ghost
			end
			local position = Vector3.new(entry.pos.x, entry.pos.y, entry.pos.z)
			ghost.marker.Position = position
			ghost.halo.Position = position
			-- Строим стаю соперника по курсу трассы в его точке.
			local cp = Course.pointAt(entry.pos.z)
			local forward = Vector3.new(cp.tangent.x, cp.tangent.y, cp.tangent.z)
			local right = Vector3.new(cp.right.x, cp.right.y, cp.right.z)
			for i, bird in ghost.birds do
				local row = math.ceil(i / 2)
				local side = if i % 2 == 0 then 1 else -1
				bird.Position = position
					+ forward * (-row * 7)
					+ right * (side * row * 4)
					+ Vector3.new(0, -1.5, 0)
			end
		end
	end
	-- Убираем призраков, которые вышли из забега.
	local stale: { number } = {}
	for uid in ghostParts do
		if not seen[uid] then
			table.insert(stale, uid)
		end
	end
	for _, uid in stale do
		local ghost = ghostParts[uid]
		if ghost then
			ghost.marker:Destroy()
			ghost.halo:Destroy()
			for _, bird in ghost.birds do
				bird:Destroy()
			end
			ghostParts[uid] = nil
		end
	end
end

function Views.reset()
	for id in ringVisuals do
		destroyRingVisual(id)
	end
	for id, part in obstacleVisuals do
		part:Destroy()
		obstacleVisuals[id] = nil
	end
	for uid, ghost in ghostParts do
		ghost.marker:Destroy()
		ghost.halo:Destroy()
		for _, bird in ghost.birds do
			bird:Destroy()
		end
		ghostParts[uid] = nil
	end
end

return Views

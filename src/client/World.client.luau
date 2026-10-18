--[=[
	Мир: бесконечная «прокручивающаяся» ландшафтная лента вдоль курса.
	Никаких внешних ассетов — всё строится примитивами.
	Пропсы пересчитываются каждый кадр относительно позиции лидера,
	поэтому мир выглядит бесконечным, а число объектов постоянно.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Общие модули (собранные Rojo в ReplicatedStorage.FlockShared).
local Shared = ReplicatedStorage:WaitForChild("FlockShared", 10)
local Lighting = game:GetService("Lighting")

local Course = require(Shared.Course)
local Vec = require(Shared.Vec)

local World = {}

export type Prop = {
	part: Part,
	kind: string,
	offset: number,
	height: number,
	scale: number,
	tint: Color3,
	phase: number,
	--- Шаг расстановки этого вида пропсов (хранится в самом пропсе:
	--- индекс в общем списке не совпадает с индексом вида).
	spacing: number,
}

local props: { Prop } = {}
local ground: Part? = nil
local built = false

local KINDS = {
	{ kind = "tree", spacing = 55, size = Vector3.new(7, 13, 7), color = Color3.fromRGB(72, 138, 78), y = 6 },
	{ kind = "tree2", spacing = 61, size = Vector3.new(6, 10, 6), color = Color3.fromRGB(92, 158, 88), y = 5 },
	{ kind = "bush", spacing = 33, size = Vector3.new(6, 4, 6), color = Color3.fromRGB(104, 172, 96), y = 2 },
	{ kind = "rock", spacing = 47, size = Vector3.new(5, 4, 5), color = Color3.fromRGB(146, 146, 152), y = 2 },
	{ kind = "cloud", spacing = 210, size = Vector3.new(46, 14, 30), color = Color3.fromRGB(255, 255, 255), y = 86 },
	{ kind = "pylon", spacing = 42, size = Vector3.new(1.2, 9, 1.2), color = Color3.fromRGB(255, 214, 96), y = 4 },
}

function World.build()
	if built then
		return
	end
	built = true

	Lighting.ClockTime = 14.6
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(112, 124, 145)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 158, 172)
	Lighting.FogColor = Color3.fromRGB(196, 224, 242)
	Lighting.FogStart = 420
	Lighting.FogEnd = 1500
	Lighting.GlobalShadows = true

	-- Земля: большая плита, которая едет под игроком.
	local g = Instance.new("Part")
	g.Name = "Ground"
	g.Size = Vector3.new(1400, 10, 1400)
	g.Anchored = true
	g.CanCollide = false
	g.Material = Enum.Material.Grass
	g.Color = Color3.fromRGB(118, 176, 96)
	g.CFrame = CFrame.new(0, -5, 0)
	g.Parent = workspace
	ground = g

	-- Создаём пул пропсов.
	for _, kind in KINDS do
		for i = 1, 9 do
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Shape = Enum.PartType.Ball
			part.Size = kind.size
			part.Material = if kind.kind == "pylon" then Enum.Material.Neon else Enum.Material.SmoothPlastic
			part.Color = kind.color
			part.Transparency = if kind.kind == "cloud" then 0.35 else 0
			part.LightEmission = if kind.kind == "pylon" then 0.6 else 0
			part.Parent = workspace
			table.insert(props, {
				part = part,
				kind = kind.kind,
				offset = (i % 2 == 0 and 1 or -1) * (26 + (i * 37) % 60),
				height = kind.y,
				scale = 0.8 + ((i * 13) % 7) / 10,
				tint = kind.color,
				phase = (i * 0.7) % (math.pi * 2),
				spacing = kind.spacing,
			})
		end
	end
end

--- Палитры фаз: небо, туман и свет меняются вместе с фазой —
--- так прогресс забега читается даже боковым зрением.
local PHASE_LOOK = {
	{
		clock = 14.6,
		brightness = 2.4,
		ambient = Color3.fromRGB(112, 124, 145),
		outdoor = Color3.fromRGB(150, 158, 172),
		fog = Color3.fromRGB(196, 224, 242),
		fogStart = 420,
		fogEnd = 1500,
	},
	{
		clock = 13.2,
		brightness = 2.0,
		ambient = Color3.fromRGB(104, 116, 136),
		outdoor = Color3.fromRGB(140, 150, 168),
		fog = Color3.fromRGB(176, 202, 224),
		fogStart = 320,
		fogEnd = 1200,
	},
	{
		clock = 11.0,
		brightness = 1.6,
		ambient = Color3.fromRGB(92, 100, 118),
		outdoor = Color3.fromRGB(120, 130, 150),
		fog = Color3.fromRGB(150, 172, 198),
		fogStart = 240,
		fogEnd = 950,
	},
	{
		clock = 8.6,
		brightness = 1.2,
		ambient = Color3.fromRGB(74, 82, 102),
		outdoor = Color3.fromRGB(96, 106, 130),
		fog = Color3.fromRGB(112, 128, 158),
		fogStart = 150,
		fogEnd = 680,
	},
}

--- Перекрашивает мир под текущую фазу (1..4).
function World.setPhase(index: number)
	local look = PHASE_LOOK[math.clamp(index, 1, #PHASE_LOOK)]
	if not look then
		return
	end
	Lighting.ClockTime = look.clock
	Lighting.Brightness = look.brightness
	Lighting.Ambient = look.ambient
	Lighting.OutdoorAmbient = look.outdoor
	Lighting.FogColor = look.fog
	Lighting.FogStart = look.fogStart
	Lighting.FogEnd = look.fogEnd
end

--- Пересчитывает позиции пропсов относительно текущей позиции лидера.
function World.update(leaderPos: Vec.Vec3)
	if not built then
		return
	end
	if ground then
		-- Плита «переезжает» под игроком (с шагом, чтобы не было дрожания).
		local snap = 140
		ground.Position = Vector3.new(
			math.floor(leaderPos.x / snap) * snap,
			-5,
			math.floor(leaderPos.z / snap) * snap
		)
	end

	local baseZ = leaderPos.z
	for index, prop in props do
		local spacing = prop.spacing
		local z = baseZ + 70 + ((index * spacing) % (spacing * 9))
		local cp = Course.pointAt(z)
		local sway = math.sin(prop.phase + z * 0.01) * 3
		local pos = Vec.add(cp.pos, Vec.scale(cp.right, prop.offset + sway))
		pos.y = prop.height
		local part = prop.part
		local size = prop.part.Size * prop.scale
		part.Size = size
		part.CFrame = CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(0, prop.phase, 0)
	end
end

return World

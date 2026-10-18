--!nocheck
--[=[
	Мини-реализация API Roblox для headless-проверки клиентского слоя.

	ЗАЧЕМ: клиентский код (src/client) нельзя выполнить в интерпретаторе Luau
	из-за Roblox-глобалов. Этот мок даёт достаточно API, чтобы
	`require`-нуть клиентские модули, построить HUD/мир/визуалы и выполнить
	несколько кадров игрового цикла — и поймать рантайм-ошибки
	(опечатки в полях, nil-разыменования, неверные вызовы методов).

	ЧЕГО ЭТО НЕ ДАЁТ: мок — не Roblox. Он не проверяет реальную семантику
	движка (CFType, порядок рендера, реальные ассеты, DataStore).
	Это проверка «код запускается и не падает», а не «игра выглядит правильно».

	Использование: bash tools/smoke.sh
]=]

local Mock = {}

--- Ссылка на «локального» игрока мока (нужна для FireServer).
local localPlayerRef = nil

--- Виртуальные часы сервера (секунды). Двигаются только вызовом Mock.advance.
Mock.clock = 0.0

--- Сдвигает виртуальные часы сервера (для проверок обратного отсчёта и раундов).
function Mock.advance(seconds: number)
	Mock.clock += seconds
	return Mock.clock
end

--------------------------------------------------------------------------- V3Type

local V3Type = {}
V3Type.__index = V3Type
V3Type.__type = "V3Type"

function V3Type.new(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable({
		x = x,
		y = y,
		z = z,
		X = x,
		Y = y,
		Z = z,
		Magnitude = math.sqrt(x * x + y * y + z * z),
	}, V3Type)
end

V3Type.zero = V3Type.new(0, 0, 0)
V3Type.one = V3Type.new(1, 1, 1)

function V3Type.__add(a, b)
	return V3Type.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function V3Type.__sub(a, b)
	return V3Type.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function V3Type.__mul(a, s)
	if type(s) == "number" then
		return V3Type.new(a.x * s, a.y * s, a.z * s)
	end
	return a
end

function V3Type.__eq(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

--------------------------------------------------------------------------- V2Type

local V2Type = {}
V2Type.__index = V2Type
V2Type.__type = "V2Type"

function V2Type.new(x, y)
	x, y = x or 0, y or 0
	return setmetatable({
		x = x,
		y = y,
		X = x,
		Y = y,
		Magnitude = math.sqrt(x * x + y * y),
	}, V2Type)
end

V2Type.zero = V2Type.new(0, 0)

function V2Type.__eq(a, b)
	return a.x == b.x and a.y == b.y
end

--------------------------------------------------------------------------- CFType

local CFType = {}
CFType.__index = CFType
CFType.__type = "CFType"

function CFType.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ p = x, r = V3Type.zero }, CFType)
	end
	local pos = V3Type.new(x or 0, y or 0, z or 0)
	return setmetatable({
		p = pos,
		Position = pos,
		r = V3Type.zero,
		RightVector = V3Type.new(1, 0, 0),
		UpVector = V3Type.new(0, 1, 0),
		LookVector = V3Type.new(0, 0, -1),
	}, CFType)
end

function CFType.lookAt(from, to)
	return setmetatable({
		p = from,
		Position = from,
		look = to,
		r = V3Type.zero,
		RightVector = V3Type.new(1, 0, 0),
		UpVector = V3Type.new(0, 1, 0),
		LookVector = V3Type.new(0, 0, -1),
	}, CFType)
end

function CFType.fromMatrix(pos, right, up, back)
	return setmetatable({ p = pos, r = V3Type.zero }, CFType)
end

function CFType.Angles(x, y, z)
	return setmetatable({ p = V3Type.zero, angles = { x, y, z } }, CFType)
end

function CFType.__mul(a, b)
	return setmetatable({ p = a.p, r = a.r }, CFType)
end

function CFType.__add(a, b)
	return setmetatable({ p = a.p + b.p, r = a.r }, CFType)
end

--------------------------------------------------------------------------- U2Type

local U2Type = {}
U2Type.__index = U2Type
U2Type.__type = "U2Type"

function U2Type.fromScale(x, y)
	return setmetatable({ sx = x or 0, sy = y or 0, ox = 0, oy = 0 }, U2Type)
end

function U2Type.fromOffset(x, y)
	return setmetatable({ sx = 0, sy = 0, ox = x or 0, oy = y or 0 }, U2Type)
end

function U2Type.new(x, y, ox, oy)
	return setmetatable({ sx = x, sy = y, ox = ox, oy = oy }, U2Type)
end

function U2Type.__mul(a, s)
	if type(s) == "number" then
		return setmetatable({ sx = a.sx * s, sy = a.sy * s, ox = a.ox * s, oy = a.oy * s }, U2Type)
	end
	return a
end

--------------------------------------------------------------------------- UDim

local UDim = {
	new = function(scale, offset)
		return { scale = scale or 0, offset = offset or 0 }
	end,
}

local ColorSequenceKeypoint = {
	new = function(time, color)
		return { time = time, color = color }
	end,
}

local NumberSequenceKeypoint = {
	new = function(time, number)
		return { time = time, number = number }
	end,
}

--------------------------------------------------------------------------- C3Type

local C3Type = {}
C3Type.__index = C3Type
C3Type.__type = "C3Type"

function C3Type.fromRGB(r, g, b)
	return setmetatable({ r = r or 0, g = g or 0, b = b or 0 }, C3Type)
end

--------------------------------------------------------------------------- прочее

local function makeEnum(t)
	return setmetatable(t, {
		__index = function(_, key)
			local value = rawget(t, key)
			if value == nil then
				value = { name = key }
				rawset(t, key, value)
			end
			return value
		end,
	})
end

local EnumType = setmetatable({}, {
	__index = function(t, key)
		local value = makeEnum({})
		rawset(t, key, value)
		return value
	end,
})

EnumType.PartType = makeEnum({ Block = "Block", Ball = "Ball", Cylinder = "Cylinder" })
EnumType.Material = makeEnum({ Plastic = "Plastic", Neon = "Neon", Grass = "Grass", Slate = "Slate", SmoothPlastic = "SmoothPlastic" })
EnumType.Font = makeEnum({ GothamBold = "GothamBold", Gotham = "Gotham" })
EnumType.UserInputType = makeEnum({ MouseButton1 = "MouseButton1", Keyboard = "Keyboard", Touch = "Touch" })
-- KeyCode: значения-строки, чтобы ввод можно было проверять сравнением
-- (как это делает Input.client.luau: key == Enum.KeyCode.W).
EnumType.KeyCode = makeEnum({
	W = "W",
	A = "A",
	S = "S",
	D = "D",
	Up = "Up",
	Down = "Down",
	Left = "Left",
	Right = "Right",
	Space = "Space",
	LeftShift = "LeftShift",
	C = "C",
	Unknown = "Unknown",
})
EnumType.CameraType = makeEnum({ Scriptable = "Scriptable", Custom = "Custom" })
EnumType.EasingStyle = makeEnum({ Back = "Back", Quad = "Quad", Linear = "Linear" })
EnumType.EasingDirection = makeEnum({ Out = "Out", In = "In" })
EnumType.RollOffMode = makeEnum({ InverseTapered = "InverseTapered", Linear = "Linear" })
EnumType.TextXAlignment = makeEnum({ Left = "Left", Center = "Center", Right = "Right" })
EnumType.TextYAlignment = makeEnum({ Top = "Top", Center = "Center", Bottom = "Bottom" })
EnumType.ProductInfoResponse = makeEnum({
	Success = "Success",
	AlreadyProcessed = "AlreadyProcessed",
	NotProcessedYet = "NotProcessedYet",
})

local TweenInfo = {
	new = function(time, easingStyle, easingDirection)
		return { time = time, easingStyle = easingStyle, easingDirection = easingDirection }
	end,
}

local NumberSequence = {
	new = function(points)
		return { points = points }
	end,
}

local ColorSequence = {
	new = function(points)
		return { points = points }
	end,
}

--------------------------------------------------------------------------- InstanceType

local instanceMethods = {}

local instanceMt = {
	__index = function(t, k)
		local method = instanceMethods[k]
		if method ~= nil then
			return method
		end
		return rawget(t, k)
	end,
	__newindex = function(t, k, v)
		if k == "Parent" then
			rawset(t, "__parent", v)
			if type(v) == "table" and rawget(v, "__children") ~= nil then
				table.insert(v.__children, t)
			end
			return
		end
		rawset(t, k, v)
	end,
}

local function makeInstance(className, props)
	if className == "TextButton" or className == "ImageButton" then
		props = props or {}
		props.MouseButton1Click = props.MouseButton1Click or makeInstance("RBXScriptSignal", { Name = "MouseButton1Click" })
		props.MouseButton1Down = props.MouseButton1Down or makeInstance("RBXScriptSignal", { Name = "MouseButton1Down" })
		props.MouseButton1Up = props.MouseButton1Up or makeInstance("RBXScriptSignal", { Name = "MouseButton1Up" })
	end
	if className == "RemoteEvent" then
		props = props or {}
		props.OnClientEvent = props.OnClientEvent or makeInstance("RBXScriptSignal", { Name = "OnClientEvent" })
		props.OnServerEvent = props.OnServerEvent or makeInstance("RBXScriptSignal", { Name = "OnServerEvent" })
	end
	local inst = setmetatable({
		__class = className,
		__children = {},
		__parent = nil,
		__signals = {},
		__destroyed = false,
	}, instanceMt)
	for k, v in props or {} do
		rawset(inst, k, v)
	end
	return inst
end

instanceMethods.Destroy = function(self)
	self.__destroyed = true
	local parent = rawget(self, "__parent")
	if type(parent) == "table" and rawget(parent, "__children") then
		for i, child in ipairs(parent.__children) do
			if child == self then
				table.remove(parent.__children, i)
				break
			end
		end
	end
end

-- Иерархия классов (как в Roblox): Part — это BasePart, TextLabel — GuiObject и т.д.
local CLASS_PARENTS = {
	Part = "BasePart",
	TrussPart = "BasePart",
	WedgePart = "BasePart",
	MeshPart = "BasePart",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	TextBox = "GuiObject",
	ImageLabel = "GuiObject",
	ImageButton = "GuiObject",
	ScrollingFrame = "GuiObject",
	Frame = "GuiObject",
	ViewportFrame = "GuiObject",
}

local function isClass(className: string, wanted: string): boolean
	local current = className
	while current do
		if current == wanted then
			return true
		end
		current = CLASS_PARENTS[current]
	end
	return false
end

instanceMethods.IsA = function(self, className)
	return isClass(rawget(self, "__class"), className)
end

instanceMethods.FindFirstChild = function(self, name)
	for _, child in ipairs(rawget(self, "__children")) do
		if rawget(child, "Name") == name then
			return child
		end
	end
	return nil
end

instanceMethods.FindFirstChildOfClass = function(self, className)
	for _, child in ipairs(rawget(self, "__children")) do
		if rawget(child, "__class") == className then
			return child
		end
	end
	return nil
end

instanceMethods.WaitForChild = function(self, name, _timeout)
	local child = self:FindFirstChild(name)
	if child then
		return child
	end
	local special = rawget(self, "__special")
	if special and special[name] ~= nil then
		return special[name]
	end
	error("WaitForChild: '" .. tostring(name) .. "' отсутствует в моке", 2)
end

instanceMethods.GetDescendants = function(self)
	local out = {}
	local function walk(node)
		for _, child in ipairs(rawget(node, "__children")) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

instanceMethods.Connect = function(self, fn)
	table.insert(rawget(self, "__signals"), fn)
	return function() end
end

instanceMethods.PivotTo = function(self, cf)
	rawset(self, "__pivot", cf)
end

instanceMethods.FireServer = function(self, ...)
	local args = { ... }
	rawset(self, "__fired", args)
	-- В Roblox сервер получает первым аргументом игрока, отправившего событие.
	local onServer = rawget(self, "OnServerEvent")
	if onServer and rawget(onServer, "__signals") then
		for _, fn in ipairs(rawget(onServer, "__signals")) do
			fn(localPlayerRef, table.unpack(args))
		end
	end
end

instanceMethods.FireAllClients = function(self, ...)
	local args = { ... }
	rawset(self, "__firedAll", args)
	local onClient = rawget(self, "OnClientEvent")
	if onClient and rawget(onClient, "__signals") then
		for _, fn in ipairs(rawget(onClient, "__signals")) do
			fn(table.unpack(args))
		end
	end
end

instanceMethods.FireClient = function(self, ...)
	local args = { ... }
	rawset(self, "__fired", args)
	-- Событие клиенту: в моке клиент один (LocalPlayer).
	-- Первый аргумент FireClient — получатель, клиенту он не передаётся.
	local onClient = rawget(self, "OnClientEvent")
	if onClient and rawget(onClient, "__signals") then
		for _, fn in ipairs(rawget(onClient, "__signals")) do
			fn(table.unpack(args, 2))
		end
	end
end

instanceMethods.Play = function(self)
	rawset(self, "__played", true)
end

instanceMethods.Clone = function(self)
	return makeInstance(rawget(self, "__class"), {})
end

local function new(className, props)
	return makeInstance(className, props)
end

--------------------------------------------------------------------------- сервисы

local services = {}

local function signal(name)
	return makeInstance("RBXScriptSignal", { Name = name })
end

local function buildServices(shared)
	local players = makeInstance("Players", { Name = "Players" })
	local playerGui = makeInstance("PlayerGui", { Name = "PlayerGui" })
	local player = makeInstance("Player", {
		Name = "TestPlayer",
		UserId = 1,
		Character = nil,
		CharacterAdded = signal("CharacterAdded"),
	})
	rawset(player, "__special", { PlayerGui = playerGui })
	rawset(players, "__special", { TestPlayer = player })
	players.LocalPlayer = player
	localPlayerRef = player
	players.PlayerAdded = signal("PlayerAdded")
	players.PlayerRemoving = signal("PlayerRemoving")
	players.GetPlayerByUserId = function(_self, userId)
		if player.UserId == userId then
			return player
		end
		return nil
	end

	local runService = makeInstance("RunService", { Name = "RunService" })
	runService.Heartbeat = signal("Heartbeat")
	runService.RenderStepped = signal("RenderStepped")

	local replicatedStorage = makeInstance("ReplicatedStorage", { Name = "ReplicatedStorage" })
	rawset(replicatedStorage, "__special", { FlockShared = shared })

	local remotes = makeInstance("Folder", { Name = "FlockRemotes" })
	for _, remoteName in { "SubmitScore", "BestScore", "RequestBest" } do
		rawset(remotes, "__children", {})
		local remote = makeInstance("RemoteEvent", { Name = remoteName })
		rawset(remote, "Parent", remotes)
	end
	rawset(replicatedStorage, "__special", { FlockShared = shared, FlockRemotes = remotes })

	local workspaceService = makeInstance("Workspace", { Name = "Workspace" })
	-- Серверное время в моке: двигается только через Mock.advance (детерминированно).
	workspaceService.GetServerTimeNow = function()
		return 1700000000 + Mock.clock
	end
	workspaceService.CurrentCamera = makeInstance("Camera", {
		Name = "Camera",
		ViewportSize = V2Type.new(1920, 1080),
		FieldOfView = 78,
		CFrame = CFType.new(0, 0, 0),
	})

	local lighting = makeInstance("Lighting", { Name = "Lighting" })

	local tweenService = makeInstance("TweenService", { Name = "TweenService" })
	tweenService.Create = function(_self, instance, info, props)
		return {
			Play = function()
				if type(instance) == "table" and rawget(instance, "__class") ~= nil then
					for k, v in pairs(props or {}) do
						rawset(instance, k, v)
					end
				end
			end,
		}
	end

	local userInputService = makeInstance("UserInputService", { Name = "UserInputService" })
	userInputService.InputBegan = signal("InputBegan")
	userInputService.InputEnded = signal("InputEnded")
	userInputService.InputMoved = signal("InputMoved")
	userInputService.WindowFocusReleased = signal("WindowFocusReleased")
	userInputService.TouchEnabled = false
	userInputService.MouseEnabled = true

	local dataStoreService = makeInstance("DataStoreService", { Name = "DataStoreService" })
	dataStoreService.GetDataStore = function()
		return {
			GetAsync = function()
				return 0
			end,
			SetAsync = function() end,
		}
	end

	local soundService = makeInstance("SoundService", { Name = "SoundService" })

	-- Маркетплейс: промпты покупок и обработка чеков.
	local marketplaceService = makeInstance("MarketplaceService", { Name = "MarketplaceService" })
	marketplaceService.ProcessReceipt = nil
	marketplaceService.PromptGamePassPurchase = function(_self, player, id)
		rawset(marketplaceService, "__promptedPass", { player = player, id = id })
	end
	marketplaceService.PromptProductPurchase = function(_self, player, id, info)
		rawset(marketplaceService, "__promptedProduct", { player = player, id = id, info = info })
	end

	-- GameplayService: проверка владения game pass'ом.
	local gameplayService = makeInstance("GameplayService", { Name = "GameplayService" })
	gameplayService.__ownedPasses = {}
	gameplayService.PlayerHasPassAsync = function(_self, userId, id)
		local owned = rawget(gameplayService, "__ownedPasses")
		return owned[userId] ~= nil and owned[userId][id] == true
	end

	services.Players = players
	services.RunService = runService
	services.ReplicatedStorage = replicatedStorage
	services.Workspace = workspaceService
	services.Lighting = lighting
	services.TweenService = tweenService
	services.UserInputService = userInputService
	services.DataStoreService = dataStoreService
	services.SoundService = soundService
	services.MarketplaceService = marketplaceService
	services.GameplayService = gameplayService
	return services
end

--------------------------------------------------------------------------- установка глобалов

-- Собирает окружение Roblox-глобалов.
-- ВАЖНО: в CLI Luau каждый require-модуль получает СВОЮ копию глобалов,
-- поэтому глобалы нельзя «экспортировать» просто через _G. Вместо этого
-- prepare_sandbox.sh добавляет в начало каждого клиентского/серверного файла
-- заголовок с локальными алиасами, которые тянут значения отсюда.
function Mock.buildEnv(shared)
	local svc = buildServices(shared or {})

	local env = {
		game = {
			GetService = function(_self, name)
				return svc[name]
			end,
			Players = svc.Players,
			Workspace = svc.Workspace,
		},
		workspace = svc.Workspace,
		Instance = {
			new = new,
		},
		Vector3 = V3Type,
		Vector2 = V2Type,
		CFrame = CFType,
		UDim2 = U2Type,
		UDim = UDim,
		Color3 = C3Type,
		Enum = EnumType,
		TweenInfo = TweenInfo,
		NumberSequence = NumberSequence,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		-- В CLI нет библиотеки task — делаем синхронную заглушку.
		task = {
			delay = function(_seconds, fn)
				if type(fn) == "function" then
					fn()
				end
			end,
			spawn = function(fn, ...)
				if type(fn) == "function" then
					fn(...)
				end
			end,
			defer = function(fn, ...)
				if type(fn) == "function" then
					fn(...)
				end
			end,
			wait = function(seconds)
				return seconds or 0
			end,
		},
	}

	return env, svc
end

-- Общие модули игры (настоящие, из src/shared) — нужны серверу и клиенту.
local sharedModules = {
	Vec = require("./Vec"),
	Config = require("./Config"),
	Course = require("./Course"),
	Rng = require("./Rng"),
	Flock = require("./Flock"),
	Rings = require("./Rings"),
	Score = require("./Score"),
	Difficulty = require("./Difficulty"),
	Obstacles = require("./Obstacles"),
	Game = require("./Game"),
}

Mock.env, Mock.services = Mock.buildEnv(sharedModules)

return Mock

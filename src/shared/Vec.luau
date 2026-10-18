--!strict
--[=[
	Векторная математика для "СТАИ".
	Намеренно НЕ использует Roblox-глобалы (Vector3 и т.п.): модуль остаётся чистым Luau,
	поэтому его можно прогнать в обычном интерпретаторе Luau (см. tests/).
	Вектор — обычная таблица {x, y, z}; функции возвращают НОВЫЕ таблицы (иммутабельность).
]=]

export type Vec3 = { x: number, y: number, z: number }

local Vec = {}

function Vec.new(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

function Vec.zero(): Vec3
	return { x = 0, y = 0, z = 0 }
end

function Vec.copy(a: Vec3): Vec3
	return { x = a.x, y = a.y, z = a.z }
end

function Vec.add(a: Vec3, b: Vec3): Vec3
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

function Vec.sub(a: Vec3, b: Vec3): Vec3
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

function Vec.scale(a: Vec3, k: number): Vec3
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

function Vec.dot(a: Vec3, b: Vec3): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function Vec.cross(a: Vec3, b: Vec3): Vec3
	return {
		x = a.y * b.z - a.z * b.y,
		y = a.z * b.x - a.x * b.z,
		z = a.x * b.y - a.y * b.x,
	}
end

function Vec.len(a: Vec3): number
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

function Vec.lenSq(a: Vec3): number
	return a.x * a.x + a.y * a.y + a.z * a.z
end

function Vec.dist(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Vec.distSq(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

--- Нормирует вектор. Если длина ~ 0, возвращает `fallback`.
function Vec.norm(a: Vec3, fallback: Vec3?): Vec3
	local lSq = Vec.lenSq(a)
	if lSq < 1e-12 then
		return fallback or Vec.zero()
	end
	local l = math.sqrt(lSq)
	return { x = a.x / l, y = a.y / l, z = a.z / l }
end

function Vec.lerp(a: Vec3, b: Vec3, t: number): Vec3
	return {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
		z = a.z + (b.z - a.z) * t,
	}
end

--- Ограничивает длину вектора величиной maxLen.
function Vec.clampMag(a: Vec3, maxLen: number): Vec3
	local l = Vec.len(a)
	if l <= maxLen or l < 1e-6 then
		return Vec.copy(a)
	end
	return Vec.scale(a, maxLen / l)
end

--- Проекция a на плоскость с нормалью n (используется для радиального расстояния до кольца).
function Vec.projectOnPlane(a: Vec3, n: Vec3): Vec3
	local d = Vec.dot(a, n)
	return { x = a.x - n.x * d, y = a.y - n.y * d, z = a.z - n.z * d }
end

return Vec

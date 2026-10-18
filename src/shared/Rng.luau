--!strict
--[=[
	Детерминированный ГПСЧ (LCG). Чистый Luau — нужен, чтобы поведение было
	воспроизводимым в тестах (и одинаковым на клиенте и в юнит-тестах).
]=]

export type Rng = { state: number }

local Rng = {}

function Rng.new(seed: number?): Rng
	return { state = (seed or 1337) % 2147483647 }
end

--- [0, 1)
function Rng.nextFloat(r: Rng): number
	r.state = (r.state * 1103515245 + 12345) % 2147483648
	return r.state / 2147483648
end

--- [min, max)
function Rng.nextRange(r: Rng, min: number, max: number): number
	return min + (max - min) * Rng.nextFloat(r)
end

--- Случайный вектор в шаре радиуса r.
function Rng.nextInSphere(r: Rng, radius: number): { x: number, y: number, z: number }
	local u = Rng.nextFloat(r) * 2 - 1
	local theta = Rng.nextFloat(r) * math.pi * 2
	local s = math.sqrt(math.max(0, 1 - u * u))
	local m = radius * (Rng.nextFloat(r) ^ (1 / 3))
	return {
		x = m * s * math.cos(theta),
		y = m * s * math.sin(theta),
		z = m * u,
	}
end

return Rng

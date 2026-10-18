--!strict
--[=[
	Тесты векторной математики.
]=]

local T = require(script.Parent.Framework)
local Vec = require(script.Parent.Vec)

T.test("Vec.norm нормализует вектор", function()
	local n = Vec.norm(Vec.new(3, 0, 4))
	T.near(n.x, 0.6)
	T.near(n.y, 0)
	T.near(n.z, 0.8)
	T.near(Vec.len(n), 1, 1e-9)
end)

T.test("Vec.norm нулевого вектора возвращает fallback", function()
	local fallback = Vec.new(0, 0, 1)
	local n = Vec.norm(Vec.zero(), fallback)
	T.vecNear(n, fallback)
end)

T.test("Vec.clampMag ограничивает длину", function()
	local c = Vec.clampMag(Vec.new(30, 40, 0), 5)
	T.near(Vec.len(c), 5, 1e-9)
	local small = Vec.clampMag(Vec.new(1, 0, 0), 5)
	T.vecNear(small, { x = 1, y = 0, z = 0 })
end)

T.test("Vec.projectOnPlane убирает компоненту по нормали", function()
	local p = Vec.projectOnPlane(Vec.new(2, 5, 0), Vec.new(0, 1, 0))
	T.vecNear(p, { x = 2, y = 0, z = 0 })
end)

T.test("Vec.dist и Vec.dot согласованы", function()
	local a = Vec.new(1, 2, 3)
	local b = Vec.new(4, 6, 3)
	T.near(Vec.dist(a, b), 5, 1e-9)
	T.near(Vec.dot(Vec.new(1, 0, 0), Vec.new(0, 1, 0)), 0)
end)

T.test("Vec.lerp интерполирует", function()
	local p = Vec.lerp(Vec.new(0, 0, 0), Vec.new(10, 20, 30), 0.5)
	T.vecNear(p, { x = 5, y = 10, z = 15 })
end)

T.test("Vec.copy не даёт общих ссылок", function()
	local a = Vec.new(1, 2, 3)
	local b = Vec.copy(a)
	b.x = 99
	T.near(a.x, 1)
end)

return T

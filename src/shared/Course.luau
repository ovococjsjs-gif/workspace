--!strict
--[=[
	Курс (трасса) — бесконечная плавно изгибающаяся лента.
	Чистый Luau: pointAt(distance) -> позиция и касательная в точке трассы.
]=]

local Vec = require(script.Parent.Vec)
local Config = require(script.Parent.Config)

export type CoursePoint = {
	pos: Vec.Vec3,
	tangent: Vec.Vec3,
	right: Vec.Vec3,
}

local Course = {}

local UP = Vec.new(0, 1, 0)

--- Точка трассы на расстоянии d вдоль курса.
function Course.pointAt(d: number): CoursePoint
	local sway = Config.course.swayAmplitude
	local period = Config.course.swayPeriod
	local k = 2 * math.pi / period

	local x = math.sin(d * k) * sway
	local dx = math.cos(d * k) * sway * k
	local pos = Vec.new(x, 0, d)
	local tangent = Vec.norm(Vec.new(dx, 0, 1))
	local right = Vec.norm(Vec.cross(tangent, UP), Vec.new(1, 0, 0))
	return { pos = pos, tangent = tangent, right = right }
end

--- Расстояние по курсу до ближайшей точки (приблизительно, по z).
--- Знак отклонения от оси трассы по горизонтали.
function Course.lateralOffset(pos: Vec.Vec3, coursePos: Vec.Vec3): number
	return pos.x - coursePos.x
end

return Course

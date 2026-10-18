--!strict
--[=[
	End-to-end проверка игрового цикла БЕЗ Roblox: гоняем настоящий Game.step()
	в интерпретаторе Luau с простым автопилотом.

	Это самая ценная проверка проекта: она прогоняет ровно тот же код, что и
	клиент в Roblox (src/shared/Game.luau), и ловит NaN, разлёт стаи,
	неработающие кольца и прочие регрессии.
]=]

local T = require(script.Parent.Framework)
local Vec = require(script.Parent.Vec)
local Game = require(script.Parent.Game)
local Flock = require(script.Parent.Flock)

local DT = 1 / 60

local Course = require(script.Parent.Course)

--- Автопилот «хорошего игрока»: держит курс по центру трассы и управляет газом
--- так, чтобы стая не отставала (как разумный человек в игре).
local function autopilot(game: Game.Game): Game.Input
	local cp0 = Course.pointAt(game.leaderPos.z)
	local err = Flock.averageSlotError(game.flock, {
		leaderPos = game.leaderPos,
		courseForward = cp0.tangent,
		courseRight = cp0.right,
		wind = Vec.zero(),
		time = game.time,
	})
	local z = 1.0
	if err > 26 then
		z = 0.35 -- притормозить, дать стае собраться
	elseif err > 14 then
		z = 0.7
	end
	local cp = Course.pointAt(game.leaderPos.z)
	local lateral = game.leaderPos.x - cp.pos.x
	-- input.x > 0 — это "вправо" (в системе курса); боковое смещение в мире — по X.
	local x = math.clamp(lateral * 0.06, -1, 1)
	local y = math.clamp((20 - game.leaderPos.y) * 0.05, -1, 1)
	return { x = x, y = y, z = z }
end

--- Прогоняет забег и возвращает статистику.
local function simulate(seconds: number, pilot: (game: Game.Game) -> Game.Input)
	local game = Game.new(20261018)
	local events = { rings = 0, perfect = 0, partial = 0, fail = 0, recovered = 0 }
	local steps = math.floor(seconds / DT)
	for _ = 1, steps do
		if game.mode ~= "playing" then
			break
		end
		local stepEvents = Game.step(game, DT, pilot(game))
		for _, event in stepEvents do
			events.rings += #event.rings
			events.recovered += event.recovered
			for _, ring in event.rings do
				if ring.result == "perfect" then
					events.perfect += 1
				elseif ring.result == "partial" then
					events.partial += 1
				else
					events.fail += 1
				end
			end
		end
	end
	return game, events
end

T.test("симуляция не даёт NaN/Inf в координатах", function()
	local game = Game.new(1)
	for _ = 1, 3600 do
		Game.step(game, DT, { x = 0.3, y = 0.1, z = 1 })
	end
	local function finite(v: number): boolean
		return v == v and v < 1e9 and v > -1e9
	end
	T.ok(finite(game.leaderPos.x) and finite(game.leaderPos.y) and finite(game.leaderPos.z), "позиция лидера должна быть конечной")
	for i = 1, #game.flock.birds do
		local bird = game.flock.birds[i]
		T.ok(
			finite(bird.pos.x) and finite(bird.pos.y) and finite(bird.pos.z),
			string.format("птица %d имеет некорректную позицию: (%s, %s, %s)", i, tostring(bird.pos.x), tostring(bird.pos.y), tostring(bird.pos.z))
		)
		T.ok(
			finite(bird.vel.x) and finite(bird.vel.y) and finite(bird.vel.z),
			string.format("птица %d имеет некорректную скорость", i)
		)
	end
end)

T.test("автопилот собирает стаю и кольца засчитываются", function()
	local game, events = simulate(90, autopilot)
	T.ok(events.rings > 0, "кольца должны засчитываться, а не игнорироваться")
	T.ok(game.score.score > 0, "счёт должен расти, получено " .. tostring(game.score.score))
	T.ok(events.perfect > 0, "хотя бы часть колец должна проходиться чисто")
	T.eq(game.mode, "playing", "с хорошим автопилотом забег не должен проигрываться")
end)

T.test("счёт и комбо растут монотонно по мере прохождения колец", function()
	local game = Game.new(7)
	local lastScore = 0
	local rings = 0
	for _ = 1, 3600 do
		local stepEvents = Game.step(game, DT, autopilot(game))
		for _, event in stepEvents do
			rings += #event.rings
		end
		T.ok(game.score.score >= lastScore, "счёт не должен уменьшаться")
		lastScore = game.score.score
		if rings >= 5 then
			break
		end
	end
	T.ok(rings >= 5, "за 60 секунд должно быть не меньше 5 колец, получено " .. tostring(rings))
end)

T.test("агрессивный пилот (метание в стороны) теряет стаю — есть условие проигрыша", function()
	local game = Game.new(3)
	local over = false
	for step = 1, 60 * 240 do
		local t = step * DT
		local wobble = math.sin(t * 5.5)
		local events = Game.step(game, DT, { x = wobble, y = math.sin(t * 3.1), z = 1 })
		for _, event in events do
			if event.gameOver then
				over = true
			end
		end
		if over then
			break
		end
	end
	T.ok(over, "условие проигрыша должно срабатывать, когда стая рассыпалась")
	T.eq(game.mode, "over")
end)

T.test("окно кольца: после пересечения лидером стая должна успеть", function()
	local game = Game.new(5)
	local sawOpenRing = false
	for _ = 1, 3600 do
		Game.step(game, DT, autopilot(game))
		if game.ringGraceLeft and game.ringGraceTotal then
			sawOpenRing = true
			T.ok(game.ringGraceLeft <= game.ringGraceTotal, "оставшееся время не может превышать полное")
			break
		end
	end
	T.ok(sawOpenRing, "после пересечения кольца должен появляться таймер окна")
end)

T.test("симуляция детерминирована", function()
	local a = Game.new(123)
	local b = Game.new(123)
	for _ = 1, 1200 do
		Game.step(a, DT, autopilot(a))
		Game.step(b, DT, autopilot(b))
	end
	T.eq(a.score.score, b.score.score)
	T.vecNear(a.leaderPos, b.leaderPos, 1e-9)
	for i = 1, #a.flock.birds do
		T.vecNear(a.flock.birds[i].pos, b.flock.birds[i].pos, 1e-9, string.format("птица %d", i))
	end
end)

T.test("стая не улетает за пределы разумного (нет «взрыва» координат)", function()
	local game = Game.new(11)
	for _ = 1, 3600 do
		Game.step(game, DT, { x = 0, y = 0, z = 1 })
	end
	for i = 1, #game.flock.birds do
		local bird = game.flock.birds[i]
		T.ok(Vec.len(bird.vel) < 200, string.format("птица %d разогналась: |v|=%s", i, tostring(Vec.len(bird.vel))))
		T.ok(bird.pos.z < game.leaderPos.z + 200, "птица не должна обгонять лидера сильно")
		T.ok(bird.pos.y < 300, "птица не должна улетать в космос")
		T.ok(bird.pos.y > -50, "птица не должна проваливаться")
	end
end)

return T

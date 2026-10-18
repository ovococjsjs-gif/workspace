--!strict
--[=[
	Тесты рейтинга гонки: сортировка, места, поиск позиции игрока.
]=]

local T = require(script.Parent.Framework)
local Race = require(script.Parent.Race)

local function entry(userId: number, name: string, score: number, distance: number, finished: boolean, alive: number?): Race.Entry
	return {
		userId = userId,
		name = name,
		score = score,
		distance = distance,
		alive = alive or 18,
		finished = finished,
		place = nil,
	}
end

T.test("рейтинг сортируется по очкам, финишировавшие выше", function()
	local entries = {
		entry(1, "Аня", 100, 500, false),
		entry(2, "Борис", 300, 900, true),
		entry(3, "Вера", 200, 700, false),
	}
	local sorted = Race.sort(entries)
	T.eq(sorted[1].name, "Борис", "финишировавший первый")
	T.eq(sorted[2].name, "Вера", "второй по очкам")
	T.eq(sorted[3].name, "Аня", "третий по очкам")
end)

T.test("при равных очках выше тот, кто дальше улетел", function()
	local sorted = Race.sort({
		entry(1, "Аня", 200, 400, false),
		entry(2, "Борис", 200, 900, false),
	})
	T.eq(sorted[1].name, "Борис")
end)

T.test("места присваиваются по порядку финиша", function()
	local entries = {
		entry(1, "Аня", 100, 500, false),
		entry(2, "Борис", 300, 900, true),
		entry(3, "Вера", 250, 800, true),
	}
	local sorted = Race.assignPlaces(entries)
	T.eq(sorted[1].name, "Борис", "первый финишировал — первое место")
	T.eq(sorted[1].place, 1)
	T.eq(sorted[2].name, "Вера", "вторая финишировала — второе место")
	T.eq(sorted[2].place, 2)
	T.eq(sorted[3].place, nil, "не финишировал — места пока нет")
	T.eq(Race.placeOf(entries, 2), 1)
	T.eq(Race.placeOf(entries, 1), nil)
end)

T.test("позиция игрока в рейтинге считается среди всех", function()
	local entries = {
		entry(1, "Аня", 100, 500, false),
		entry(2, "Борис", 300, 900, false),
		entry(3, "Вера", 200, 700, false),
	}
	T.eq(Race.rankOf(entries, 2), 1)
	T.eq(Race.rankOf(entries, 3), 2)
	T.eq(Race.rankOf(entries, 1), 3)
	T.eq(Race.rankOf(entries, 99), nil, "чужого игрока в рейтинге нет")
end)

T.test("подпись строки рейтинга читаема", function()
	local text = Race.formatEntry(entry(1, "Аня", 12400, 900, true, 18), 1)
	T.ok(string.find(text, "Аня") ~= nil, "имя в подписи")
	T.ok(string.find(text, "12400") ~= nil, "счёт в подписи")
end)

return T

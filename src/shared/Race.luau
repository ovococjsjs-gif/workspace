--!strict
--[=[
	Гонка: общий забег для нескольких игроков на одном сервере.
	Чистая логика (без Roblox-API), чтобы её можно было покрыть юнит-тестами.

	Сервер генерирует сид раунда и рассылает его всем: одинаковый сид — 
	одинаковый курс (кольца, камни, раскладка стаи), поэтому результаты
	сравнимы. Каждый клиент считает свой забег сам, но сервер принимает
	только правдоподобный счёт (Score.isPlausible) и собирает рейтинг.
]=]

export type Entry = {
	--- UserId игрока (устойчивый ключ, в отличие от имени).
	userId: number,
	name: string,
	score: number,
	--- Пройденное расстояние вдоль трассы (для сравнения «кто дальше»).
	distance: number,
	--- Сколько птиц осталось в строю.
	alive: number,
	--- Финишировал ли игрок (забег окончен).
	finished: boolean,
	--- Итоговое место (задаётся в порядке финиша).
	place: number?,
	--- Последняя известная позиция вожака (для «призраков» соперников).
	pos: { x: number, y: number, z: number }?,
}

local Race = {}

--- Сортировка рейтинга: больше очков — выше; при равенстве — кто дальше улетел.
--- Готовые (финишировавшие) всегда выше тех, кто ещё в забеге.
function Race.sort(entries: { Entry }): { Entry }
	local copy: { Entry } = {}
	for i, entry in entries do
		copy[i] = entry
	end
	table.sort(copy, function(a: Entry, b: Entry): boolean
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.distance > b.distance
	end)
	return copy
end

--- Присвоение мест: финишировавшие получают места по порядку финиша,
--- остальные — места по текущему рейтингу (но без «настоящего» места).
function Race.assignPlaces(entries: { Entry }): { Entry }
	local sorted = Race.sort(entries)
	local place = 0
	for _, entry in sorted do
		if entry.finished then
			place += 1
			entry.place = place
		else
			entry.place = nil
		end
	end
	return sorted
end

--- Итоговое место игрока (nil, если он ещё не финишировал).
function Race.placeOf(entries: { Entry }, userId: number): number?
	for _, entry in entries do
		if entry.userId == userId then
			return entry.place
		end
	end
	return nil
end

--- Позиция в рейтинге (1 — первое место среди всех, включая ещё не финишировавших).
function Race.rankOf(entries: { Entry }, userId: number): number?
	local sorted = Race.sort(entries)
	for i, entry in sorted do
		if entry.userId == userId then
			return i
		end
	end
	return nil
end

--- Короткая подпись для HUD: "1. Маша — 12 400".
function Race.formatEntry(entry: Entry, rank: number): string
	local place = if entry.place then tostring(entry.place) else tostring(rank)
	return string.format("%s. %s — %d", place, entry.name, entry.score)
end

return Race

--!strict
--[=[
	«Забег дня» — ежедневное задание с общим курсом и таблицей лидеров.

	Сид забега дня выводится из даты (UTC), поэтому в течение суток у всех
	игроков **один и тот же курс**, а результаты можно сравнивать между собой.
]=]

export type BoardEntry = {
	userId: number,
	name: string,
	score: number,
}

local Daily = {}

--- Ключ дня в формате "ГГГГММДД" (UTC).
function Daily.todayKey(): string
	return os.date("!%Y%m%d")
end

--- Сид забега дня из ключа дня. Один и тот же день → один и тот же сид.
function Daily.seedFor(key: string): number
	local hash = 2166136261
	for i = 1, #key do
		local code = string.byte(key, i) or 0
		hash = (hash * 31 + code) % 4294967296
	end
	-- Диапазон, пригодный для Game.new (любое целое).
	return hash % 100000000 + 1
end

--- Сид сегодняшнего забега.
function Daily.seedToday(): number
	return Daily.seedFor(Daily.todayKey())
end

--- Сортировка таблицы лидеров: больше очков — выше.
function Daily.sortBoard(entries: { BoardEntry }): { BoardEntry }
	local copy: { BoardEntry } = {}
	for i, entry in entries do
		copy[i] = entry
	end
	table.sort(copy, function(a: BoardEntry, b: BoardEntry): boolean
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	return copy
end

--- Лучший результат игрока в таблице (nil, если его нет).
function Daily.bestOf(entries: { BoardEntry }, userId: number): number?
	for _, entry in entries do
		if entry.userId == userId then
			return entry.score
		end
	end
	return nil
end

--- Есть ли в таблице результат лучше указанного.
function Daily.beats(entries: { BoardEntry }, userId: number, score: number): boolean
	local best = Daily.bestOf(entries, userId)
	return best == nil or score > best
end

--- Красивая строка таблицы: "1. Аня — 24 300".
function Daily.formatEntry(entry: BoardEntry, rank: number): string
	return string.format("%d. %s — %d", rank, tostring(entry.name), entry.score)
end

return Daily

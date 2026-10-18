--!strict
--[=[
	Тесты «забега дня»: сид по дате, таблица лидеров.
]=]

local T = require(script.Parent.Framework)
local Daily = require(script.Parent.Daily)

T.test("сид забега дня одинаков для одного дня и разный для разных", function()
	local a = Daily.seedFor("20261018")
	local b = Daily.seedFor("20261018")
	local c = Daily.seedFor("20261019")
	T.eq(a, b, "одинаковый день — одинаковый сид")
	T.ok(a ~= c, "разные дни — разные сиды")
	T.ok(a > 0 and a < 100000001, "сид в допустимом диапазоне: " .. tostring(a))
end)

T.test("ключ дня имеет формат ГГГГММДД", function()
	local key = Daily.todayKey()
	T.eq(#key, 8, "8 символов: " .. tostring(key))
	T.ok(string.match(key, "^%d%d%d%d%d%d%d%d$") ~= nil, "только цифры: " .. tostring(key))
end)

T.test("таблица лидеров сортируется по очкам", function()
	local board = Daily.sortBoard({
		{ userId = 1, name = "Аня", score = 100 },
		{ userId = 2, name = "Борис", score = 900 },
		{ userId = 3, name = "Вера", score = 500 },
	})
	T.eq(board[1].name, "Борис")
	T.eq(board[2].name, "Вера")
	T.eq(board[3].name, "Аня")
end)

T.test("результат игрока в таблице и его улучшение", function()
	local board = {
		{ userId = 1, name = "Аня", score = 100 },
		{ userId = 2, name = "Борис", score = 900 },
	}
	T.eq(Daily.bestOf(board, 1), 100)
	T.eq(Daily.bestOf(board, 99), nil, "чужого игрока нет")
	T.eq(Daily.beats(board, 1, 200), true, "200 лучше 100")
	T.eq(Daily.beats(board, 1, 50), false, "50 хуже 100")
	T.eq(Daily.beats(board, 99, 10), true, "нового игрока можно улучшить")
end)

T.test("строка таблицы читаема", function()
	local text = Daily.formatEntry({ userId = 1, name = "Аня", score = 24300 }, 1)
	T.ok(string.find(text, "Аня") ~= nil, "имя в строке")
	T.ok(string.find(text, "24300") ~= nil, "счёт в строке")
end)

return T

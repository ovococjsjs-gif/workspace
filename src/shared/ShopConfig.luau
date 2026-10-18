--!strict
--[=[
	Конфигурация магазина (Robux).

	ВАЖНО: идентификаторы покупок (game pass'ов и developer product'ов) —
	ПЛЕЙСХОЛДЕРЫ, равные нулю. Реальные ID создаются в Roblox Creator Dashboard
	(Store -> Game Passes / Developer Products) и вписываются сюда. Пока ID = 0,
	сервер не открывает окно покупки, а честно отвечает клиенту, что магазин
	ещё не настроен.

	Цены (Robux) — ориентировочные: реальная цена задаётся в Creator Dashboard,
	здесь она нужна только для подписи в интерфейсе.
]=]

export type ShopEntry = {
	--- Ключ перка (совпадает с ключом в src/shared/Perms.luau).
	key: string,
	--- Название в интерфейсе.
	title: string,
	--- Короткое описание эффекта.
	desc: string,
	--- Ориентировочная цена в Robux (для подписи в интерфейсе).
	price: number,
	--- Это повторяемая покупка (developer product), а не game pass.
	repeatable: boolean,
}

export type ShopConfig = {
	--- Game pass'ы: key -> ID (0 = не настроено).
	passes: { [string]: number },
	--- Developer product'ы: key -> ID (0 = не настроено).
	products: { [string]: number },
	--- Товары для интерфейса.
	items: { ShopEntry },
}

local ShopConfig: ShopConfig = {
	passes = {
		goldenBoost = 0,
		windproof = 0,
		fastStart = 0,
		magnetPlus = 0,
		calm = 0,
	},
	products = {
		boostPack = 0,
	},
	items = {
		{
			key = "goldenBoost",
			title = "ЗОЛОТОЙ РЫВОК",
			desc = "Перезарядка рывка вдвое короче",
			price = 49,
			repeatable = false,
		},
		{
			key = "windproof",
			title = "ВЕТРОКРОМ",
			desc = "Ветер больше не сносит вожаку и стаю",
			price = 79,
			repeatable = false,
		},
		{
			key = "fastStart",
			title = "ФОРСАЖ",
			desc = "Забег начинается с комбо x2",
			price = 99,
			repeatable = false,
		},
		{
			key = "magnetPlus",
			title = "МАГНИТ+",
			desc = "Радиус подбора потерянных птиц в полтора раза больше",
			price = 59,
			repeatable = false,
		},
		{
			key = "calm",
			title = "ХОЗЯЙКА",
			desc = "Стая нервничает заметно меньше: меньше потерь",
			price = 89,
			repeatable = false,
		},
		{
			key = "boostPack",
			title = "ЗАРЯДЫ РЫВКА x3",
			desc = "Три мгновенных рывка (можно покупать снова)",
			price = 25,
			repeatable = true,
		},
	},
}

--- Товар по ключу (nil, если ключа нет).
function ShopConfig.item(key: string): ShopEntry?
	for _, entry in ShopConfig.items do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

--- ID покупки по ключу (nil, если ключа нет или он не настроен).
function ShopConfig.idFor(key: string): number?
	local passId = ShopConfig.passes[key]
	if passId and passId ~= 0 then
		return passId
	end
	local productId = ShopConfig.products[key]
	if productId and productId ~= 0 then
		return productId
	end
	return nil
end

return ShopConfig

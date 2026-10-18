--!strict
--[=[
	Тесты конфигурации магазина: товары, цены, идентификаторы покупок.
]=]

local T = require(script.Parent.Framework)
local ShopConfig = require(script.Parent.ShopConfig)

T.test("в магазине шесть товаров с описанием и ценой", function()
	T.eq(#ShopConfig.items, 6, "товаров: 6")
	for _, item in ShopConfig.items do
		T.ok(type(item.key) == "string" and item.key ~= "", "у товара есть ключ")
		T.ok(type(item.title) == "string" and item.title ~= "", "у товара есть название")
		T.ok(type(item.desc) == "string" and item.desc ~= "", "у товара есть описание")
		T.ok(item.price > 0, "у товара есть цена: " .. tostring(item.key))
	end
end)

T.test("товар находится по ключу", function()
	local item = ShopConfig.item("goldenBoost")
	T.ok(item ~= nil, "товар найден")
	T.eq(item and item.key, "goldenBoost")
	T.eq(ShopConfig.item("нет-такого"), nil, "неизвестного товара нет")
end)

T.test("не настроенные ID (0) считаются отсутствующими", function()
	ShopConfig.passes.goldenBoost = 0
	T.eq(ShopConfig.idFor("goldenBoost"), nil, "нулевой ID — покупка не настроена")
	ShopConfig.passes.goldenBoost = 4242
	T.eq(ShopConfig.idFor("goldenBoost"), 4242, "ID читается после настройки")
	ShopConfig.passes.goldenBoost = 0
end)

T.test("повторяемая покупка помечена флагом repeatable", function()
	local pack = ShopConfig.item("boostPack")
	T.ok(pack ~= nil, "набор зарядов есть")
	T.eq(pack and pack.repeatable, true, "заряды можно покупать снова")
	local pass = ShopConfig.item("windproof")
	T.eq(pass and pass.repeatable, false, "game pass покупается один раз")
end)

return T

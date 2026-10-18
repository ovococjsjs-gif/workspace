--!strict
--[=[
	Тесты перков (покупок за Robux): как они влияют на игру.
]=]

local T = require(script.Parent.Framework)
local Perms = require(script.Parent.Perms)

T.test("пустые перки ничего не меняют", function()
	local perms = Perms.new()
	T.eq(perms.goldenBoost, false)
	T.eq(Perms.boostCooldown(perms, 4.3), 4.3, "перезарядка без перка")
	T.eq(Perms.windFactor(perms), 1, "ветер дует как обычно")
	T.eq(Perms.startCombo(perms), 1, "комбо начинается с единицы")
	T.eq(Perms.hasBoostCharge(perms), false)
end)

T.test("«золотой рывок» укорачивает перезарядку вдвое", function()
	local perms = Perms.new()
	perms.goldenBoost = true
	T.eq(Perms.boostCooldown(perms, 4.3), 2.15)
end)

T.test("«ветрокром» гасит ветер", function()
	local perms = Perms.new()
	perms.windproof = true
	T.eq(Perms.windFactor(perms), 0)
end)

T.test("«форсаж» даёт стартовое комбо ×2", function()
	local perms = Perms.new()
	perms.fastStart = true
	T.eq(Perms.startCombo(perms), 2)
end)

T.test("заряды мгновенного рывка считаются и тратятся", function()
	local perms = Perms.fromTable({ boostCharges = 3 })
	T.eq(perms.boostCharges, 3)
	T.eq(Perms.hasBoostCharge(perms), true)
	perms.boostCharges -= 1
	T.eq(perms.boostCharges, 2)
end)

T.test("мусор от сервера не ломает перки", function()
	local perms = Perms.fromTable({ goldenBoost = "да", boostCharges = "много" })
	T.eq(perms.goldenBoost, false, "не-булево игнорируется")
	T.eq(perms.boostCharges, 0, "не-число игнорируется")
	local empty = Perms.fromTable(nil)
	T.eq(empty.goldenBoost, false)
end)

return T

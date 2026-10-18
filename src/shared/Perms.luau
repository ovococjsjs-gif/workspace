--!strict
--[=[
	Перки игрока (покупки за Robux) — чистая логика без Roblox-API.

	Покупки обрабатывает сервер (MarketplaceService) и присылает клиенту
	список перков; здесь описано, как каждый перк влияет на игру.
]=]

export type Perms = {
	--- «Золотой рывок»: перезарядка рывка вдвое короче.
	goldenBoost: boolean,
	--- «Ветрокром»: ветер не сносит вожака и стаю.
	windproof: boolean,
	--- «Форсаж»: забег начинается с двойного комбо.
	fastStart: boolean,
	--- Заряды «мгновенного рывка» (developer product, можно покупать повторно).
	boostCharges: number,
}

local Perms = {}

function Perms.new(): Perms
	return {
		goldenBoost = false,
		windproof = false,
		fastStart = false,
		boostCharges = 0,
	}
end

--- Перки из «сырой» таблицы (ответ сервера) — с защитой от мусора.
function Perms.fromTable(data: any): Perms
	local perms = Perms.new()
	if type(data) ~= "table" then
		return perms
	end
	perms.goldenBoost = data.goldenBoost == true
	perms.windproof = data.windproof == true
	perms.fastStart = data.fastStart == true
	if type(data.boostCharges) == "number" then
		perms.boostCharges = math.max(0, math.floor(data.boostCharges))
	end
	return perms
end

--- Перезарядка рывка с учётом перка.
function Perms.boostCooldown(perms: Perms, base: number): number
	if perms.goldenBoost then
		return base * 0.5
	end
	return base
end

--- Множитель силы ветра: «Ветрокром» полностью гасит ветер.
function Perms.windFactor(perms: Perms): number
	if perms.windproof then
		return 0
	end
	return 1
end

--- Комбо на старте забега.
function Perms.startCombo(perms: Perms): number
	if perms.fastStart then
		return 2
	end
	return 1
end

--- Есть ли заряды мгновенного рывка.
function Perms.hasBoostCharge(perms: Perms): boolean
	return perms.boostCharges > 0
end

return Perms

--!strict
--[=[
	Точка входа юнит-тестов.
	Запуск: luau run.luau   (из каталога песочницы, см. tools/run_tests.sh)
]=]

local T = require(script.Parent.Framework)

require(script.Parent.test_vec)
require(script.Parent.test_flock)
require(script.Parent.test_rings)
require(script.Parent.test_difficulty)
require(script.Parent.test_simulation)
require(script.Parent.test_race)
require(script.Parent.test_perms)
require(script.Parent.test_shop)

local _, failed = T.run()

if failed > 0 then
	error(string.format("Провалено тестов: %d", failed), 0)
end

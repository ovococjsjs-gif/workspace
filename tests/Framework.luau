--!strict
--[=[
	Минимальный тест-фреймворк для чистых Luau-модулей.
	Работает в обычном интерпретаторе Luau (не в Roblox) — см. tools/run_tests.sh.
]=]

export type TestCase = { name: string, fn: () -> () }

local T = {}

T.tests = {} :: { TestCase }

function T.test(name: string, fn: () -> ()): ()
	table.insert(T.tests, { name = name, fn = fn })
end

function T.fail(message: string): ()
	error(message, 3)
end

function T.ok(value: any, message: string?): ()
	if not value then
		error(message or "ожидалось truthy значение", 2)
	end
end

function T.eq(actual: any, expected: any, message: string?): ()
	if actual ~= expected then
		error(
			string.format("%s: получено %s, ожидалось %s", message or "значения не равны", tostring(actual), tostring(expected)),
			2
		)
	end
end

function T.near(actual: number, expected: number, epsilon: number?, message: string?): ()
	local eps = epsilon or 1e-6
	if math.abs(actual - expected) > eps then
		error(
			string.format("%s: получено %s, ожидалось ~%s (±%s)", message or "числа не близки", tostring(actual), tostring(expected), tostring(eps)),
			2
		)
	end
end

function T.vecNear(actual: { x: number, y: number, z: number }, expected: { x: number, y: number, z: number }, epsilon: number?, message: string?): ()
	local eps = epsilon or 1e-6
	local dx = actual.x - expected.x
	local dy = actual.y - expected.y
	local dz = actual.z - expected.z
	if math.sqrt(dx * dx + dy * dy + dz * dz) > eps then
		error(
			string.format(
				"%s: получено (%s, %s, %s), ожидалось (%s, %s, %s)",
				message or "векторы не близки",
				tostring(actual.x),
				tostring(actual.y),
				tostring(actual.z),
				tostring(expected.x),
				tostring(expected.y),
				tostring(expected.z)
			),
			2
		)
	end
end

--- Запуск всех зарегистрированных тестов. Возвращает (passed, failed).
function T.run(): (number, number)
	local passed, failed = 0, 0
	local failures: { string } = {}
	for _, case in T.tests do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
			print(string.format("  ok   %s", case.name))
		else
			failed += 1
			local message = if type(err) == "string" then err else tostring(err)
			table.insert(failures, string.format("%s: %s", case.name, message))
			print(string.format("  FAIL %s\n       %s", case.name, message))
		end
	end
	print("")
	if failed == 0 then
		print(string.format("TESTS PASSED: %d/%d", passed, passed))
	else
		print(string.format("TESTS FAILED: %d passed, %d failed", passed, failed))
		for _, f in failures do
			print("  - " .. f)
		end
	end
	return passed, failed
end

return T

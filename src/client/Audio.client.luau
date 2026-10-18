--[=[
	Звук: используются встроенные в движок ассеты rbxasset://sounds/*.
	Их не нужно загружать в Studio, и если конкретного файла нет — звук просто не проиграется.
	Всё обёрнуто в pcall: игра не должна падать из-за звука.
]=]

local Audio = {}

local SOUND = {
	ring = "rbxasset://sounds/electronicpingshort.wav",
	perfect = "rbxasset://sounds/action_jump.wav",
	fail = "rbxasset://sounds/impact_water.mp3",
	recover = "rbxasset://sounds/switch.wav",
	ui = "rbxasset://sounds/button.wav",
}

local function play(soundId: string, volume: number, pitch: number?)
	local ok, sound = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = soundId
		s.Volume = volume
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMaxDistance = 120
		s.Parent = game:GetService("SoundService")
		return s
	end)
	if not ok or not sound then
		return
	end
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	sound:Play()
	task.delay(3, function()
		if sound and sound.Parent then
			sound:Destroy()
		end
	end)
end

function Audio.ring(combo: number)
	play(SOUND.ring, 0.35, 0.9 + (combo - 1) * 0.12)
end

function Audio.perfect(combo: number)
	play(SOUND.perfect, 0.4, 1.0 + (combo - 1) * 0.1)
end

function Audio.fail()
	play(SOUND.fail, 0.4, 0.8)
end

function Audio.recover()
	play(SOUND.recover, 0.3, 1.2)
end

function Audio.ui()
	play(SOUND.ui, 0.3, 1.0)
end

return Audio

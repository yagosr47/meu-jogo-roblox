--!strict
-- Efeitos do monstro: música de tensão, batimento, vinheta e jumpscare.
--
-- 100% cosmético. Quem decide se o monstro viu/pegou o jogador é o servidor;
-- este script só reage ao que chega por RemoteEvent.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local Remotes = require(shared.Remotes)

local HudKit = require(script.Parent.HudKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

-- ----------------------------------------------------------------------
-- Sons procedurais (sem depender de asset externo)
-- ----------------------------------------------------------------------
-- Os "stings" usam os sons locais que acompanham o cliente do Roblox.
-- Se algum não existir na versão do cliente, o pcall simplesmente ignora.

local function makeSound(id: string, volume: number, looped: boolean, parent: Instance): Sound?
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = parent

	local ok = pcall(function()
		sound:Play()
	end)

	if not ok then
		sound:Destroy()
		return nil
	end

	return sound
end

local chaseSound: Sound? = nil
local warnedDanger = false

local function startChaseAudio()
	if chaseSound then
		return
	end

	-- Som grave e repetitivo, tipo batida de coração + drone.
	chaseSound = makeSound("rbxasset://sounds/impact_water.mp3", 0.12, true, Workspace.CurrentCamera)
	if chaseSound then
		chaseSound.PlaybackSpeed = 0.35
	end
end

local function stopChaseAudio()
	if chaseSound then
		chaseSound:Destroy()
		chaseSound = nil
	end
end

-- ----------------------------------------------------------------------
-- Vinheta (escurece as bordas) quando o monstro está perto
-- ----------------------------------------------------------------------

local screenGui = HudKit.screenGui("MonsterFx", playerGui, 4)

local vignette = HudKit.create("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, screenGui) :: Frame

local vignetteGradient = HudKit.create("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.62, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	}),
}, vignette)

-- ----------------------------------------------------------------------
-- Tela de jumpscare
-- ----------------------------------------------------------------------

local jumpscare = HudKit.create("Frame", {
	Name = "Jumpscare",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 50,
	Visible = false,
}, screenGui) :: Frame

local scareFace = HudKit.label({
	Name = "Face",
	Text = "☠",
	Font = Enum.Font.GothamBlack,
	TextSize = 260,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	TextTransparency = 0,
	ZIndex = 51,
}, jumpscare)

local scareText = HudKit.label({
	Name = "Caption",
	Text = "VOCÊ FOI PEGO",
	Font = Enum.Font.GothamBlack,
	TextSize = 34,
	TextColor3 = Color3.fromRGB(255, 60, 60),
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0.72, 0),
	ZIndex = 52,
}, jumpscare)

local function playJumpscare(monsterName: string)
	jumpscare.Visible = true
	scareText.Text = "VOCÊ FOI PEGO"
	jumpscare.BackgroundTransparency = 0.15
	scareFace.TextSize = 260

	-- Tremida + zoom do "rosto".
	local start = os.clock()
	local shakeConnection: RBXScriptConnection

	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		if elapsed > 1.6 then
			shakeConnection:Disconnect()
			return
		end

		local camera = Workspace.CurrentCamera
		local intensity = math.max(0, 0.35 * (1 - elapsed / 1.6))
		camera.CFrame = camera.CFrame
			* CFrame.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * intensity * 0.4)

		scareFace.TextSize = 260 + math.floor(math.sin(elapsed * 40) * 24)
		scareFace.TextColor3 = Color3.fromRGB(255, math.random(0, 60), math.random(0, 60))
	end)

	makeSound("rbxasset://sounds/uuhhh.mp3", 0.9, false, Workspace.CurrentCamera)

	task.delay(2.4, function()
		TweenService:Create(jumpscare, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.delay(0.7, function()
			jumpscare.Visible = false
		end)
	end)
end

-- ----------------------------------------------------------------------
-- Estado do monstro
-- ----------------------------------------------------------------------

local monsterMode = "Patrol"
local lastMonsterPosition: Vector3? = nil
local lastMonsterAt = 0

-- Um ÚNICO handler para o estado do monstro: antes havia dois conectados ao
-- mesmo evento, cada um sobrescrevendo metade do estado.
remotes[Remotes.SERVER_TO_CLIENT.MONSTER_STATE].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	lastMonsterAt = os.clock()

	local newMode = payload.mode
	if newMode == "Chase" or newMode == "Patrol" then
		local wasChasing = monsterMode == "Chase"
		monsterMode = newMode

		if monsterMode == "Chase" and not wasChasing then
			startChaseAudio()
			warnedDanger = true
		elseif monsterMode == "Patrol" and wasChasing then
			stopChaseAudio()
			warnedDanger = false
		end
	end

	local pos = payload.position
	if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" and type(pos[3]) == "number" then
		lastMonsterPosition = Vector3.new(pos[1], pos[2], pos[3])
	end
end)

remotes[Remotes.SERVER_TO_CLIENT.CAUGHT].OnClientEvent:Connect(function(payload: any)
	local name = if type(payload) == "table" and type(payload.monster) == "string" then payload.monster else "Algo"
	stopChaseAudio()
	monsterMode = "Patrol"
	playJumpscare(name)
end)

-- ----------------------------------------------------------------------
-- Vinheta reativa à distância do monstro (só leitura do estado replicado)
-- ----------------------------------------------------------------------

local vignetteTarget = 1

RunService.RenderStepped:Connect(function(dt)
	local target = 1

	-- Se o servidor parou de mandar estado (monstro morto/erro), relaxa.
	if (os.clock() - lastMonsterAt) < 3 then
		if monsterMode == "Chase" then
			target = 0.7
		end
	end

	if lastMonsterPosition then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - lastMonsterPosition).Magnitude
			local ratio = math.clamp(distance / Config.MONSTER_VIEW_DISTANCE, 0, 1)

			-- Perto: vinheta escura. Perseguindo, um mínimo sempre presente.
			local proximity = 0.28 + ratio * 0.62
			if monsterMode == "Chase" then
				proximity = math.min(proximity, 0.35)
			end
			target = math.min(target, proximity)
		end
	end

	vignetteTarget += (target - vignetteTarget) * math.min(1, dt * 3)
	vignette.BackgroundTransparency = vignetteTarget
end)

-- Pings de áudio de outros jogadores (passos/pânico) — o servidor repassa.
remotes[Remotes.SERVER_TO_CLIENT.MONSTER_NEAR].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or payload.player == player.Name then
		return
	end

	-- Um "eco" curto de passada; volume baixo para não poluir.
	makeSound("rbxasset://sounds/swoosh.mp3", 0.08, false, Workspace.CurrentCamera)
end)

print("[MonsterFx] Música de tensão e jumpscare prontos.")

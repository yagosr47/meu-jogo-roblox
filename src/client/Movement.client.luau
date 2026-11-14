--!strict
-- Primeira pessoa + view bobbing + sprint (Shift) + barra de estamina
-- + respiração ofegante quando cansado.
--
-- O cliente aqui NÃO decide nada sobre estamina: ele declara "estou
-- correndo" (o servidor valida e aplica a velocidade) e desenha o que o
-- servidor replicou.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local Remotes = require(shared.Remotes)
local SprintIntent = require(shared.SprintIntent)

local HudKit = require(script.Parent.HudKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

player.CameraMode = Enum.CameraMode.LockFirstPerson

pcall(function()
	StarterGui:SetCore("TopbarEnabled", false)
end)

local camera = Workspace.CurrentCamera

-- ----------------------------------------------------------------------
-- View bobbing
-- ----------------------------------------------------------------------

local bobPhase = 0
local bobAmount = 0
local baseFov = camera.FieldOfView
local smoothedTilt = 0

-- IMPORTANTE: NÃO dá para aplicar o offset e deixar acumular no CFrame da
-- câmera (o offset compõe a cada frame e a câmera "afunda"). Guardamos o que
-- foi aplicado no frame anterior e desfazemos antes de aplicar o novo.
local appliedOffset = Vector3.zero
local appliedTilt = 0

local function restoreCamera()
	if appliedOffset.Magnitude > 0 or appliedTilt ~= 0 then
		camera.CFrame = camera.CFrame * CFrame.new(-appliedOffset) * CFrame.Angles(0, 0, -appliedTilt)
		appliedOffset = Vector3.zero
		appliedTilt = 0
	end
end

local function updateBobbing(dt: number)
	restoreCamera()

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local moving = false
	local sprinting = false

	if humanoid and humanoid.Health > 0 then
		moving = humanoid.MoveDirection.Magnitude > 0.1
		sprinting = humanoid:GetAttribute("Sprinting") == true
	end

	-- A fase avança com a velocidade: andar devagar balança menos.
	if moving then
		bobPhase += dt * Config.VIEW_BOB_SPEED
		bobAmount = math.min(1, bobAmount + dt * 5)
	else
		bobAmount = math.max(0, bobAmount - dt * 5)
	end

	-- FOV: sempre caminha para o alvo (mesmo parado), sem travar.
	local targetFov = baseFov + (if sprinting and moving then 6 else 0)
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * Config.VIEW_BOB_SMOOTHING)

	if bobAmount <= 0.001 then
		return
	end

	local vertical = math.sin(bobPhase * 2) * Config.VIEW_BOB_VERTICAL * bobAmount
	local horizontal = math.sin(bobPhase) * Config.VIEW_BOB_HORIZONTAL * bobAmount
	local tilt = math.sin(bobPhase) * math.rad(Config.VIEW_BOB_TILT) * bobAmount

	smoothedTilt += (tilt - smoothedTilt) * math.min(1, dt * Config.VIEW_BOB_SMOOTHING)

	appliedOffset = Vector3.new(horizontal, vertical, 0)
	appliedTilt = smoothedTilt

	camera.CFrame = camera.CFrame * CFrame.new(appliedOffset) * CFrame.Angles(0, 0, appliedTilt)
end

-- ----------------------------------------------------------------------
-- HUD: estamina
-- ----------------------------------------------------------------------

local screenGui = HudKit.screenGui("TerrorHud", playerGui, 5)

local staminaPanel = HudKit.panel({
	Name = "StaminaPanel",
	Size = UDim2.new(0, 220, 0, 46),
	Position = UDim2.new(0, 22, 1, -78),
}, screenGui)

HudKit.label({
	Name = "Caption",
	Text = "ESTAMINA",
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color3.fromRGB(150, 158, 172),
	Size = UDim2.new(1, -20, 0, 12),
	Position = UDim2.new(0, 10, 0, 6),
}, staminaPanel)

local _, staminaFill = HudKit.bar({
	Name = "StaminaBar",
	Size = UDim2.new(1, -20, 0, 12),
	Position = UDim2.new(0, 10, 0, 22),
}, staminaPanel)

HudKit.label({
	Name = "Hint",
	Text = "Shift corre · F lanterna",
	TextSize = 10,
	TextColor3 = Color3.fromRGB(120, 126, 138),
	Size = UDim2.new(1, -20, 0, 10),
	Position = UDim2.new(0, 10, 0, 34),
}, staminaPanel)

local staminaRatio = 1
local exhausted = false
local serverSprinting = false
local localSprinting = false

-- ----------------------------------------------------------------------
-- Respiração ofegante (procedural: sem asset externo)
-- ----------------------------------------------------------------------

local function makeBreathing(): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Respiração"
	sound.SoundId = "rbxasset://sounds/uuhhh.mp3" -- asset local do Roblox client
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = 0.62
	sound.Parent = Workspace.CurrentCamera

	pcall(function()
		sound:Play()
	end)

	return sound
end

local breathing: Sound? = nil
local breathingVolume = 0

local function updateBreathing(dt: number, tired: boolean)
	if not breathing then
		breathing = makeBreathing()
	end

	local sound = breathing :: Sound

	-- Alvo: 0 quando descansado, quase 1 quando exausto.
	local target = 0
	if tired then
		target = 0.55 + (1 - staminaRatio) * 0.45
	end

	breathingVolume += (target - breathingVolume) * math.min(1, dt * 3)
	sound.Volume = math.clamp(breathingVolume * 0.8, 0, 0.8)
	sound.PlaybackSpeed = 0.58 + (1 - staminaRatio) * 0.35

	if sound.Volume <= 0.01 and sound.IsPlaying then
		pcall(function()
			sound:Pause()
		end)
	elseif sound.Volume > 0.01 and not sound.IsPlaying then
		pcall(function()
			sound:Resume()
		end)
	end
end

-- ----------------------------------------------------------------------
-- Input (Shift)
-- ----------------------------------------------------------------------

-- A intenção de correr vive em `SprintIntent` (módulo puro, testável). Aqui
-- só ligamos os eventos a ela e disparamos o RemoteEvent quando ela manda.

local sprintIntent = SprintIntent.new()

--- Manda a intenção atual ao servidor.
local function pushSprint()
	remotes[Remotes.CLIENT_TO_SERVER.SET_SPRINTING]:FireServer(sprintIntent.holdingKey)
end

local function setHoldingKey(holding: boolean)
	if SprintIntent.pressKey(sprintIntent, holding, os.clock()) then
		pushSprint()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	-- Mesmo "processado" (chat/menu), registramos a tecla: perder o key-up
	-- deixaria o jogador travado em corrida.
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setHoldingKey(not processed)
	end
end)

UserInputService.InputEnded:Connect(function(input, _processed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- Key-up SEMPRE vale, mesmo com a UI em foco: é a única forma de
		-- garantir que ninguém fique preso correndo.
		setHoldingKey(false)
	end
end)

-- Perder o foco da janela solta o Shift (senão o jogador "trava" correndo).
UserInputService.WindowFocusReleased:Connect(function()
	setHoldingKey(false)
end)

-- ----------------------------------------------------------------------
-- Estado vindo do servidor
-- ----------------------------------------------------------------------

remotes[Remotes.SERVER_TO_CLIENT.STATE].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local maxStamina = tonumber(payload.maxStamina) or Config.STAMINA_MAX
	local stamina = tonumber(payload.stamina) or maxStamina

	staminaRatio = math.clamp(stamina / maxStamina, 0, 1)
	exhausted = payload.exhausted == true
	serverSprinting = payload.sprinting == true

	-- O servidor é a fonte da verdade: a máquina de estados sincroniza com
	-- ele (e arma o watchdog quando cortou a corrida sem o jogador soltar).
	SprintIntent.onServerState(sprintIntent, serverSprinting, os.clock())
end)

-- O servidor cortou a corrida (sem estamina)? Não solta a tecla: se o
-- jogador ainda estiver segurando o Shift, o watchdog reafirma a intenção
-- assim que ele puder correr de novo.
remotes[Remotes.SERVER_TO_CLIENT.RESET].OnClientEvent:Connect(function()
	SprintIntent.onReset(sprintIntent, os.clock())
end)

-- ----------------------------------------------------------------------
-- Loop visual
-- ----------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	updateBobbing(dt)

	-- Barra: interpola para não ficar "piscando".
	local targetRatio = staminaRatio
	local current = staminaFill.Size.X.Scale
	local smoothed = current + (targetRatio - current) * math.min(1, dt * 8)

	staminaFill.Size = UDim2.fromScale(math.clamp(smoothed, 0, 1), 1)
	staminaFill.BackgroundColor3 = HudKit.colorForRatio(smoothed)

	-- Vermelho piscando quando exausto.
	if exhausted then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)
		staminaFill.BackgroundColor3 = Color3.fromRGB(255, math.floor(60 + 40 * pulse), 60)
	end

	-- Watchdog: se o jogador segura o Shift e o servidor não confirmou a
	-- corrida (cortou por cansaço, ou o pacote caiu no limite de taxa),
	-- reafirma devagar. Quem decide continua sendo o servidor (`canSprint`).
	if SprintIntent.shouldResync(
		sprintIntent,
		os.clock(),
		SprintIntent.mayTry(staminaRatio * Config.STAMINA_MAX, Config.STAMINA_MAX, exhausted)
	) then
		pushSprint()
	end

	local isSprintingNow = serverSprinting or (localSprinting and not exhausted)
	staminaPanel.BackgroundTransparency = if isSprintingNow then 0.2 else 0.35

	updateBreathing(dt, exhausted or staminaRatio <= Config.STAMINA_EXHAUSTED_UNTIL / Config.STAMINA_MAX)
end)

-- Avisa o servidor no primeiro frame (garante estado sincronizado).
task.defer(function()
	pushSprint()
end)

print("[Movement] Primeira pessoa, sprint e respiração ativos.")

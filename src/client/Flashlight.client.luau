--!strict
-- Lanterna (F): desenha a SpotLight, a HUD de bateria e a piscada abaixo de
-- 20%.
--
-- A bateria verdadeira é do servidor. Aqui só interpolamos para o visual não
-- ficar "pulando" a cada 2%, e a piscada usa `FlashlightLogic.getLightState`
-- — a MESMA função do servidor, então os dois concordam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local FlashlightLogic = require(shared.FlashlightLogic)
local Remotes = require(shared.Remotes)

local HudKit = require(script.Parent.HudKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

local screenGui = HudKit.screenGui("FlashlightHud", playerGui, 6)

local panel = HudKit.panel({
	Name = "BatteryPanel",
	Size = UDim2.new(0, 170, 0, 40),
	Position = UDim2.new(1, -192, 1, -72),
}, screenGui)

HudKit.label({
	Name = "Caption",
	Text = "BATERIA",
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = Color3.fromRGB(150, 158, 172),
	Size = UDim2.new(1, -20, 0, 12),
	Position = UDim2.new(0, 10, 0, 6),
}, panel)

local _, batteryFill = HudKit.bar({
	Name = "BatteryBar",
	Size = UDim2.new(1, -20, 0, 10),
	Position = UDim2.new(0, 10, 0, 19),
}, panel)

local statusLabel = HudKit.label({
	Name = "Status",
	Text = "F · desligada",
	TextSize = 10,
	TextColor3 = Color3.fromRGB(120, 126, 138),
	Size = UDim2.new(1, -20, 0, 10),
	Position = UDim2.new(0, 10, 0, 29),
}, panel)

-- ----------------------------------------------------------------------
-- Estado replicado
-- ----------------------------------------------------------------------

local serverBattery = Config.BATTERY_MAX
local displayBattery = Config.BATTERY_MAX
local isOn = false
local lastReplicatedAt = os.clock()

remotes[Remotes.SERVER_TO_CLIENT.STATE].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	serverBattery = tonumber(payload.battery) or serverBattery
	isOn = payload.flashlightOn == true
	lastReplicatedAt = os.clock()
end)

remotes[Remotes.SERVER_TO_CLIENT.PICKUP_RESULT].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if payload.ok == true then
		serverBattery = tonumber(payload.battery) or serverBattery
		statusLabel.Text = "+" .. tostring(math.floor(tonumber(payload.gained) or 0)) .. "% de bateria"
		statusLabel.TextColor3 = Color3.fromRGB(90, 220, 120)
	elseif payload.reason == "cheia" then
		statusLabel.Text = "Bateria já está cheia"
		statusLabel.TextColor3 = Color3.fromRGB(200, 200, 120)
	end
end)

-- ----------------------------------------------------------------------
-- Luz presa na câmera
-- ----------------------------------------------------------------------

local lightHolder: Part? = nil
local spotLight: SpotLight? = nil

local function ensureLight(): (Part, SpotLight)
	if lightHolder and lightHolder.Parent and spotLight and spotLight.Parent then
		return lightHolder, spotLight
	end

	-- Um "suporte" invisível preso à câmera: assim a luz acompanha a visão
	-- em primeira pessoa sem depender do personagem.
	--
	-- IMPORTANTE: o suporte PRECISA ser grande. O Roblox faz culling das luzes
	-- pelo bounding box do Part que as contém; com um Part de 0.2 studs
	-- encostado na câmera, ele sai do frustum e a lanterna simplesmente some
	-- enquanto o jogador anda. Um Part grande e invisível mantém a luz viva.
	local holder = Instance.new("Part")
	holder.Name = "FlashlightHolder"
	holder.Size = Vector3.new(12, 12, 12)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Anchored = true
	holder.Massless = true
	holder.Parent = Workspace.CurrentCamera

	local light = Instance.new("SpotLight")
	light.Name = "Lanterna"
	light.Angle = Config.FLASHLIGHT_ANGLE
	light.Range = Config.FLASHLIGHT_RANGE
	light.Brightness = 0
	light.Color = Color3.new(Config.FLASHLIGHT_COLOR[1], Config.FLASHLIGHT_COLOR[2], Config.FLASHLIGHT_COLOR[3])
	light.Shadows = true
	-- `Front` brilha para o lado -Z local do Part — que é exatamente "para
	-- onde a câmera olha" (a câmera também olha para o próprio -Z).
	light.Face = Enum.NormalId.Front
	light.Parent = holder

	lightHolder = holder
	spotLight = light
	return holder, light
end

-- ----------------------------------------------------------------------
-- Input (F)
-- ----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		-- Manda a intenção; o servidor decide se pode.
		remotes[Remotes.CLIENT_TO_SERVER.SET_FLASHLIGHT]:FireServer(not isOn)
	end
end)

-- ----------------------------------------------------------------------
-- Loop visual
-- ----------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()

	-- Interpola a bateria para o desenho (o valor do servidor é o certo).
	local sinceUpdate = now - lastReplicatedAt
	local projected = serverBattery
	if isOn then
		projected = math.max(0, serverBattery - Config.BATTERY_DRAIN_PER_SECOND * sinceUpdate)
	end
	displayBattery += (projected - displayBattery) * math.min(1, dt * 4)

	local ratio = math.clamp(displayBattery / Config.BATTERY_MAX, 0, 1)
	batteryFill.Size = UDim2.fromScale(ratio, 1)
	batteryFill.BackgroundColor3 = HudKit.colorForRatio(ratio)

	-- Estado da luz pela MESMA função do servidor.
	local lightState = FlashlightLogic.getLightState({
		on = isOn,
		battery = displayBattery,
		lastToggleAt = 0,
	}, now)

	local holder, light = ensureLight()
	-- O SpotLight nasce na FACE frontal do Part, não no centro. Então
	-- deslocamos o suporte metade do tamanho para TRÁS (+Z na câmera), o que
	-- deixa a face frontal exatamente na posição da câmera: a luz começa nos
	-- olhos do jogador e vai para onde ele olha.
	holder.CFrame = Workspace.CurrentCamera.CFrame * CFrame.new(0, 0, holder.Size.Z / 2)
	light.Enabled = lightState.enabled
	light.Brightness = lightState.brightness

	-- HUD
	if isOn then
		if FlashlightLogic.isLow(displayBattery) then
			statusLabel.Text = "F · ligada (bateria baixa!)"
			statusLabel.TextColor3 = Color3.fromRGB(255, 180, 60)
		else
			statusLabel.Text = "F · ligada"
			statusLabel.TextColor3 = Color3.fromRGB(90, 220, 120)
		end
	elseif FlashlightLogic.isDead(displayBattery) then
		statusLabel.Text = "Sem bateria — ache uma pilha"
		statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	else
		statusLabel.Text = "F · desligada"
		statusLabel.TextColor3 = Color3.fromRGB(120, 126, 138)
	end
end)

-- Limpa a luz se o script for recarregado.
script.Destroying:Connect(function()
	if lightHolder then
		lightHolder:Destroy()
	end
end)

print("[Flashlight] Lanterna e HUD de bateria prontas.")

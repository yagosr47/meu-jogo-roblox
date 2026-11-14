--!strict
-- HUD do objetivo de fuga.
--
-- Desenha: contador de fusíveis instalados, indicador do fusível na mão, a
-- barra de 3 segundos da instalação e um aviso quando o portão abre.
--
-- O cliente NÃO decide nada: `installed`, `holding` e o tempo da barra vêm do
-- servidor. Aqui só interpolamos a barra entre um pacote e outro usando a
-- MESMA função pura (`EscapeLogic.installProgress`) que o servidor usa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local EscapeLogic = require(shared.EscapeLogic)
local Remotes = require(shared.Remotes)

local HudKit = require(script.Parent.HudKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

local screenGui = HudKit.screenGui("EscapeHud", playerGui, 7)

-- ----------------------------------------------------------------------
-- Painel do objetivo (canto superior esquerdo)
-- ----------------------------------------------------------------------
local panel = HudKit.panel({
	Name = "EscapePanel",
	Size = UDim2.new(0, 246, 0, 78),
	Position = UDim2.new(0, 18, 0, 18),
}, screenGui)

local _title = HudKit.label({
	Name = "Title",
	Text = "GERADOR CENTRAL",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(210, 215, 225),
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -24, 0, 14),
	Position = UDim2.new(0, 12, 0, 8),
}, panel)

local counter = HudKit.label({
	Name = "Counter",
	Text = `0/{Config.FUSE_COUNT}`,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(230, 190, 70),
	TextXAlignment = Enum.TextXAlignment.Right,
	Size = UDim2.new(0, 80, 0, 24),
	Position = UDim2.new(1, -92, 0, 4),
}, panel)

local _, counterFill = HudKit.bar({
	Name = "FuseBar",
	Size = UDim2.new(1, -24, 0, 8),
	Position = UDim2.new(0, 12, 0, 32),
}, panel)

local status = HudKit.label({
	Name = "Status",
	Text = "Encontre 5 fusíveis pelo mapa.",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(150, 158, 172),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	Size = UDim2.new(1, -24, 0, 26),
	Position = UDim2.new(0, 12, 0, 46),
}, panel)

-- ----------------------------------------------------------------------
-- Barra de instalação (3 segundos, centro da tela)
-- ----------------------------------------------------------------------
local installPanel = HudKit.panel({
	Name = "InstallPanel",
	Size = UDim2.new(0, 320, 0, 54),
	Position = UDim2.new(0.5, -160, 0.72, 0),
	Visible = false,
}, screenGui)

HudKit.label({
	Name = "InstallLabel",
	Text = `INSTALANDO FUSÍVEL ({Config.FUSE_INSTALL_SECONDS}s)`,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = Color3.fromRGB(200, 230, 210),
	TextXAlignment = Enum.TextXAlignment.Left,
	Size = UDim2.new(1, -24, 0, 14),
	Position = UDim2.new(0, 12, 0, 7),
}, installPanel)

local _, installFill = HudKit.bar({
	Name = "InstallBar",
	Size = UDim2.new(1, -24, 0, 14),
	Position = UDim2.new(0, 12, 0, 26),
}, installPanel)

-- ----------------------------------------------------------------------
-- Indicador do fusível na mão
-- ----------------------------------------------------------------------
local carryLabel = HudKit.label({
	Name = "CarryLabel",
	Text = "◆ FUSÍVEL NA MÃO — leve ao Gerador Central",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(255, 226, 130),
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(0, 460, 0, 22),
	Position = UDim2.new(0.5, -230, 1, -124),
	Visible = false,
}, screenGui)

-- ----------------------------------------------------------------------
-- Faixa de aviso (vitória / portão aberto)
-- ----------------------------------------------------------------------
local banner = HudKit.label({
	Name = "Banner",
	Text = "",
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	TextColor3 = Color3.fromRGB(140, 255, 180),
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, -40, 0, 40),
	Position = UDim2.new(0, 20, 0.34, 0),
	TextTransparency = 1,
	Visible = false,
}, screenGui)

-- ----------------------------------------------------------------------
-- Som de confirmação
-- ----------------------------------------------------------------------
local confirmSound = Instance.new("Sound")
confirmSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
confirmSound.Volume = 0.45
confirmSound.Parent = SoundService

local function playConfirm(pitch: number)
	confirmSound.PlaybackSpeed = pitch
	confirmSound:Play()
end

-- ----------------------------------------------------------------------
-- Estado local (só visual)
-- ----------------------------------------------------------------------
local installed = 0
local required = Config.FUSE_COUNT
local holding: number? = nil
local gateOpen = false
local phase = "NeedFuses"
-- Quantos jogadores estão carregando fusível agora (co-op).
local holders = 0

-- Barra de instalação: fração confirmada pelo servidor + tempo local.
-- `installFloor` garante que a barra nunca anda para trás entre pacotes.
local installing = false
local installFloor = 0
local installAnchorAt = 0

local bannerUntil = 0
local bannerDuration = 3

local function setCounter()
	counter.Text = `{installed}/{required}`
	local ratio = if required > 0 then installed / required else 0
	counterFill.Size = UDim2.fromScale(ratio, 1)
	counterFill.BackgroundColor3 = if ratio >= 1
		then Color3.fromRGB(90, 220, 140)
		else Color3.fromRGB(230, 190, 70)
end

local function setStatusText()
	if phase == "Finished" then
		status.Text = "Partida encerrada."
	elseif gateOpen then
		status.Text = "Portão aberto! Corra para a saída."
	elseif holding ~= nil then
		status.Text = `Leve o fusível ao Gerador Central (você carrega 1).`
	else
		local faltam = math.max(0, required - installed)
		status.Text = if holders > 1
			then `Faltam {faltam} — {holders} carregando fusível.`
			else `Faltam {faltam} fusível(is) pelo mapa.`
	end
end

local function showBanner(text: string, color: Color3, duration: number?)
	banner.Text = text
	banner.TextColor3 = color
	banner.Visible = true
	banner.TextTransparency = 0
	bannerUntil = os.clock() + (duration or bannerDuration)
end

local function currentInstallRatio(): number
	if not installing then
		return 0
	end

	local elapsed = os.clock() - installAnchorAt
	local ratio = installFloor + elapsed / Config.FUSE_INSTALL_SECONDS
	return math.clamp(ratio, 0, 1)
end

local function applyState(payload: any)
	if type(payload) ~= "table" then
		return
	end

	installed = tonumber(payload.installed) or installed
	required = tonumber(payload.required) or required
	holders = math.max(0, math.floor(tonumber(payload.holders) or 0))
	phase = if type(payload.phase) == "string" then payload.phase else phase

	local newHolding = payload.holding
	holding = if type(newHolding) == "number" then newHolding else nil
	gateOpen = payload.gateOpen == true

	local estavaInstalando = installing
	installing = payload.installing == true

	if installing then
		local recebido = math.clamp(tonumber(payload.installProgress) or 0, 0, 1)

		if not estavaInstalando then
			-- Instalação começou agora: ancora na fração (normalmente ~0).
			installFloor = recebido
			installAnchorAt = os.clock()
		elseif recebido > currentInstallRatio() then
			-- O servidor está à frente do que desenhamos: reancora.
			installFloor = recebido
			installAnchorAt = os.clock()
		end
	else
		installFloor = 0
		installAnchorAt = 0
	end

	carryLabel.Visible = holding ~= nil and not gateOpen
	setCounter()
	setStatusText()
end

-- ----------------------------------------------------------------------
-- Eventos
-- ----------------------------------------------------------------------
remotes[Remotes.SERVER_TO_CLIENT.ESCAPE_STATE].OnClientEvent:Connect(applyState)

remotes[Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" or type(payload.message) ~= "string" then
		return
	end

	local kind = payload.kind

	if kind == "victory" then
		showBanner(payload.message, Color3.fromRGB(140, 255, 180), 5)
		playConfirm(1.4)
	elseif kind == "good" then
		playConfirm(1.15)
	elseif kind == "warn" then
		-- Avisos aparecem embaixo do painel; não poluem a tela.
		status.Text = payload.message
		playConfirm(0.7)
	end
end)

remotes[Remotes.SERVER_TO_CLIENT.GATE_OPENED].OnClientEvent:Connect(function()
	gateOpen = true
	showBanner("O PORTÃO ABRIU", Color3.fromRGB(140, 255, 180), 4)
	playConfirm(1.3)
	setStatusText()
end)

remotes[Remotes.SERVER_TO_CLIENT.ESCAPED].OnClientEvent:Connect(function(payload: any)
	local who = if type(payload) == "table" and type(payload.player) == "string" then payload.player else "Alguém"
	local seconds = if type(payload) == "table" and type(payload.seconds) == "number" then payload.seconds else 0

	showBanner(`{who} ESCAPOU em {math.floor(seconds)}s`, Color3.fromRGB(140, 255, 180), 8)
end)

-- ----------------------------------------------------------------------
-- Loop visual: barra de instalação e desvanecimento da faixa
-- ----------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	if installing then
		local ratio = currentInstallRatio()
		installPanel.Visible = true
		installFill.Size = UDim2.fromScale(ratio, 1)
		installFill.BackgroundColor3 = Color3.fromRGB(90, math.floor(170 + 70 * ratio), 140)
	else
		installPanel.Visible = false
	end

	if banner.Visible then
		local restante = bannerUntil - os.clock()
		if restante <= 0 then
			banner.Visible = false
			banner.TextTransparency = 1
		elseif restante < 0.8 then
			banner.TextTransparency = 1 - (restante / 0.8)
		end
	end
end)

-- Estado inicial enquanto o primeiro pacote não chega.
setCounter()
setStatusText()

-- Se o jogador respawnar, a HUD continua (ResetOnSpawn = false); só
-- escondemos a barra por segurança.
player.CharacterAdded:Connect(function()
	installPanel.Visible = false
end)

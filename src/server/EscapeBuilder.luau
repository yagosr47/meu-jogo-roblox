--!strict
-- Monta as peças físicas do objetivo de fuga: Gerador Central, Portão de
-- Saída e o modelo de cada fusível.
--
-- Só geometria e ProximityPrompt. Quem decide se a coleta/instalação vale é o
-- EscapeService (servidor).

local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local EscapeBuilder = {}

local GENERATOR_COLOR = Color3.fromRGB(90, 92, 100)
local GENERATOR_OFF = Color3.fromRGB(70, 40, 40)
local GENERATOR_ON = Color3.fromRGB(60, 210, 120)
local FUSE_COLOR = Color3.fromRGB(230, 190, 70)
local GATE_COLOR = Color3.fromRGB(120, 40, 40)

export type EscapeProps = {
	folder: Folder,
	generator: Model,
	generatorPrompt: ProximityPrompt,
	progressBarFill: Part,
	statusLight: Part,
	gate: Model,
	gatePanels: { BasePart },
	gateTrigger: Part,
}

local function makePart(properties: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.Locked = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	for key, value in properties do
		(part :: any)[key] = value
	end

	part.Parent = parent
	return part
end

--- Cria o Gerador Central com o ProximityPrompt de instalação.
function EscapeBuilder.buildGenerator(parent: Instance): (Model, ProximityPrompt, Part, Part)
	local position = Vector3.new(Config.GENERATOR_POSITION[1], Config.GENERATOR_POSITION[2], Config.GENERATOR_POSITION[3])

	local model = Instance.new("Model")
	model.Name = "GeradorCentral"

	-- `position` é a altura do PISO: cada peça soma metade da própria altura.
	local base = makePart({
		Name = "Base",
		Size = Vector3.new(8, 6, 6),
		Position = position + Vector3.new(0, 3, 0),
		Color = GENERATOR_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	local top = makePart({
		Name = "Topo",
		Size = Vector3.new(6, 1.2, 5),
		Position = base.Position + Vector3.new(0, 3.6, 0),
		Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.Metal,
	}, model)

	-- Luz de status: vermelha desligada, verde quando o gerador completa.
	local statusLight = makePart({
		Name = "LuzStatus",
		Size = Vector3.new(1.6, 1.6, 1.6),
		Shape = Enum.PartType.Ball,
		Position = base.Position + Vector3.new(3.2, 3.8, 0),
		Color = GENERATOR_OFF,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)

	-- Barra de progresso FÍSICA de 3 segundos: o servidor move este part.
	-- (A HUD do cliente mostra a mesma coisa; esta é a confirmação visual no
	-- mundo para quem está perto.)
	local progressBack = makePart({
		Name = "BarraFundo",
		Size = Vector3.new(5.5, 1.1, 0.3),
		Position = base.Position + Vector3.new(0, 3.7, -2.9),
		Color = Color3.fromRGB(30, 30, 34),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, model)

	local progressBarFill = makePart({
		Name = "BarraEnchimento",
		Size = Vector3.new(0.02, 1, 0.35),
		Position = progressBack.Position + Vector3.new(-2.75, 0.02, -0.05),
		Color = Color3.fromRGB(90, 220, 140),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Transparency = 1,
	}, model)

	progressBarFill:SetAttribute("BaseSize", 5.5)
	-- Guarda o centro do fundo como dado, para o serviço não depender de a
	-- peça ainda ter a posição original (a cada tick ela é reposicionada).
	progressBarFill:SetAttribute("AnchorX", progressBack.Position.X)
	progressBarFill:SetAttribute("AnchorY", progressBack.Position.Y)
	progressBarFill:SetAttribute("AnchorZ", progressBack.Position.Z)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InstallPrompt"
	prompt.ActionText = "Instalar fusível"
	prompt.ObjectText = "Gerador Central"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- só habilita com um fusível na mão
	prompt.Parent = base

	model.PrimaryPart = base
	model.Parent = parent

	return model, prompt, progressBarFill, statusLight
end

--- Cria o Portão de Saída (fechado por padrão).
function EscapeBuilder.buildGate(parent: Instance): (Model, { BasePart }, Part)
	local position = Vector3.new(Config.EXIT_GATE_POSITION[1], Config.EXIT_GATE_POSITION[2], Config.EXIT_GATE_POSITION[3])
	local width = Config.EXIT_GATE_WIDTH
	local height = Config.EXIT_GATE_HEIGHT

	local model = Instance.new("Model")
	model.Name = "PortaoDeSaida"

	-- `position` é o CENTRO vertical do vão do portão.
	local frameTop = makePart({
		Name = "MolduraTopo",
		Size = Vector3.new(width + 4, 2, 3),
		Position = position + Vector3.new(0, height / 2 + 1, 0),
		Color = GENERATOR_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	local frameLeft = makePart({
		Name = "MolduraEsquerda",
		Size = Vector3.new(2, height, 3),
		Position = position + Vector3.new(-(width / 2 + 1), 0, 0),
		Color = GENERATOR_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	local frameRight = makePart({
		Name = "MolduraDireita",
		Size = Vector3.new(2, height, 3),
		Position = position + Vector3.new(width / 2 + 1, 0, 0),
		Color = GENERATOR_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	-- Duas folhas que deslizam para os lados quando o gerador completa.
	local panelWidth = width / 2

	local leftPanel = makePart({
		Name = "FolhaEsquerda",
		Size = Vector3.new(panelWidth, height - 1, 1),
		Position = position + Vector3.new(-panelWidth / 2, 0, 0),
		Color = GATE_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	local rightPanel = makePart({
		Name = "FolhaDireita",
		Size = Vector3.new(panelWidth, height - 1, 1),
		Position = position + Vector3.new(panelWidth / 2, 0, 0),
		Color = GATE_COLOR,
		Material = Enum.Material.Metal,
	}, model)

	-- Volume invisível que marca a "zona de saída". O servidor mede a
	-- distância do jogador até aqui no tick (não usamos Touched: uma parte
	-- sem colisão pode nunca disparar o evento de física).
	local trigger = makePart({
		Name = "GatilhoSaida",
		Size = Vector3.new(width, height, 6),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, model)

	model.PrimaryPart = leftPanel
	model.Parent = parent

	return model, { leftPanel, rightPanel }, trigger
end

--- Atualiza a barra física do gerador conforme o progresso 0..1.
--- A referência (centro do fundo) fica gravada em atributos na criação, então
--- esta função é idempotente: pode rodar todo tick sem "andar" a barra.
function EscapeBuilder.setProgressBar(fill: Part, ratio: number)
	local baseSize: number = fill:GetAttribute("BaseSize") or 5.5
	local anchor = Vector3.new(
		fill:GetAttribute("AnchorX") or 0,
		fill:GetAttribute("AnchorY") or 0,
		fill:GetAttribute("AnchorZ") or 0
	)

	local clamped = math.clamp(ratio, 0, 1)
	local width = math.max(baseSize * clamped, 0.02)

	-- Borda esquerda fixa; o centro anda metade da largura.
	local leftEdge = anchor.X - baseSize / 2

	fill.Size = Vector3.new(width, 1, 0.35)
	fill.Position = Vector3.new(leftEdge + width / 2, anchor.Y, anchor.Z)
	fill.Transparency = if clamped <= 0 then 1 else 0
end

--- Liga/desliga o visual do gerador (cor + brilho).
function EscapeBuilder.setGeneratorState(statusLight: Part, complete: boolean)
	statusLight.Color = if complete then GENERATOR_ON else GENERATOR_OFF

	local light = statusLight:FindFirstChildOfClass("PointLight")
	if not light and complete then
		local created = Instance.new("PointLight")
		created.Brightness = 2
		created.Range = 26
		created.Color = Color3.fromRGB(90, 255, 150)
		created.Parent = statusLight
	elseif light and not complete then
		light:Destroy()
	end
end

--- Abre o portão (desliza as folhas para os lados).
function EscapeBuilder.openGate(model: Model, panels: { BasePart })
	for index, panel in panels do
		local direction = if index == 1 then -1 else 1
		local target = panel.Position + Vector3.new(direction * (panel.Size.X * 0.95), 0, 0)

		panel.CanCollide = false
		panel.Color = Color3.fromRGB(60, 200, 120)
		panel.Material = Enum.Material.Neon

		-- Animação leve, só cosmética.
		task.spawn(function()
			local start = panel.Position
			for step = 1, 20 do
				if not panel.Parent then
					return
				end
				local alpha = step / 20
				panel.Position = start:Lerp(target, alpha)
				task.wait(0.02)
			end
		end)
	end
end

return EscapeBuilder

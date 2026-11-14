--!strict
-- Constrói o cenário em runtime: sala fechada, pilares (para esconder e
-- quebrar linha de visão), luzes fracas e os pontos de spawn de pilha.
--
-- Fica no código (e não no default.project.json) porque o Resolver do Rojo 7
-- não suporta UDim2/NumberSequence para propriedades complexas — e porque
-- mantém a geometria junto do Config.
--
-- REGRA DE OURO DESTE MÓDULO: **nada aqui pode derrubar o servidor.**
-- Se uma pasta, objeto ou serviço não existir, é criado na hora. Se o
-- `ReplicatedStorage.Shared` não estiver presente (Rojo desconectado, projeto
-- desatualizado), usamos o Config embutido e seguimos com um aviso — um
-- cenário feio é infinitamente melhor do que um servidor que não sobe.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- `LightingLogic` é puro (só matemática), mas o require ainda pode falhar se
-- o Rojo estiver desconectado. Nesse caso seguimos sem as posições novas.
local LightingLogic = nil
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("LightingLogic")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			LightingLogic = result
		end
	end
end

local MapBuilder = {}

-- ======================================================================
-- Config: resolução tolerante
-- ======================================================================

--- Valores de emergência, usados SÓ se `ReplicatedStorage.Shared.Config`
--- não estiver disponível. Espelham os campos que este módulo lê.
local FALLBACK_CONFIG = {
	MAP_FLOOR_SIZE = 120,
	MAP_WALL_HEIGHT = 16,
	MAP_WALL_THICKNESS = 2,
	MAP_LIGHT_COUNT = 6,
	MAP_LIGHT_BRIGHTNESS = 1.2,
	MAP_LIGHT_RANGE = 34,
	FALLBACK_PICKUP_POINTS = 10,
}

--- Procura o módulo Config sem estourar se a pasta `Shared` não existir.
---
--- `require` de um caminho inexistente lança erro em tempo de carregamento e
--- derruba o módulo inteiro (era assim que o servidor não subia). Aqui a
--- ausência é tratada como um caso esperado.
--- `WaitForChild` com timeout pode LANÇAR erro (e não só devolver nil),
--- dependendo do contexto. Qualquer falha aqui significa "não achei".
local function safeWaitForChild(parent: Instance, name: string, timeout: number): Instance?
	local ok, result = pcall(function()
		return parent:WaitForChild(name, timeout)
	end)
	return if ok then result else nil
end

local function resolveConfig(): (any, boolean)
	local shared = ReplicatedStorage:FindFirstChild("Shared")

	-- O Rojo pode ainda não ter replicado a pasta no primeiro instante.
	if not shared then
		shared = safeWaitForChild(ReplicatedStorage, "Shared", 10)
	end

	if not shared then
		return FALLBACK_CONFIG, false
	end

	local configModule = shared:FindFirstChild("Config")
	if not configModule then
		configModule = safeWaitForChild(shared, "Config", 10)
	end

	if not configModule or not configModule:IsA("ModuleScript") then
		return FALLBACK_CONFIG, false
	end

	local ok, result = pcall(require, configModule)
	if not ok or type(result) ~= "table" then
		warn("[MapBuilder] Config inválido, usando valores embutidos:", result)
		return FALLBACK_CONFIG, false
	end

	return result, true
end

local Config, configResolved = resolveConfig()

-- Constantes derivadas. São declaradas AQUI, antes de qualquer função que as
-- leia ou escreva: em Luau, um `local` só é visível a partir da sua linha, e
-- uma função definida antes enxergaria o global (nil) em vez do local.
local FLOOR_SIZE = 0
local WALL_HEIGHT = 0
local WALL_THICKNESS = 0
local LIGHT_COUNT = 0
local LIGHT_BRIGHTNESS = 0
local LIGHT_RANGE = 0
local PICKUP_POINTS = 0

--- Lê um número do Config, com fallback se a chave faltar ou for inválida.
local function cfg(key: string, default: number): number
	local value = (Config :: any)[key]
	if type(value) == "number" and value == value then
		return value
	end
	return default
end

--- Aplica os valores do Config nas constantes do módulo.
local function applyConfig()
	FLOOR_SIZE = cfg("MAP_FLOOR_SIZE", FALLBACK_CONFIG.MAP_FLOOR_SIZE)
	WALL_HEIGHT = cfg("MAP_WALL_HEIGHT", FALLBACK_CONFIG.MAP_WALL_HEIGHT)
	WALL_THICKNESS = cfg("MAP_WALL_THICKNESS", FALLBACK_CONFIG.MAP_WALL_THICKNESS)
	LIGHT_COUNT = cfg("MAP_LIGHT_COUNT", FALLBACK_CONFIG.MAP_LIGHT_COUNT)
	LIGHT_BRIGHTNESS = cfg("MAP_LIGHT_BRIGHTNESS", FALLBACK_CONFIG.MAP_LIGHT_BRIGHTNESS)
	LIGHT_RANGE = cfg("MAP_LIGHT_RANGE", FALLBACK_CONFIG.MAP_LIGHT_RANGE)
	PICKUP_POINTS = cfg("FALLBACK_PICKUP_POINTS", FALLBACK_CONFIG.FALLBACK_PICKUP_POINTS)
end

applyConfig()

if not configResolved then
	warn(
		"[MapBuilder] ReplicatedStorage.Shared.Config não encontrado. "
			.. "Seguindo com os valores embutidos — rode `rojo serve` e reconecte o plugin."
	)
end

--- Reavalia os valores do Config (reexecutável).
---
--- Exportado por dois motivos: permite testar o caminho de fallback e permite
--- recarregar caso o Rojo conecte DEPOIS que o servidor já subiu.
function MapBuilder.reloadConfig(): boolean
	local resolved, ok = resolveConfig()
	Config = resolved
	configResolved = ok
	applyConfig()
	return ok
end

--- `true` se o Config real foi encontrado (e não o embutido).
function MapBuilder.hasRealConfig(): boolean
	return configResolved
end

-- ======================================================================
-- Helpers de criação tolerante
-- ======================================================================

--- Devolve o filho `name` de `parent`, criando-o se não existir.
---
--- Se existir com a classe errada, é substituído — usar um `Part` onde se
--- espera uma `Folder` quebraria o `Parent = ` mais adiante.
function MapBuilder.ensureChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)

	if existing then
		if existing.ClassName == className or existing:IsA(className) then
			return existing
		end

		warn(`[MapBuilder] {parent:GetFullName()}.{name} era {existing.ClassName}, trocando por {className}.`)
		existing:Destroy()
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

--- Atalho para `ensureChild(..., "Folder")`.
function MapBuilder.ensureFolder(parent: Instance, name: string): Folder
	return MapBuilder.ensureChild(parent, name, "Folder") :: Folder
end

-- ======================================================================
-- Geometria
-- ======================================================================

--- Geometria dos pilares (x, z, largura, profundidade). Somente leitura.
MapBuilder.pillars = {
	{ x = 20, z = 20, w = 10, d = 10, h = 14 },
	{ x = -22, z = 16, w = 8, d = 14, h = 14 },
	{ x = 26, z = -18, w = 14, d = 8, h = 14 },
	{ x = -18, z = -22, w = 10, d = 10, h = 14 },
	{ x = 2, z = 2, w = 12, d = 6, h = 12 },
}

local FLOOR_COLOR = Color3.fromRGB(38, 40, 46)
local WALL_COLOR = Color3.fromRGB(26, 27, 31)
local PILLAR_COLOR = Color3.fromRGB(48, 50, 56)

export type Pillar = {
	x: number,
	z: number,
	w: number,
	d: number,
	h: number,
}

export type Map = {
	folder: Folder,
	spawn: SpawnLocation,
	pickupPoints: { Vector3 },
}

export type PillarGeometry = {
	x: number,
	z: number,
	w: number,
	d: number,
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

--- Pilares internos: além de dar forma, servem para o monstro perder a
--- linha de visão do jogador (mecânica real de esconderijo).
---
--- Exportado como `MapBuilder.pillars`: o EscapeService usa esta MESMA lista
--- para não sortear fusível dentro de um pilar. Duplicar a lista aqui e lá
--- faria os fusíveis ficarem inalcançáveis se alguém movesse um pilar.
local PILLARS = MapBuilder.pillars

-- ======================================================================
-- Construção
-- ======================================================================

--- Monta o mapa (recriando sempre) e devolve as referências.
---
--- Nunca lança: `parent` inválido cai para o Workspace, e cada peça é criada
--- do zero — não depende de nada preexistente no Workspace.
function MapBuilder.build(parent: Instance?): Map
	-- Sem container informado, usa o Workspace (nunca falha por causa disso).
	local target: Instance = parent or Workspace

	local existing = target:FindFirstChild("TerrorMap")
	if existing then
		existing:Destroy()
	end

	local folder = MapBuilder.ensureFolder(target, "TerrorMap")

	local size = FLOOR_SIZE
	local half = size / 2
	local thickness = WALL_THICKNESS
	local height = WALL_HEIGHT

	-- ==================================================================
	-- Geometria sem sobreposição (o "chão bugado" era z-fighting)
	-- ==================================================================
	-- Regra que este bloco segue: duas faces de peças diferentes NUNCA
	-- ficam no mesmo plano. Quando ficam, a GPU não tem como decidir qual
	-- desenhar na frente e o resultado é aquele cintilar/zigue-zague — que
	-- aparece justamente na quina do chão com a parede.
	--
	-- Antes: o piso ia de -half a +half e as paredes eram centradas em
	-- `±half`, então metade de cada parede ficava FORA do piso e as duas
	-- faces coincidiam exatamente na borda.

	-- Piso: cresce meia espessura de parede para cada lado, para ficar
	-- DEBAIXO das paredes em vez de encostado nelas.
	local floorSize = size + thickness * 2
	local floor = makePart({
		Name = "Piso",
		Size = Vector3.new(floorSize, 2, floorSize),
		Position = Vector3.new(0, -1, 0),
		Color = FLOOR_COLOR,
		Material = Enum.Material.Concrete,
	}, folder)

	-- A base da parede fica DENTRO do piso (que vai de -2 a 0), nunca no
	-- mesmo plano da face inferior dele — senão o z-fighting só muda de lugar.
	local wallBase = -1.5

	-- As paredes sobem ATÉ DENTRO do teto — acima da face inferior dele. Se
	-- terminassem exatamente na base do teto, as duas faces ficariam no mesmo
	-- plano (wallTopY = ceilingY - 1) e o z-fighting só mudaria de lugar: do
	-- chão para o topo das paredes.
	local ceilingY = height + 2
	local wallTopY = ceilingY
	local ceiling = makePart({
		Name = "Teto",
		Size = Vector3.new(floorSize, 2, floorSize),
		Position = Vector3.new(0, ceilingY, 0),
		Color = WALL_COLOR,
		Material = Enum.Material.Concrete,
	}, folder)

	-- As paredes vão da base (dentro do piso) até o topo (dentro do teto),
	-- sempre sobrepostas em vez de encostadas face a face.
	local wallCenterY = (wallBase + wallTopY) / 2
	local wallSizeY = wallTopY - wallBase
	local wallSpan = size + thickness * 2

	local walls = {
		{ name = "ParedeNorte", size = Vector3.new(wallSpan, wallSizeY, thickness), pos = Vector3.new(0, wallCenterY, -half) },
		{ name = "ParedeSul", size = Vector3.new(wallSpan, wallSizeY, thickness), pos = Vector3.new(0, wallCenterY, half) },
		{ name = "ParedeLeste", size = Vector3.new(thickness, wallSizeY, wallSpan), pos = Vector3.new(half, wallCenterY, 0) },
		{ name = "ParedeOeste", size = Vector3.new(thickness, wallSizeY, wallSpan), pos = Vector3.new(-half, wallCenterY, 0) },
	}

	for _, wall in walls do
		makePart({
			Name = wall.name,
			Size = wall.size,
			Position = wall.pos,
			Color = WALL_COLOR,
			Material = Enum.Material.Concrete,
		}, folder)
	end

	-- Os pilares afundam `PILLAR_SINK` no piso. Se a base deles ficasse
	-- exatamente em y=0 (o topo do piso), a face de baixo de cada pilar
	-- ficaria coplanar com o chão e voltaria o mesmo cintilar — agora na base
	-- dos pilares, que é onde o jogador passa o tempo todo.
	local PILLAR_SINK = 0.5

	for index, pillar in PILLARS do
		makePart({
			Name = "Pilar" .. index,
			Size = Vector3.new(pillar.w, pillar.h + PILLAR_SINK, pillar.d),
			Position = Vector3.new(pillar.x, (pillar.h + PILLAR_SINK) / 2 - PILLAR_SINK, pillar.z),
			Color = PILLAR_COLOR,
			Material = Enum.Material.Brick,
		}, folder)
	end

	-- Luzes fracas e espaçadas: o suficiente para andar, não para se sentir
	-- seguro. (A lanterna é que ilumina de verdade.)
	--
	-- Duas decisões que resolvem o "mapa piscando luzes aleatórias":
	--
	--   * `Shadows = false` nestas luzes. Uma PointLight com sombra faz o
	--     motor recalcular o shadow map toda vez que o Part entra/sai do
	--     campo de visão — com 6 delas o mapa cintila ao caminhar. Sombra
	--     fica só na lanterna do jogador, que é a que dá tensão.
	--   * posição em GRADE, derivada do tamanho do mapa (antes era um círculo
	--     de raio 36 que deixava o centro e as quinas no escuro).

	-- Fallback embutido: sem `LightingLogic` (Rojo desconectado), usa um
	-- círculo simples. O mapa fica menos bonito, mas sobe.
	local lightPositions: { { number } }
	if LightingLogic then
		-- Passamos os pilares: uma luz pendurada em cima de um pilar de 14
		-- studs bate na laje dele e vira um clarão chapado, deixando o chão
		-- ao redor escuro.
		lightPositions = LightingLogic.lightPositions(size, height, LIGHT_COUNT, PILLARS)
	else
		local count = math.max(1, math.floor(LIGHT_COUNT))
		lightPositions = {}
		for index = 1, count do
			local angle = (index / count) * math.pi * 2
			table.insert(lightPositions, {
				math.cos(angle) * size * 0.3,
				height - 2,
				math.sin(angle) * size * 0.3,
			})
		end
	end

	for index, position in lightPositions do
		local holder = Instance.new("Part")
		holder.Name = "Luz" .. index
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		-- O suporte precisa ser grande: o motor faz culling da luz pela
		-- bounding box do Part pai. Com 1 stud, a luz some ao andar.
		holder.Size = Vector3.new(6, 1, 6)
		holder.Transparency = 1
		holder.CastShadow = false
		holder.Position = Vector3.new(position[1], position[2], position[3])
		holder.Parent = folder

		local light = Instance.new("PointLight")
		light.Brightness = LIGHT_BRIGHTNESS
		light.Range = LIGHT_RANGE
		light.Color = Color3.fromRGB(255, 214, 170)
		-- Sem sombra: é o que impede o mapa de cintilar ao andar.
		light.Shadows = false
		light.Parent = holder

		-- A cintilação é feita no CLIENTE (um `PointLight` tweenando no
		-- servidor seria replicado todo frame para todos os jogadores).
		-- Guardamos os parâmetros como atributos para o cliente ler.
		light:SetAttribute("FlickerBase", LIGHT_BRIGHTNESS)
		light:SetAttribute("FlickerIndex", index)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "StartSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(0, 0.5, -half + 12)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	-- Pontos válidos para as pilhas: espalhados e longe das paredes.
	local pickupPoints: { Vector3 } = {}
	local pointCount = math.max(1, math.floor(PICKUP_POINTS))

	for index = 1, pointCount do
		local angle = (index / pointCount) * math.pi * 2 + 0.4
		local radius = half * 0.72
		table.insert(pickupPoints, Vector3.new(math.cos(angle) * radius, 1.5, math.sin(angle) * radius))
	end

	-- Nada de outro SpawnLocation ativo no mapa (senão o jogador nasce fora).
	-- `pcall` porque GetDescendants pode falhar se o Workspace estiver sendo
	-- modificado no mesmo instante.
	pcall(function()
		for _, descendant in Workspace:GetDescendants() do
			if descendant:IsA("SpawnLocation") and descendant ~= spawn then
				descendant.Enabled = false
			end
		end
	end)

	return {
		folder = folder,
		spawn = spawn,
		pickupPoints = pickupPoints,
	}
end

-- ======================================================================
-- Atmosfera
-- ======================================================================

--- Aplica a atmosfera de terror no Lighting.
---
--- O Atmosphere em si vem do default.project.json (com Density/Haze), para o
--- visual ficar igual mesmo se este script falhar. Aqui só reforçamos o que
--- precisa ser garantido em runtime.
function MapBuilder.applyAtmosphere()
	Lighting.Ambient = Color3.fromRGB(8, 8, 12)
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 22, 30)
	Lighting.Brightness = 0.4
	Lighting.EnvironmentDiffuseScale = 0.1
	Lighting.EnvironmentSpecularScale = 0.05
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.6
	Lighting.ClockTime = 0
	Lighting.GeographicLatitude = 0
	Lighting.ExposureCompensation = -0.35

	Lighting.FogColor = Color3.fromRGB(10, 11, 16)
	Lighting.FogStart = 8
	Lighting.FogEnd = 90

	-- Garante o Atmosphere (o projeto já traz um; só criamos se faltar).
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		local created = Instance.new("Atmosphere")
		created.Density = 0.42
		created.Offset = 0.1
		created.Color = Color3.fromRGB(102, 107, 122)
		created.Decay = Color3.fromRGB(41, 43, 51)
		created.Glare = 0
		created.Haze = 3.2
		created.Parent = Lighting
	end
end

return MapBuilder

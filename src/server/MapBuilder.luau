--!strict
-- Constrói o cenário em runtime: sala fechada, pilares (para esconder e
-- quebrar linha de visão), luzes fracas e os pontos de spawn de pilha.
--
-- Fica no código (e não no default.project.json) porque o Resolver do Rojo 7
-- não suporta UDim2/NumberSequence para propriedades complexas — e porque
-- mantém a geometria junto do Config.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

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

--- Monta o mapa (ou reaproveita, se já existir) e devolve as referências.
function MapBuilder.build(parent: Instance): Map
	local existing = parent:FindFirstChild("TerrorMap")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "TerrorMap"
	folder.Parent = parent

	local size = Config.MAP_FLOOR_SIZE

	local floor = makePart({
		Name = "Piso",
		Size = Vector3.new(size, 2, size),
		Position = Vector3.new(0, -1, 0),
		Color = FLOOR_COLOR,
		Material = Enum.Material.Concrete,
	}, folder)

	local ceiling = makePart({
		Name = "Teto",
		Size = Vector3.new(size, 2, size),
		Position = Vector3.new(0, Config.MAP_WALL_HEIGHT + 1, 0),
		Color = WALL_COLOR,
		Material = Enum.Material.Concrete,
	}, folder)

	local half = size / 2
	local thickness = Config.MAP_WALL_THICKNESS
	local height = Config.MAP_WALL_HEIGHT

	local walls = {
		{ name = "ParedeNorte", size = Vector3.new(size, height, thickness), pos = Vector3.new(0, height / 2, -half) },
		{ name = "ParedeSul", size = Vector3.new(size, height, thickness), pos = Vector3.new(0, height / 2, half) },
		{ name = "ParedeLeste", size = Vector3.new(thickness, height, size), pos = Vector3.new(half, height / 2, 0) },
		{ name = "ParedeOeste", size = Vector3.new(thickness, height, size), pos = Vector3.new(-half, height / 2, 0) },
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

	for index, pillar in PILLARS do
		makePart({
			Name = "Pilar" .. index,
			Size = Vector3.new(pillar.w, pillar.h, pillar.d),
			Position = Vector3.new(pillar.x, pillar.h / 2, pillar.z),
			Color = PILLAR_COLOR,
			Material = Enum.Material.Brick,
		}, folder)
	end

	-- Luzes fracas e espaçadas: o suficiente para andar, não para se sentir
	-- seguro. (A lanterna é que ilumina de verdade.)
	for index = 1, Config.MAP_LIGHT_COUNT do
		local angle = (index / Config.MAP_LIGHT_COUNT) * math.pi * 2
		local radius = size * 0.3
		local position = Vector3.new(math.cos(angle) * radius, height - 3, math.sin(angle) * radius)

		local holder = Instance.new("Part")
		holder.Name = "Luz" .. index
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.Position = position
		holder.Parent = folder

		local light = Instance.new("PointLight")
		light.Brightness = Config.MAP_LIGHT_BRIGHTNESS
		light.Range = Config.MAP_LIGHT_RANGE
		light.Color = Color3.fromRGB(255, 214, 170)
		light.Shadows = true
		light.Parent = holder
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
	for index = 1, Config.FALLBACK_PICKUP_POINTS do
		local angle = (index / Config.FALLBACK_PICKUP_POINTS) * math.pi * 2 + 0.4
		local radius = half * 0.72
		table.insert(pickupPoints, Vector3.new(math.cos(angle) * radius, 1.5, math.sin(angle) * radius))
	end

	-- Marca como principal o spawn do mapa.
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant ~= spawn then
			descendant.Enabled = false
		end
	end

	return {
		folder = folder,
		spawn = spawn,
		pickupPoints = pickupPoints,
	}
end

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

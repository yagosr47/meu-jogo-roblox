--!strict
-- Constrói (em runtime) a pista, o pad de largada e os checkpoints.
--
-- Os checkpoints NÃO são servidos pelo Rojo: o servidor cria tudo no `Workspace`
-- quando inicia. A posição de cada trigger fica registrada em `course[index]`
-- para a validação de distância.

local Config = require(script.Parent.Parent.shared.Config)

export type CheckpointInfo = {
	index: number,
	isFinish: boolean,
	position: Vector3,
	part: BasePart,
}

export type Course = {
	folder: Folder,
	startPad: BasePart,
	checkpoints: { CheckpointInfo },
	spawnLocation: SpawnLocation,
}

local CourseBuilder = {}

local FLOOR_COLOR = Color3.fromRGB(78, 84, 96)
local START_COLOR = Color3.fromRGB(46, 160, 67)
local CHECKPOINT_COLOR = Color3.fromRGB(52, 120, 200)
local FINISH_COLOR = Color3.fromRGB(220, 168, 32)

local function makePart(properties: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	for key, value in properties do
		(part :: any)[key] = value
	end

	part.Parent = parent
	return part
end

--- Constrói a pista inteira e devolve as referências usadas na validação.
function CourseBuilder.build(parent: Instance): Course
	local existing = parent:FindFirstChild("RaceCourse")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "RaceCourse"
	folder.Parent = parent

	local totalWidth = Config.FLOOR_WIDTH
	local floorLength = (Config.CHECKPOINT_COUNT + 1) * Config.TRACK_SPACING + Config.FLOOR_MARGIN * 2

	local floor = makePart({
		Name = "Pista",
		Size = Vector3.new(totalWidth, Config.FLOOR_THICKNESS, floorLength),
		Position = Vector3.new(0, -Config.FLOOR_THICKNESS / 2, floorLength / 2 - Config.FLOOR_MARGIN),
		Color = FLOOR_COLOR,
		Material = Enum.Material.Slate,
	}, folder)

	-- Paredes laterais: evitam cair da pista (e de "voar" para fora).
	for _, side in { -1, 1 } do
		makePart({
			Name = if side < 0 then "ParedeEsquerda" else "ParedeDireita",
			Size = Vector3.new(2, 18, floorLength),
			Position = Vector3.new(side * (totalWidth / 2), 9, floor.Position.Z),
			Color = FLOOR_COLOR,
			Material = Enum.Material.Slate,
			Transparency = 0.35,
		}, folder)
	end

	local startPad = makePart({
		Name = "StartPad",
		Size = Vector3.new(Config.START_PAD_WIDTH, 1, 12),
		Position = Vector3.new(0, 0.5, 0),
		Color = START_COLOR,
		Material = Enum.Material.Neon,
	}, folder)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "RaceSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.6, -12)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	local checkpoints: { CheckpointInfo } = {}

	for index = 1, Config.CHECKPOINT_COUNT do
		local isFinish = index == Config.CHECKPOINT_COUNT
		local position = Vector3.new(0, Config.CHECKPOINT_HEIGHT / 2, index * Config.TRACK_SPACING)

		local part = makePart({
			Name = if isFinish then "Finish" else string.format("Checkpoint%d", index),
			Size = Vector3.new(Config.CHECKPOINT_WIDTH, Config.CHECKPOINT_HEIGHT, Config.CHECKPOINT_DEPTH),
			Position = position,
			Color = if isFinish then FINISH_COLOR else CHECKPOINT_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CanCollide = false,
		}, folder)

		table.insert(checkpoints, {
			index = index,
			isFinish = isFinish,
			position = position,
			part = part,
		})
	end

	return {
		folder = folder,
		startPad = startPad,
		checkpoints = checkpoints,
		spawnLocation = spawn,
	}
end

--- Realça visualmente o próximo checkpoint.
--- Puramente cosmético: quem decide se valeu é o servidor. O `player` fica na
--- assinatura para, no futuro, dar realce individual sem quebrar chamadores.
function CourseBuilder.highlight(course: Course, player: Player | nil, nextIndex: number)
	for _, info in course.checkpoints do
		local isNext = info.index == nextIndex
		info.part.Transparency = if isNext then 0.25 else 0.8
		info.part.Color = if isNext
			then (if info.isFinish then FINISH_COLOR else CHECKPOINT_COLOR)
			else Color3.fromRGB(70, 70, 78)
	end
end

return CourseBuilder

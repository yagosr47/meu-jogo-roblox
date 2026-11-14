--!strict
-- Objetivo principal de fuga: 5 fusíveis -> Gerador Central -> Portão.
--
-- TODA a validação mora aqui:
--   * distância de coleta e de instalação medidas no servidor;
--   * só 1 fusível na mão por jogador;
--   * os 3 segundos de instalação contados no relógio do servidor;
--   * portão só abre com os 5 instalados;
--   * vitória só cruzando o portão aberto.
--
-- O estado é POR PARTIDA e compartilhado entre os jogadores (co-op): se um
-- pega o fusível e outro instala, o progresso é o mesmo. Isso é decidido aqui,
-- não no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local EscapeLogic = require(ReplicatedStorage.Shared.EscapeLogic)
local FuseSpawner = require(ReplicatedStorage.Shared.FuseSpawner)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EscapeBuilder = require(script.Parent.EscapeBuilder)
local MapBuilder = require(script.Parent.MapBuilder)
local PlayerState = require(script.Parent.PlayerState)

local EscapeService = {}

export type Service = {
	folder: Folder,
	fuses: { EscapeLogic.Fuse },
	getProgress: () -> EscapeLogic.Progress,
	tick: (now: number) -> (),
	handleCollect: (player: Player, fuseId: number) -> (),
	handleInstallStart: (player: Player) -> (),
	handleCancel: (player: Player) -> (),
	reset: () -> (),
}

local FUSE_MODEL_NAME = "Fusivel"


--- `floor` é a superfície do piso; as peças sobem a partir dela.
local function makeFuseModel(floor: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = FUSE_MODEL_NAME

	local body = Instance.new("Part")
	body.Name = "Corpo"
	body.Size = Vector3.new(0.8, 2.2, 0.8)
	body.Position = floor + Vector3.new(0, 1.1, 0)
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.Metal
	body.Color = Color3.fromRGB(230, 190, 70)
	body.Parent = model

	local cap = Instance.new("Part")
	cap.Name = "Terminal"
	cap.Size = Vector3.new(0.5, 0.4, 0.5)
	cap.Position = body.Position + Vector3.new(0, 1.3, 0)
	cap.Anchored = true
	cap.CanCollide = false
	cap.Material = Enum.Material.Neon
	cap.Color = Color3.fromRGB(255, 240, 150)
	cap.Parent = model

	local light = Instance.new("PointLight")
	light.Brightness = 0.9
	light.Range = 10
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Parent = cap

	-- O prompt só sinaliza; o servidor decide.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Pegar fusível"
	prompt.ObjectText = "Fusível"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	model.PrimaryPart = body
	model.Parent = parent

	return model
end

--- Mostra/esconde um fusível sem destruí-lo.
---
--- Guardar o modelo (em vez de destruir) é o que permite DEVOLVER o fusível
--- ao mapa se quem o carregava sair do jogo — destruir tornaria o objetivo
--- impossível de completar.
local function setFuseVisible(model: Model, visible: boolean)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = if visible then 0 else 1
			descendant.CanCollide = false
			descendant.CanQuery = visible
			descendant.CanTouch = visible
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = visible
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = visible
		end
	end
end

--- Libera os fusíveis de quem saiu do jogo (senão ficam presos para sempre e
--- o objetivo trava). Devolve o estado novo e a lista de fusíveis devolvidos.
local function releaseOrphans(
	progress: EscapeLogic.Progress,
	fuses: { EscapeLogic.Fuse },
	restoreFuse: (number) -> ()
): (EscapeLogic.Progress, { number })
	local present: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		present[player.UserId] = true
	end

	local released: { number } = {}

	for userId, fuseId in progress.holders do
		if not present[userId] then
			local fuse = fuses[fuseId]
			if fuse then
				progress = EscapeLogic.releaseFuse(progress, fuse, userId)
			else
				local holders = table.clone(progress.holders)
				holders[userId] = nil
				progress = EscapeLogic.withChanges(progress, { holders = holders })
			end

			if fuseId then
				restoreFuse(fuseId)
				table.insert(released, fuseId)
			end
		end
	end

	-- Se quem estava instalando saiu, cancela.
	if progress.installingBy ~= nil and not present[progress.installingBy] then
		progress = EscapeLogic.cancelInstall(progress)
	end

	return progress, released
end

function EscapeService.start(): Service
	-- O mapa é só o container visual. Se ele não existir, criamos um — o
	-- serviço nunca deve derrubar o servidor por causa de uma pasta ausente
	-- (era o que acontecia quando o MapBuilder falhava).
	local map = Workspace:FindFirstChild("TerrorMap")
	if not map then
		warn("[EscapeService] TerrorMap ausente; criando um para pendurar o objetivo.")
		map = MapBuilder.ensureFolder(Workspace, "TerrorMap")
	end

	local existing = map:FindFirstChild("ObjetivoFuga")
	if existing then
		existing:Destroy()
	end

	local folder = MapBuilder.ensureFolder(map, "ObjetivoFuga")

	local remoteFolder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME) :: Folder

	-- ------------------------------------------------------------------
	-- 1. Gerador e portão
	-- ------------------------------------------------------------------
	local generator, installPrompt, progressBarFill, statusLight = EscapeBuilder.buildGenerator(folder)
	local gate, gatePanels, gateTrigger = EscapeBuilder.buildGate(folder)

	EscapeBuilder.setGeneratorState(statusLight, false)
	EscapeBuilder.setProgressBar(progressBarFill, 0)

	-- ------------------------------------------------------------------
	-- 2. Fusíveis em pontos aleatórios
	-- ------------------------------------------------------------------
	local fuseFolder = Instance.new("Folder")
	fuseFolder.Name = "Fusiveis"
	fuseFolder.Parent = folder

	local spawnOption = Vector3.new(0, 0, -Config.MAP_FLOOR_SIZE / 2 + 12)
	local generatorVector = Vector3.new(Config.GENERATOR_POSITION[1], 0, Config.GENERATOR_POSITION[3])
	local gateVector = Vector3.new(Config.EXIT_GATE_POSITION[1], 0, Config.EXIT_GATE_POSITION[3])

	-- O gerador é sólido (8 x 6 studs): entra na lista de obstáculos para o
	-- sorteio nunca colocar um fusível dentro dele.
	local function generatorObstacle(): FuseSpawner.Obstacle
		local size = Vector3.new(8, 6, 6)
		local primary = generator.PrimaryPart
		local center = if primary then primary.Position else Vector3.new(generatorVector.X, 0, generatorVector.Z)
		return {
			x = center.X,
			z = center.Z,
			w = size.X + Config.GENERATOR_PADDING,
			d = size.Z + Config.GENERATOR_PADDING,
		}
	end

	-- Os pilares vêm do MapBuilder: uma única fonte de verdade da geometria.
	local obstacles: { FuseSpawner.Obstacle } = {}
	for _, pillar in MapBuilder.pillars do
		table.insert(obstacles, { x = pillar.x, z = pillar.z, w = pillar.w, d = pillar.d })
	end

	-- O gerador também é sólido: vira obstáculo para não sortear fusível
	-- dentro dele.
	table.insert(obstacles, generatorObstacle())

	local points = FuseSpawner.roll({
		halfSize = Config.MAP_FLOOR_SIZE / 2,
		obstacles = obstacles,
		spawn = { x = spawnOption.X, y = 0, z = spawnOption.Z },
		generator = { x = generatorVector.X, y = 0, z = generatorVector.Z },
		gate = { x = gateVector.X, y = 0, z = gateVector.Z },
	}, Config.FUSE_COUNT)

	local fuses: { EscapeLogic.Fuse } = {}
	local fuseModels: { [number]: Model } = {}

	-- Declarações antecipadas: os Prompts dos fusíveis são conectados já aqui,
	-- mas as funções de verdade são definidas mais abaixo (elas precisam do
	-- estado da partida, que ainda não existe neste ponto).
	local collect: (Player, Model) -> ()
	local startInstall: (Player) -> ()
	local finishInstall: (Player) -> ()
	local cancelInstall: (Player) -> ()

	for index, point in points do
		-- O piso de TerrorMap fica com a superfície em Y = 0.
		local floorPosition = Vector3.new(point.x, 0, point.z)
		local model = makeFuseModel(floorPosition, fuseFolder)
		model:SetAttribute("FuseId", index)

		fuses[index] = EscapeLogic.newFuse(index)
		fuseModels[index] = model

		local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				collect(player, model)
			end)
		end
	end

	-- ------------------------------------------------------------------
	-- 3. Estado da partida
	-- ------------------------------------------------------------------
	local progress = EscapeLogic.newProgress()
	-- Ritmo de coleta por jogador (anti-farm).
	local pickupTimestamps: { [Player]: { number } } = {}

	local startedAt = os.clock()

	-- ------------------------------------------------------------------
	-- 4. Replicação para os clientes
	-- ------------------------------------------------------------------
	local stateRemote = Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_STATE)
	local eventRemote = Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT)

	--- Cada jogador recebe o MESMO progresso da partida, mas a mão é a dele.
	local function broadcast()
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			stateRemote:FireClient(player, EscapeLogic.toPayload(progress, player.UserId, now))
		end
	end

	local function notify(player: Player, message: string, kind: string)
		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT):FireClient(player, {
			message = message,
			kind = kind,
		})
	end

	--- O prompt do gerador é compartilhado por todos, então ele fica ligado
	--- enquanto o gerador não estiver completo. Quem pode instalar (estar com
	--- um fusível na mão e ser o dono dele) é decidido em `startInstall`.
	local function setPromptState()
		installPrompt.Enabled = not EscapeLogic.isComplete(progress.installed)
	end

	-- ------------------------------------------------------------------
	-- 5. Helpers de validação (distância sempre medida no servidor)
	-- ------------------------------------------------------------------
	local function rootPosition(player: Player): (Vector3?, boolean)
		local character = player.Character
		if not character then
			return nil, false
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")

		if not root or not root:IsA("BasePart") then
			return nil, false
		end

		local alive = humanoid ~= nil and humanoid.Health > 0
		return root.Position, alive
	end

	local function distanceTo(player: Player, target: Vector3): number
		local position = rootPosition(player)
		if not position then
			return math.huge
		end
		return (position - target).Magnitude
	end

	local function generatorPosition(): Vector3
		local primary = generator.PrimaryPart
		return if primary then primary.Position else Vector3.new(
			Config.GENERATOR_POSITION[1],
			Config.GENERATOR_POSITION[2],
			Config.GENERATOR_POSITION[3]
		)
	end

	-- ------------------------------------------------------------------
	-- 6. Coleta
	-- ------------------------------------------------------------------
	function collect(player: Player, model: Model)
		local state = PlayerState.get(player)
		if not state or state.isCaught then
			return
		end

		-- Ritmo por jogador.
		local now = os.clock()
		local timestamps = pickupTimestamps[player] or {}
		local recent: { number } = {}
		for _, timestamp in timestamps do
			if (now - timestamp) <= 60 then
				table.insert(recent, timestamp)
			end
		end
		pickupTimestamps[player] = recent

		if #recent >= Config.FUSE_PICKUP_MAX_PER_MINUTE then
			return
		end

		local fuseId = model:GetAttribute("FuseId")
		if typeof(fuseId) ~= "number" then
			return
		end

		-- O prompt pode disparar com o modelo já escondido (coleta concorrida
		-- de dois jogadores no mesmo frame).
		if fuseModels[fuseId] ~= model then
			return
		end

		local fuse = fuses[fuseId]
		local position = model:GetPivot().Position

		local rootPos, alive = rootPosition(player)
		local distance = if rootPos then (rootPos - position).Magnitude else math.huge

		local verdict = EscapeLogic.canCollect(progress, fuse, player.UserId, distance, alive)
		if not verdict.ok then
			if verdict.reason ~= "longe demais" and verdict.reason ~= "fusível inexistente" then
				notify(player, "Não é possível pegar: " .. verdict.reason, "warn")
			end
			return
		end

		table.insert(recent, now)
		progress = EscapeLogic.markCollected(progress, fuse, player.UserId)

		-- Esconde (não destrói): se o portador sair ou morrer, este fusível
		-- volta para o mapa.
		setFuseVisible(model, false)

		broadcast()
		notify(player, `Fusível {fuseId}/{Config.FUSE_COUNT} na mão. Leve ao Gerador Central.`, "good")
	end

	-- ------------------------------------------------------------------
	-- 7. Instalação (3 segundos medidos no servidor)
	-- ------------------------------------------------------------------
	function startInstall(player: Player)
		local state = PlayerState.get(player)
		if not state or state.isCaught then
			return
		end

		local rootPos, alive = rootPosition(player)
		local distance = if rootPos then (rootPos - generatorPosition()).Magnitude else math.huge
		local now = os.clock()

		-- `canStartInstall` já confere se ESTE jogador tem fusível na mão.
		-- O prompt do gerador é compartilhado: sem essa checagem, alguém
		-- parado perto poderia instalar o fusível de outra pessoa.
		local verdict = EscapeLogic.canStartInstall(progress, player.UserId, distance, now, alive)
		if not verdict.ok then
			if verdict.reason ~= "longe demais do gerador" then
				notify(player, verdict.reason, "warn")
			end
			return
		end

		progress = EscapeLogic.beginInstall(progress, player.UserId, now)
		broadcast()
		notify(player, `Instalando... não saia do lugar ({Config.FUSE_INSTALL_SECONDS}s).`, "info")
	end

	function finishInstall(player: Player)
		local now = os.clock()

		local rootPos, alive = rootPosition(player)
		local distance = if rootPos then (rootPos - generatorPosition()).Magnitude else math.huge

		local verdict = EscapeLogic.canFinishInstall(progress, player.UserId, now, distance, alive)
		if not verdict.ok then
			return
		end

		local wasInstalled = progress.installed
		progress = EscapeLogic.completeInstall(progress, player.UserId, now)

		-- O fusível foi consumido: a mão deste jogador fica livre.
		-- A barra física zera e o prompt continua valendo para o próximo.
		EscapeBuilder.setProgressBar(progressBarFill, 0)
		broadcast()

		if progress.installed > wasInstalled then
			Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT):FireAllClients({
				message = `Fusível instalado ({progress.installed}/{Config.FUSE_COUNT})`,
				kind = "good",
			})
		end

		if EscapeLogic.isComplete(progress.installed) then
			EscapeBuilder.setGeneratorState(statusLight, true)
			EscapeBuilder.openGate(gate, gatePanels)

			Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT):FireAllClients({
				message = "Gerador completo! O portão de saída abriu.",
				kind = "victory",
			})

			Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.GATE_OPENED):FireAllClients({
				position = { gateTrigger.Position.X, gateTrigger.Position.Y, gateTrigger.Position.Z },
			})
		end
	end

	function cancelInstall(player: Player)
		-- Ninguém cancela a instalação de outro jogador.
		if progress.installingBy ~= player.UserId then
			return
		end

		progress = EscapeLogic.cancelInstall(progress)
		broadcast()
	end

	-- ------------------------------------------------------------------
	-- 8. Prompt do gerador
	-- ------------------------------------------------------------------
	installPrompt.Triggered:Connect(function(player: Player)
		local state = PlayerState.get(player)
		if not state then
			return
		end

		-- O prompt inicia a instalação; o término é validado no tick
		-- (com o relógio do servidor), não pelo cliente.
		startInstall(player)
	end)

	-- ------------------------------------------------------------------
	-- 9. Portão: vitória ao cruzar
	-- ------------------------------------------------------------------
	-- A vitória é checada por DISTÂNCIA no tick, não por Touched: o gatilho
	-- não colide (CanCollide = false), então um evento de física poderia
	-- nunca disparar. Assim o servidor sempre avalia e a regra é a mesma para
	-- todo mundo.
	local function tryWin(player: Player)
		if not progress.gateOpen or progress.phase == "Finished" then
			return
		end

		local rootPos, alive = rootPosition(player)
		local distance = if rootPos then (rootPos - gateTrigger.Position).Magnitude else math.huge

		if not EscapeLogic.canWin(progress, distance, alive).ok then
			return
		end

		progress = EscapeLogic.markFinished(progress, os.clock())
		broadcast()

		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT):FireAllClients({
			message = `{player.Name} escapou! Vitória.`,
			kind = "victory",
		})
		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPED):FireAllClients({
			player = player.Name,
			seconds = os.clock() - startedAt,
		})
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		pickupTimestamps[player] = nil
	end)

	-- Nota: se o portador sair do jogo, `releaseOrphans` (no tick) detecta
	-- que ele não está mais em Players:GetPlayers() e devolve o fusível ao
	-- mapa. Não é preciso um handler separado.

	-- ------------------------------------------------------------------
	-- 10. Tick: progresso da instalação, cancelamento e limpeza
	-- ------------------------------------------------------------------
	local function tick(now: number)
		-- 1. Quem saiu do jogo perde o fusível — que VOLTA para o mapa.
		local released
		progress, released = releaseOrphans(progress, fuses, function(fuseId: number)
			local model = fuseModels[fuseId]
			if model and model.Parent then
				setFuseVisible(model, true)
			end
		end)

		if #released > 0 then
			broadcast()
			Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.ESCAPE_EVENT):FireAllClients({
				message = "Um fusível voltou ao mapa (o portador saiu).",
				kind = "warn",
			})
		end

		-- 2. Barra física do gerador.
		if progress.installingBy ~= nil then
			EscapeBuilder.setProgressBar(progressBarFill, EscapeLogic.installProgress(progress, now))
		else
			EscapeBuilder.setProgressBar(progressBarFill, 0)
		end

		-- 3. Chegou no portão aberto? Venceu.
		if progress.gateOpen and progress.phase ~= "Finished" then
			for _, player in Players:GetPlayers() do
				tryWin(player)
				if progress.phase == "Finished" then
					break
				end
			end
		end

		-- 4. Instalação em andamento: conclui, ou cancela se preciso.
		if progress.installingBy == nil then
			return
		end

		local userId = progress.installingBy :: number
		local player = Players:GetPlayerByUserId(userId)

		if player == nil then
			-- Saiu do jogo: `releaseOrphans` já cuidou do fusível.
			progress = EscapeLogic.cancelInstall(progress)
			broadcast()
			return
		end

		local rootPos, alive = rootPosition(player)
		local distance = if rootPos then (rootPos - generatorPosition()).Magnitude else math.huge

		if not alive or EscapeLogic.shouldAbortInstall(progress, distance) then
			progress = EscapeLogic.cancelInstall(progress)
			broadcast()
			notify(player, "Instalação cancelada.", "warn")
		elseif EscapeLogic.installProgress(progress, now) >= 1 then
			finishInstall(player)
		end
	end

	setPromptState()
	broadcast()

	-- Replica o progresso da barra de tempos em tempos (o cliente também
	-- anima sozinho com o `serverNow`).
	task.spawn(function()
		while folder.Parent do
			task.wait(0.1)
			if progress.installingBy ~= nil then
				broadcast()
			end
		end
	end)

	return {
		folder = folder,
		fuses = fuses,
		getProgress = function(): EscapeLogic.Progress
			return progress
		end,
		tick = tick,
		handleCollect = function(player: Player, fuseId: number)
			-- O cliente só manda um número. A prova de que o fusível existe é
			-- esta tabela do servidor (o modelo vivo), nunca o cliente.
			local model = fuseModels[fuseId]
			if model == nil or not model.Parent then
				return
			end

			collect(player, model)
		end,
		handleInstallStart = function(player: Player)
			-- `startInstall` já valida tudo (inclusive se ESTE jogador tem
			-- fusível na mão); aqui só evitamos trabalho desnecessário.
			if progress.holders[player.UserId] == nil then
				return
			end
			startInstall(player)
		end,
		handleCancel = function(player: Player)
			cancelInstall(player)
		end,
		reset = function()
			-- (usado se o mapa for reconstruído)
			progress = EscapeLogic.newProgress()
			broadcast()
		end,
	}
end

return EscapeService

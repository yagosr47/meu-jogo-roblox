--!strict
-- Estado da corrida por jogador + validação das RemoteEvents.
--
-- REGRA DE OURO: o cliente é sempre suspeito. Nada que ele envia é usado como
-- verdade; ele só aponta "quero pegar o checkpoint X" e o servidor confere
-- estado, ordem, distância real e ritmo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local RaceLogic = require(shared.RaceLogic)
local Remotes = require(shared.Remotes)
local LeaderboardStore = require(shared.LeaderboardStore)

local CourseBuilder = require(script.Parent.CourseBuilder)
local RaceServerLogic = require(script.Parent.RaceServerLogic)

type Session = {
	phase: RaceLogic.Phase,
	startedAt: number,
	lastClaimAt: number,
	nextIndex: number,
	recentClaims: { number },
	finishedAt: number?,
	lastStartAt: number,
	callTimestamps: { number },
	conns: { RBXScriptConnection },
}

local RaceService = {}

local sessions: { [Player]: Session } = {}
local course: CourseBuilder.Course
local remoteFolder: Folder
local leaderboard: LeaderboardStore.Store
local store: DataStore? = nil
local saveQueued = false

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------

local function now(): number
	return os.clock()
end

local function newSession(): Session
	return {
		phase = "Idle",
		startedAt = 0,
		lastClaimAt = 0,
		nextIndex = 1,
		recentClaims = {},
		finishedAt = nil,
		lastStartAt = 0,
		callTimestamps = {},
		conns = {},
	}
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

--- Rate limit global por jogador: qualquer remote passa por aqui primeiro.
--- O jogador está fisicamente no pad de largada? (medido no servidor)
local function isOnStartPad(player: Player): boolean
	local root = getHumanoidRootPart(player)
	if not root then
		return false
	end

	return (root.Position - course.startPad.Position).Magnitude <= Config.MAX_START_DISTANCE
end

--- Aplica a chegada: cancela o estado e registra no ranking.
--- Chamado tanto pela claim quanto pelo `cleanup` (rede de segurança).
local function onFinished(player: Player, session: Session, elapsed: number)
	session.phase = "Finished"
	session.finishedAt = elapsed
	session.nextIndex = Config.CHECKPOINT_COUNT + 1

	local entered, position = leaderboard:add(player.Name, elapsed)

	Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.RACE_FINISHED):FireClient(player, {
		time = elapsed,
		formatted = RaceLogic.formatTime(elapsed),
		position = position,
		entered = entered,
	})

	broadcastLeaderboard()

	if entered then
		notify(player, string.format("Chegou! %s (posição %d)", RaceLogic.formatTime(elapsed), position or 0), Color3.fromRGB(90, 220, 120))
	else
		notify(player, string.format("Chegou em %s!", RaceLogic.formatTime(elapsed)), Color3.fromRGB(90, 220, 120))
	end

	pushState(player, session)
end

local function isFlooding(session: Session): boolean
	local t = now()
	session.callTimestamps = RaceLogic.pruneClaims(session.callTimestamps, t, 1)

	if #session.callTimestamps >= Config.MAX_REMOTE_CALLS_PER_SECOND then
		return true
	end

	table.insert(session.callTimestamps, t)
	return false
end

local function pushState(player: Player, session: Session)
	local event = Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.RACE_STATE)
	event:FireClient(player, {
		phase = session.phase,
		nextIndex = session.nextIndex,
		totalCheckpoints = Config.CHECKPOINT_COUNT,
		startedAt = session.startedAt,
		serverNow = now(),
		finishedAt = session.finishedAt,
	})

	-- Destaque puramente visual; o valor vem do estado do servidor.
	CourseBuilder.highlight(course, player, if session.phase == "Running" or session.phase == "Countdown" then session.nextIndex else 1)
end

local function notify(player: Player, message: string, color: Color3?)
	Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.NOTIFY):FireClient(player, message, color)
end

local function broadcastLeaderboard()
	local event = Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.LEADERBOARD)
	event:FireAllClients(leaderboard:getEntries())
end

local function resolvePlayer(from: Player?): Player?
	-- `from` vem do próprio motor (Engine), não do conteúdo da mensagem.
	if typeof(from) == "Instance" and from:IsA("Player") then
		return from
	end
	return nil
end

-- ----------------------------------------------------------------------
-- Largada
-- ----------------------------------------------------------------------

local function startRace(player: Player, session: Session)
	local t = now()

	if session.phase == "Countdown" or session.phase == "Running" then
		notify(player, "Você já está em uma corrida.", Color3.fromRGB(255, 170, 0))
		return
	end

	if t - session.lastStartAt < Config.START_COOLDOWN then
		notify(player, "Aguarde alguns segundos para largar de novo.", Color3.fromRGB(255, 170, 0))
		return
	end

	local root = getHumanoidRootPart(player)
	if not root then
		notify(player, "Seu personagem não está pronto.", Color3.fromRGB(255, 90, 90))
		return
	end

	-- O cliente NÃO diz onde está: o servidor mede a posição real.
	-- Sem isso, bastaria chamar RequestStart de qualquer lugar para burlar
	-- a largada.
	if not isOnStartPad(player) then
		notify(player, "Vá até o pad verde de largada.", Color3.fromRGB(255, 90, 90))
		return
	end

	session.lastStartAt = t
	session.phase = "Countdown"
	session.nextIndex = 1
	session.startedAt = 0
	session.lastClaimAt = 0
	session.recentClaims = {}
	session.finishedAt = nil

	pushState(player, session)

	task.delay(Config.COUNTDOWN_SECONDS, function()
		-- Reconfere no fim da contagem: jogador pode ter saído, morrido ou
		-- cancelado nesse meio tempo.
		if not player.Parent then
			return
		end
		if session.phase ~= "Countdown" then
			return
		end
		if not getHumanoidRootPart(player) then
			session.phase = "Idle"
			notify(player, "Largada cancelada.", Color3.fromRGB(255, 170, 0))
			pushState(player, session)
			return
		end

		session.phase = "Running"
		session.startedAt = now()
		pushState(player, session)
		notify(player, "Valendo! Passe pelos checkpoints em ordem.", Color3.fromRGB(90, 220, 120))
	end)
end

-- ----------------------------------------------------------------------
-- Claims
-- ----------------------------------------------------------------------

local function claimCheckpoint(player: Player, session: Session, claimed: any)
	local t = now()

	local root = getHumanoidRootPart(player)
	local alive = root ~= nil

	local claimedNumber = if type(claimed) == "number" then claimed else -1
	local checkpoint = if RaceLogic.isValidCheckpointIndex(claimedNumber, Config.CHECKPOINT_COUNT)
		then course.checkpoints[claimedNumber]
		else nil

	-- A distância é calculada com a posição REAL do personagem no servidor.
	local distance = math.huge
	if root and checkpoint then
		distance = (root.Position - checkpoint.position).Magnitude
	end

	local context = RaceServerLogic.buildContext({
		phase = session.phase,
		progression = {
			nextIndex = session.nextIndex,
			lastClaimAt = session.lastClaimAt,
			startedAt = session.startedAt,
			recentClaims = session.recentClaims,
		},
		claimed = claimedNumber,
		distance = distance,
		alive = alive,
		now = t,
		total = Config.CHECKPOINT_COUNT,
	})

	local verdict = RaceLogic.evaluateClaim(context)
	if not verdict.accepted then
		-- Não dá dica fina de anti-cheat (distância exata, etc.) para o cliente.
		if verdict.reason ~= "Checkpoint fora de ordem" and not string.find(verdict.reason, "Checkpoint fora de ordem", 1, true) then
			notify(player, "Checkpoint não validado.", Color3.fromRGB(255, 90, 90))
		end
		pushState(player, session)
		return
	end

	local updated, outcome = RaceServerLogic.applyClaim(
		{
			nextIndex = session.nextIndex,
			lastClaimAt = session.lastClaimAt,
			startedAt = session.startedAt,
			recentClaims = session.recentClaims,
		},
		claimedNumber,
		Config.CHECKPOINT_COUNT,
		t
	)

	session.nextIndex = updated.nextIndex
	session.lastClaimAt = updated.lastClaimAt
	session.recentClaims = updated.recentClaims

	if outcome.finished then
		onFinished(player, session, outcome.elapsed)
		-- O checkpoints na ordem: o último só fecha se o jogador já
		-- passou por todos (garantido por `evaluateClaim`).
	else
		notify(player, string.format("Checkpoint %d/%d", claimedNumber, Config.CHECKPOINT_COUNT), Color3.fromRGB(90, 200, 255))
		pushState(player, session)
	end
end

-- ----------------------------------------------------------------------
-- Ciclo de vida
-- ----------------------------------------------------------------------

function RaceService.start()
	remoteFolder = Remotes.createServerSide(ReplicatedStorage)

	-- DataStore é opcional: se a API estiver desligada (Studio sem API,
	-- ou teste local), o ranking continua funcionando em memória.
	if Config.USE_DATASTORE then
		local ok, dataStoreService = pcall(function()
			return game:GetService("DataStoreService")
		end)
		if ok and dataStoreService then
			local okStore, result = pcall(function()
				return dataStoreService:GetDataStore("RaceLeaderboard_v1")
			end)
			if okStore then
				store = result
			else
				warn("[RaceService] DataStore indisponível, ranking em memória:", result)
			end
		end
	end

	leaderboard = LeaderboardStore.new(if store then {
		load = function()
			local ok, data = pcall(function()
				return store:GetAsync("top")
			end)
			if ok then
				return data
			end
			warn("[RaceService] falha ao carregar ranking:", data)
			return nil
		end,
		save = function(entries)
			-- Debounce: evita estourar o limite de escrita do DataStore.
			if saveQueued then
				return
			end
			saveQueued = true
			task.delay(2, function()
				saveQueued = false
				local ok, err = pcall(function()
					store:SetAsync("top", entries)
				end)
				if not ok then
					warn("[RaceService] falha ao salvar ranking:", err)
				end
			end)
		end,
	} else nil)

	course = CourseBuilder.build(Workspace)
	CourseBuilder.highlight(course, nil, 1)

	local requestStart = Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.REQUEST_START)
	local claimCheckpointRemote = Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.CLAIM_CHECKPOINT)
	local cancelRace = Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.CANCEL_RACE)

	requestStart.OnServerEvent:Connect(function(from: Player?)
		local player = resolvePlayer(from)
		if not player then
			return
		end

		local session = sessions[player]
		if not session then
			return
		end

		if isFlooding(session) then
			return
		end

		startRace(player, session)
	end)

	claimCheckpointRemote.OnServerEvent:Connect(function(from: Player?, claimed: any)
		local player = resolvePlayer(from)
		if not player then
			return
		end

		local session = sessions[player]
		if not session then
			return
		end

		if isFlooding(session) then
			return
		end

		claimCheckpoint(player, session, claimed)
	end)

	cancelRace.OnServerEvent:Connect(function(from: Player?)
		local player = resolvePlayer(from)
		if not player then
			return
		end

		local session = sessions[player]
		if not session then
			return
		end

		if isFlooding(session) then
			return
		end

		if session.phase ~= "Running" and session.phase ~= "Countdown" then
			return
		end

		session.phase = "Idle"
		session.nextIndex = 1
		session.recentClaims = {}
		session.finishedAt = nil
		notify(player, "Corrida cancelada.", Color3.fromRGB(255, 170, 0))
		pushState(player, session)
	end)

	--- Se o jogador morrer no meio da corrida, manda o tempo parcial para ele
	--- (não entra no ranking: a corrida não foi concluída).
	local function onPlayerDied(player: Player, session: Session)
		if session.phase ~= "Running" then
			return
		end

		local elapsed = now() - session.startedAt
		session.phase = "Idle"
		session.nextIndex = 1
		session.recentClaims = {}
		session.finishedAt = nil

		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.RACE_FINISHED):FireClient(player, {
			time = elapsed,
			formatted = RaceLogic.formatTime(elapsed),
			position = nil,
			entered = false,
			died = true,
		})

		notify(player, "Você morreu. Tempo parcial: " .. RaceLogic.formatTime(elapsed), Color3.fromRGB(255, 90, 90))
		pushState(player, session)
	end

	local function hookCharacter(player: Player, session: Session)
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid

		table.insert(session.conns, humanoid.Died:Connect(function()
			onPlayerDied(player, session)
		end))

		player.CharacterAdded:Connect(function()
			-- Novo personagem: o HUD volta ao estado neutro.
			if session.phase ~= "Running" then
				task.defer(pushState, player, session)
			end
		end)
	end

	local function onPlayerAdded(player: Player)
		if sessions[player] then
			return
		end

		local session = newSession()
		sessions[player] = session

		-- Liga a detecção de morte deste jogador.
		hookCharacter(player, session)

		-- Envia o ranking logo ao entrar.
		task.defer(function()
			if player.Parent then
				Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.LEADERBOARD):FireClient(player, leaderboard:getEntries())
				pushState(player, sessions[player])
			end
		end)
	end

	local function onPlayerRemoving(player: Player)
		local session = sessions[player]
		if session then
			for _, conn in session.conns do
				conn:Disconnect()
			end
			sessions[player] = nil
		end

		-- Se o jogador estava correndo, cancela a corrida dele.
		if session and session.phase == "Running" then
			session.phase = "Idle"
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	print(`[RaceService] Sistema de corrida iniciado com {Config.CHECKPOINT_COUNT} checkpoints.`)
end

--- Loop periódico do servidor (chamado a cada poucos segundos).
---
--- Faz três coisas:
---  1. Larga sozinho quem ficou parado no pad (conveniência). A distância é
---     conferida aqui E no fluxo do RemoteEvent.
---  2. Fecha a corrida de quem já está sobre o checkpoint final (rede de
---     segurança: alguma claim pode ter se perdido).
---  3. Encerra corridas que passaram do tempo limite.
function RaceService.cleanup()
	local t = now()

	for player, session in sessions do
		if not player.Parent then
			continue
		end

		if session.phase == "Idle" then
			if t - session.lastStartAt >= Config.START_COOLDOWN and isOnStartPad(player) then
				startRace(player, session)
			end
		elseif session.phase == "Running" then
			if (t - session.startedAt) > Config.RACE_TIME_LIMIT then
				session.phase = "Idle"
				session.nextIndex = 1
				notify(player, "Tempo esgotado. Volte ao pad de largada.", Color3.fromRGB(255, 90, 90))
				pushState(player, session)
				continue
			end

			-- Rede de segurança da chegada: só vale se o próximo checkpoint
			-- esperado for o último e o jogador estiver realmente sobre ele.
			if session.nextIndex == Config.CHECKPOINT_COUNT then
				local finish = course.checkpoints[Config.CHECKPOINT_COUNT]
				local root = getHumanoidRootPart(player)

				if finish and root then
					local distance = (root.Position - finish.position).Magnitude
					local elapsed = t - session.startedAt

					if distance <= Config.MAX_CLAIM_DISTANCE
						and (t - session.lastClaimAt) >= Config.MIN_SECONDS_PER_CHECKPOINT
						and elapsed > 0
					then
						onFinished(player, session, elapsed)
					end
				end
			end
		end
	end
end

return RaceService

--!strict
-- Monstro: patrulha (PathfindingService), detecção (raycast + som),
-- perseguição e captura.
--
-- TODA a decisão roda aqui. O cliente só recebe o estado para tocar música de
-- tensão e mostra o jumpscare quando o servidor avisa.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MonsterAI = require(ReplicatedStorage.Shared.MonsterAI)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)

local MonsterService = {}

export type Service = {
	start: () -> (),
	stop: () -> (),
}

local RAY_IGNORE = { "TerrorMap", "BatteryPickups", "Monster" }

--- Conta quantas amostras do caminho monstro->jogador batem em parede.
--- Devolve a fração bloqueada (0 = visão limpa).
local function obstructionRatio(fromVector: Vector3, toVector: Vector3, ignoreList: { Instance }): number
	local delta = toVector - fromVector
	local distance = delta.Magnitude
	if distance < 0.1 then
		return 0
	end

	local direction = delta.Unit
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.IgnoreWater = true

	local samples = math.clamp(math.floor(distance / 6), 1, 8)
	local blocked = 0

	for index = 1, samples do
		local alpha = index / (samples + 1)
		local origin = fromVector + delta * alpha
		-- Amostra em altura de "torso", não no chão.
		local result = Workspace:Raycast(origin, direction * 2, rayParams)
		if result then
			blocked += 1
		end
	end

	return blocked / samples
end

function MonsterService.start(): Service
	local remoteFolder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME) :: Folder
	local map = Workspace:FindFirstChild("TerrorMap")

	local root = map and map:FindFirstChild("Monster")
	if root then
		root:Destroy()
	end

	-- ------------------------------------------------------------------
	-- Modelo do monstro (construído em runtime)
	-- ------------------------------------------------------------------
	local model = Instance.new("Model")
	model.Name = "Monster"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 6, 2)
	body.Anchored = true
	body.CanCollide = true
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(14, 14, 18)
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2)
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(10, 10, 12)
	head.Parent = model

	local eyes = Instance.new("Part")
	eyes.Name = "Olhos"
	eyes.Size = Vector3.new(1.4, 0.25, 0.1)
	eyes.Anchored = true
	eyes.CanCollide = false
	eyes.Material = Enum.Material.Neon
	eyes.Color = Color3.fromRGB(255, 40, 40)
	eyes.Parent = model

	model.PrimaryPart = body
	model.Parent = Workspace

	local spawn = Vector3.new(Config.MONSTER_SPAWN[1], Config.MONSTER_SPAWN[2], Config.MONSTER_SPAWN[3])
	model:PivotTo(CFrame.new(spawn + Vector3.new(0, 3, 0)))

	local state = MonsterAI.new(MonsterAI.fromVector(spawn))
	local waypointIndex = 1
	local lastProgressAt = os.clock()
	local lastStateSentAt = 0
	local lastSentMode = ""

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	-- Cache de caminho: ComputeAsync é caro, então recalculamos só a cada
	-- MONSTER_PATH_RECOMPUTE segundos (ou quando o destino mudou muito).
	local cachedPath: { Vector3 } = {}
	local cachedAt = 0
	local cachedGoal: Vector3? = nil

	local function getPath(goal: Vector3): { Vector3 }
		local now = os.clock()
		local goalMoved = cachedGoal == nil or (goal - cachedGoal :: Vector3).Magnitude > 6

		if #cachedPath > 0 and not goalMoved and (now - cachedAt) < Config.MONSTER_PATH_RECOMPUTE then
			return cachedPath
		end

		local points: { Vector3 } = {}
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 6,
			AgentCanJump = false,
		})

		local ok = pcall(function()
			path:ComputeAsync(model:GetPivot().Position, goal)
		end)

		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
		end

		cachedPath = points
		cachedAt = now
		cachedGoal = goal
		return points
	end

	-- ------------------------------------------------------------------
	-- Estado replicado (só o necessário para FX/som)
	-- ------------------------------------------------------------------
	local function broadcastState(force: boolean?)
		local now = os.clock()
		if not force and (now - lastStateSentAt) < 0.5 and state.mode == lastSentMode then
			return
		end
		lastStateSentAt = now
		lastSentMode = state.mode

		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.MONSTER_STATE):FireAllClients({
			mode = state.mode,
			position = { state.position.x, state.position.y, state.position.z },
			targetName = state.targetName,
		})
	end

	-- ------------------------------------------------------------------
	-- Movimento
	-- ------------------------------------------------------------------
	local function moveTowards(targetVector: Vector3, speed: number, dt: number)
		local current = model:GetPivot().Position
		local delta = targetVector - current
		delta = Vector3.new(delta.X, 0, delta.Z)

		if delta.Magnitude < 0.5 then
			return false
		end

		-- Sem "teletransporte": limita o passo pelo dt.
		local maxStep = speed * dt
		local direction = delta.Unit
		local target = current + direction * math.min(maxStep, delta.Magnitude)

		local look = CFrame.lookAt(target + Vector3.new(0, 3, 0), target + Vector3.new(0, 3, 0) + direction)
		model:PivotTo(look)

		head.CFrame = look * CFrame.new(0, 4, 0)
		eyes.CFrame = look * CFrame.new(0, 4.3, -1.02)

		return true
	end

	-- ------------------------------------------------------------------
	-- Loop principal
	-- ------------------------------------------------------------------
	local connection: RBXScriptConnection

	local function step(dt: number)
		local now = os.clock()

		-- A posição pura sempre parte de onde o modelo está de fato.
		state.position = MonsterAI.fromVector(model:GetPivot().Position)

		-- 1. Amostra dos jogadores (posição real + o que o servidor sabe).
		local ignoreList: { Instance } = {}
		for _, name in RAY_IGNORE do
			local found = Workspace:FindFirstChild(name)
			if found then
				table.insert(ignoreList, found)
			end
		end

		local samples: { MonsterAI.PlayerSample } = {}
		local playersByUserId: { [number]: Player } = {}

		for _, player in Players:GetPlayers() do
			local playerState = PlayerState.get(player)
			if not playerState then
				continue
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local charRoot = character and character:FindFirstChild("HumanoidRootPart")

			if not character or not humanoid or not charRoot or not charRoot:IsA("BasePart") then
				continue
			end

			local alive = humanoid.Health > 0

			local sample: MonsterAI.PlayerSample = {
				userId = player.UserId,
				name = player.Name,
				position = MonsterAI.fromVector(charRoot.Position),
				isSprinting = PlayerState.isSprinting(player),
				isMoving = playerState.moving,
				obstructionRatio = obstructionRatio(
					Vector3.new(state.position.x, state.position.y + 4, state.position.z),
					charRoot.Position,
					ignoreList
				),
				alive = alive,
				isCaught = playerState.isCaught,
			}

			table.insert(samples, sample)
			playersByUserId[player.UserId] = player
		end

		-- 2. Decide perseguição (só pode haver 1 caçado por vez).
		local previousMode = state.mode
		state, _ = MonsterAI.updateChase(state, samples, now)

		-- `updateChase` já garante um único alvo por vez.

		-- 3. Movimento.
		local speed = MonsterAI.speedFor(state.mode)

		if state.mode == "Chase" and state.targetUserId then
			local targetPlayer = playersByUserId[state.targetUserId]
			local targetState = targetPlayer and PlayerState.get(targetPlayer)
			local character = targetPlayer and targetPlayer.Character
			local charRoot = character and character:FindFirstChild("HumanoidRootPart")

			if charRoot and charRoot:IsA("BasePart") then
				local goal = charRoot.Position
				local points = getPath(goal)

				if #points > 1 then
					-- Vai para o próximo ponto do caminho.
					local nextPoint = points[2]
					moveTowards(nextPoint, speed, dt)
				else
					-- Sem caminho: perseguição direta (linha reta).
					moveTowards(goal, speed, dt)
				end

				-- 4. Captura (distância medida no servidor).
				if targetState and MonsterAI.canCatch(state, {
					userId = state.targetUserId,
					name = state.targetName or "",
					position = MonsterAI.fromVector(charRoot.Position),
					isSprinting = PlayerState.isSprinting(targetPlayer),
					isMoving = targetState.moving,
					obstructionRatio = 0,
					alive = true,
					isCaught = targetState.isCaught,
				}, now) then
					state.lastSwingAt = now

					PlayerState.setCaught(targetState, true, now)
					targetState.stamina.stamina = 0
					targetState.stamina.exhausted = true
					PlayerState.applySpeed(targetState)

					Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.CAUGHT):FireClient(targetPlayer, {
						monster = state.targetName or "Algo",
					})

					broadcastState(true)
				end
			end
		else
			-- Patrulha: vai de waypoint em waypoint.
			local waypoints = Config.MONSTER_WAYPOINTS
			local target = waypoints[waypointIndex]
			if not target then
				waypointIndex = 1
				target = waypoints[1]
			end

			local targetVector = Vector3.new(target[1], target[2], target[3])
			local reached = false

			local points = getPath(targetVector)

			if #points > 1 then
				local nextPoint = points[2]
				if moveTowards(nextPoint, speed, dt) then
					lastProgressAt = now
				end
			else
				moveTowards(targetVector, speed, dt)
			end

			local flatTarget = Vector3.new(targetVector.X, model:GetPivot().Position.Y, targetVector.Z)
			if (model:GetPivot().Position - flatTarget).Magnitude <= Config.MONSTER_WAYPOINT_TOLERANCE then
				reached = true
			end

			if reached then
				lastProgressAt = now
				waypointIndex = MonsterAI.nextWaypointIndex(waypointIndex, #waypoints)
			end
		end

		-- 5. Replica o estado (posição já sincronizada acima).
		if state.mode ~= previousMode then
			broadcastState(true)
		else
			broadcastState(false)
		end

		-- Reposiciona olhos/cabeça mesmo parado.
		local pivot = model:GetPivot()
		head.CFrame = pivot * CFrame.new(0, 4, 0)
		eyes.CFrame = pivot * CFrame.new(0, 4.3, -1.02)
	end

	-- Pathfinding a cada frame é caro; o movimento anda em passos curtos
	-- (Heartbeat com dt real) e o caminho é recalculado no ritmo do Config.
	local accum = 0
	local stepInterval = 1 / 20

	connection = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < stepInterval then
			return
		end
		local stepDt = accum
		accum = 0

		local ok, err = pcall(step, math.min(stepDt, 0.25))
		if not ok then
			warn("[MonsterService] erro no passo da IA:", err)
		end
	end)

	-- Recuperação: se o monstro ficar preso, volta ao spawn.
	task.spawn(function()
		while connection.Connected do
			task.wait(5)
			if MonsterAI.needsRespawn(state, MonsterAI.fromVector(spawn), os.clock(), lastProgressAt) then
				model:PivotTo(CFrame.new(spawn + Vector3.new(0, 3, 0)))
				state = MonsterAI.new(MonsterAI.fromVector(spawn))
				lastProgressAt = os.clock()
				broadcastState(true)
			end
		end
	end)

	broadcastState(true)
	print("[MonsterService] Monstro ativo.")

	return {
		start = function() end,
		stop = function()
			if connection then
				connection:Disconnect()
			end
			model:Destroy()
		end,
	}
end

return MonsterService

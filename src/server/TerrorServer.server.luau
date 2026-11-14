--!strict
-- Entrada do servidor: monta o mapa, cria os remotes e liga os três sistemas.
--
-- Ordem importa: o mapa precisa existir antes dos serviços que procuram
-- `Workspace.TerrorMap`, e os remotes antes de qualquer FireClient.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local Remotes = require(shared.Remotes)
local StaminaLogic = require(shared.StaminaLogic)
local FlashlightLogic = require(shared.FlashlightLogic)

local FlashlightService = require(script.Parent.FlashlightService)
local MapBuilder = require(script.Parent.MapBuilder)
local MonsterService = require(script.Parent.MonsterService)
local EscapeService = require(script.Parent.EscapeService)
local PlayerState = require(script.Parent.PlayerState)

-- 1. Mapa e atmosfera.
local map = MapBuilder.build(Workspace)
MapBuilder.applyAtmosphere()

-- Pontos de spawn das pilhas (invisíveis, só referência).
do
	local points = Instance.new("Folder")
	points.Name = "PickupPoints"
	points.Parent = map.folder

	for index, position in map.pickupPoints do
		local marker = Instance.new("Part")
		marker.Name = "Point" .. index
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Transparency = 1
		marker.Size = Vector3.new(1, 1, 1)
		marker.Position = position
		marker.Parent = points
	end
end

-- 2. Remotes.
local remoteFolder = Remotes.createServerSide(ReplicatedStorage)

-- 3. Serviços.
local flashlight = FlashlightService.start()
flashlight.spawnInitial()

local monster = MonsterService.start()
local escape = EscapeService.start()

-- ----------------------------------------------------------------------
-- Estado replicado ao cliente
-- ----------------------------------------------------------------------

local function replicate(player: Player)
	local state = PlayerState.get(player)
	if not state then
		return
	end

	Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.STATE):FireClient(player, {
		stamina = state.stamina.stamina,
		maxStamina = Config.STAMINA_MAX,
		sprinting = state.stamina.sprinting,
		exhausted = state.stamina.exhausted,
		tired = StaminaLogic.isTired(state.stamina),
		battery = state.flashlight.battery,
		maxBattery = Config.BATTERY_MAX,
		flashlightOn = state.flashlight.on,
		batteryLow = FlashlightLogic.isLow(state.flashlight.battery),
	})
end

-- ----------------------------------------------------------------------
-- Ciclo de vida dos jogadores
-- ----------------------------------------------------------------------

local function applyHumanoid(state: PlayerState.State)
	local character = state.player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = Config.WALK_SPEED
	humanoid.JumpPower = Config.JUMP_POWER
	humanoid:SetAttribute("Sprinting", false)
	PlayerState.applySpeed(state)
end

local function onCharacterAdded(player: Player, character: Model)
	local state = PlayerState.get(player)
	if not state then
		return
	end

	-- Morrer não deve deixar o jogador "pego" para sempre.
	PlayerState.setCaught(state, false, os.clock())
	PlayerState.clearMovement(player)

	-- Respawn é um estado limpo: sem Shift grudado, sem lanterna ligada
	-- drenando bateria enquanto o jogador está morto.
	state.sprinting = false
	state.moving = false
	FlashlightLogic.apply(state.flashlight, {
		on = false,
		battery = state.flashlight.battery,
		lastToggleAt = state.flashlight.lastToggleAt,
	})

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		applyHumanoid(state)

		humanoid.Died:Connect(function()
			PlayerState.setCaught(state, false, os.clock())
			-- Ao morrer, a estamina volta (é um respawn limpo).
			state.stamina = StaminaLogic.new()
			state.sprinting = false
			PlayerState.applySpeed(state)
		end)
	end

	replicate(player)
end

local function onPlayerAdded(player: Player)
	local state = PlayerState.create(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	-- Estado inicial logo que possível.
	task.defer(function()
		if player.Parent then
			replicate(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	PlayerState.remove(player)
	PlayerState.clearMovement(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- ----------------------------------------------------------------------
-- RemoteEvents (cliente -> servidor)
-- ----------------------------------------------------------------------

Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.SET_SPRINTING).OnServerEvent:Connect(function(from: Player?, declared: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state then
		return
	end

	local now = os.clock()

	-- O servidor NÃO aceita "estou correndo" como verdade absoluta: ele
	-- confere se o jogador realmente pode correr (estamina/cansaço) e é ele
	-- quem aplica a velocidade.
	local wantsSprint = declared == true
	if wantsSprint and not StaminaLogic.canSprint(state.stamina) then
		wantsSprint = false
	end

	-- O limite de chamadas existe contra spam, mas NUNCA pode engolir o
	-- "soltar o Shift": sem isso o jogador fica preso correndo para sempre
	-- (o cliente já parou de mandar, o servidor acha que ele ainda corre).
	-- Pedidos de PARAR são sempre aceitos.
	if wantsSprint and PlayerState.isFlooding(state, now) then
		return
	end

	state.sprinting = wantsSprint
	PlayerState.applySpeed(state)
	replicate(from)
end)

Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.SET_FLASHLIGHT).OnServerEvent:Connect(function(from: Player?, desired: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state then
		return
	end

	if PlayerState.isFlooding(state, os.clock()) then
		return
	end

	flashlight.handleToggle(from, desired)
end)

Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.REQUEST_PICKUP).OnServerEvent:Connect(function(from: Player?, pickup: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state then
		return
	end

	if PlayerState.isFlooding(state, os.clock()) then
		return
	end

	flashlight.handlePickup(from, pickup)
end)

-- Ping de áudio do monstro para os outros jogadores (o cliente pede, o
-- servidor decide se vale a pena repassar).
Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.MONSTER_SOUND).OnServerEvent:Connect(function(from: Player?, kind: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state or PlayerState.isFlooding(state, os.clock()) then
		return
	end

	if type(kind) ~= "string" or #kind > 32 then
		return
	end

	Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.MONSTER_NEAR):FireAllClients({
		kind = kind,
		player = from.Name,
	})
end)

-- ----------------------------------------------------------------------
-- Objetivo de fuga (cliente -> servidor, tudo validado no EscapeService)
-- ----------------------------------------------------------------------

Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.COLLECT_FUSE).OnServerEvent:Connect(function(from: Player?, fuseId: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state or PlayerState.isFlooding(state, os.clock()) then
		return
	end

	if type(fuseId) ~= "number" or fuseId ~= fuseId or fuseId % 1 ~= 0 then
		return
	end

	if fuseId < 1 or fuseId > Config.FUSE_COUNT then
		return
	end

	escape.handleCollect(from, fuseId)
end)

Remotes.getServerSide(remoteFolder, Remotes.CLIENT_TO_SERVER.INSTALL_FUSE).OnServerEvent:Connect(function(from: Player?, action: any)
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end

	local state = PlayerState.get(from)
	if not state or PlayerState.isFlooding(state, os.clock()) then
		return
	end

	-- O cliente só diz "começar" ou "desistir"; o tempo e a distância são
	-- medidos no servidor.
	if action == "start" then
		escape.handleInstallStart(from)
	elseif action == "cancel" then
		escape.handleCancel(from)
	end
end)

-- ----------------------------------------------------------------------
-- Loop autoritativo (estamina + bateria)
-- ----------------------------------------------------------------------

local STAMINA_TICK = 1 / 10
local accum = 0

RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < STAMINA_TICK then
		return
	end

	local stepDt = math.min(accum, 0.5)
	accum = 0
	local now = os.clock()

	for player, state in PlayerState.all() do
		if not player.Parent then
			continue
		end

		PlayerState.updateMovement(player, state)

		if state.isCaught then
			if now >= state.caughtUntil then
				-- Fim do jumpscare: o monstro "elimina" o jogador.
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")

				PlayerState.setCaught(state, false, now)
				state.stamina = StaminaLogic.new()

				if humanoid and humanoid.Health > 0 then
					humanoid.Health = 0 -- respawn limpo no SpawnLocation do mapa
				end

				Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.RESET):FireClient(player)
				replicate(player)
			end
			PlayerState.applySpeed(state)
			continue
		end

		local newStamina, changed = StaminaLogic.step(state.stamina, stepDt, {
			sprinting = state.sprinting,
			moving = state.moving,
		}, now)

		-- Aplica no lugar: `applySpeed`/`isSprinting` leem este mesmo objeto.
		local fresh = StaminaLogic.apply(state.stamina, newStamina)

		-- Se a estamina acabou, o servidor corta a corrida na hora.
		if state.stamina.exhausted and state.sprinting then
			state.sprinting = false
			PlayerState.applySpeed(state)
			replicate(player)
		elseif changed then
			PlayerState.applySpeed(state)
			replicate(player)
		end
	end

	local ok, err = pcall(flashlight.tick, stepDt, now)
	if not ok then
		warn("[TerrorServer] erro na lanterna:", err)
	end

	-- Instalação dos fusíveis: quem conta os 3 s é este tick.
	local okEscape, errEscape = pcall(escape.tick, now)
	if not okEscape then
		warn("[TerrorServer] erro na fuga:", errEscape)
	end

	local okCleanup, errCleanup = pcall(PlayerState.cleanup)
	if not okCleanup then
		warn("[TerrorServer] erro na limpeza:", errCleanup)
	end
end)

print(string.format(
	"[TerrorServer] Pronto. Estamina %.0f, bateria %.0f, monstro %s, %d fusíveis.",
	Config.STAMINA_MAX,
	Config.BATTERY_MAX,
	monster and "ativo" or "inativo",
	Config.FUSE_COUNT
))

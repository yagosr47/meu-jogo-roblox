--!strict
-- Lanterna + pilhas coletáveis.
--
-- Todo o estado de bateria é do servidor. O cliente só:
--   * pede para ligar/desligar (validado por cooldown e bateria),
--   * pede para pegar uma pilha (validado por distância e limite de ritmo),
--   * desenha a SpotLight e a piscada com a MESMA função pura do servidor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FlashlightLogic = require(ReplicatedStorage.Shared.FlashlightLogic)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)

local FlashlightService = {}

export type Service = {
	folder: Folder,
	handleToggle: (player: Player, on: any) -> (),
	handlePickup: (player: Player, pickup: any) -> (),
	tick: (dt: number, now: number) -> (),
	spawnInitial: () -> (),
}

local function makePickup(position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "BatteryPickup"

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(0.9, 1.9, 0.9)
	core.Position = position + Vector3.new(0, 1, 0)
	core.Anchored = true
	core.CanCollide = false
	core.Material = Enum.Material.Metal
	core.Color = Color3.fromRGB(60, 200, 110)
	core.Parent = model

	local top = Instance.new("Part")
	top.Name = "Topo"
	top.Size = Vector3.new(0.4, 0.3, 0.4)
	top.Position = core.Position + Vector3.new(0, 1.05, 0)
	top.Anchored = true
	top.CanCollide = false
	top.Material = Enum.Material.Metal
	top.Color = Color3.fromRGB(220, 220, 220)
	top.Parent = model

	local light = Instance.new("PointLight")
	light.Brightness = 0.7
	light.Range = 8
	light.Color = Color3.fromRGB(90, 255, 150)
	light.Parent = core

	-- O prompt só SINALIZA; quem decide é o servidor.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pegar pilha"
	prompt.ObjectText = "Pilha"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = core

	model:SetPivot(CFrame.new(position))

	local primary = core
	model.PrimaryPart = primary

	model.Parent = parent
	return model
end

--- Inicia o serviço: cria a pasta de pilhas e liga os handlers.
function FlashlightService.start(): Service
	local existingFolder = Workspace:FindFirstChild("BatteryPickups")
	local pickupFolder: Folder
	if existingFolder and existingFolder:IsA("Folder") then
		pickupFolder = existingFolder
	else
		if existingFolder then
			existingFolder:Destroy()
		end
		pickupFolder = Instance.new("Folder")
		pickupFolder.Name = "BatteryPickups"
		pickupFolder.Parent = Workspace
	end

	local remoteFolder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME) :: Folder

	-- Declaracoes antecipadas: `tryPickup` chama `collectPickup` e o respawn
	-- chama `spawnPickup`, mas os dois so' sao definidos mais abaixo.
	local collectPickup: (Player, Model) -> ()
	local spawnPickup: (Vector3) -> ()

	local function replicate(player: Player)
		local state = PlayerState.get(player)
		if not state then
			return
		end

		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.STATE):FireClient(player, {
			battery = state.flashlight.battery,
			flashlightOn = state.flashlight.on,
			low = FlashlightLogic.isLow(state.flashlight.battery),
		})
	end

	--- Lê os marcadores invisíveis criados junto do mapa.
	local function collectPoints(): { Vector3 }
		local points: { Vector3 } = {}

		local map = Workspace:FindFirstChild("TerrorMap")
		local markers = map and map:FindFirstChild("PickupPoints")
		if not markers then
			return points
		end

		for _, marker in markers:GetChildren() do
			if marker:IsA("BasePart") then
				table.insert(points, marker.Position)
			end
		end

		return points
	end

	--- Valida e coleta. Devolve true se a pilha foi consumida.
	local function tryPickup(player: Player, model: Model): boolean
		local state = PlayerState.get(player)
		if not state or state.isCaught then
			return false
		end

		if model.Name ~= "BatteryPickup" or model.Parent ~= pickupFolder then
			return false
		end

		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return false
		end

		-- Distância medida AQUI, nunca enviada pelo cliente.
		local distance = (root.Position - model:GetPivot().Position).Magnitude
		if distance > Config.BATTERY_PICKUP_MAX_DISTANCE then
			return false
		end

		local now = os.clock()
		local recent: { number } = {}
		for _, timestamp in state.pickupTimestamps do
			if (now - timestamp) <= 60 then
				table.insert(recent, timestamp)
			end
		end
		state.pickupTimestamps = recent

		if #recent >= Config.BATTERY_PICKUP_MAX_PER_MINUTE then
			return false
		end

		table.insert(state.pickupTimestamps, now)
		collectPickup(player, model)
		return true
	end

	--- Recarrega de fato e repõe a pilha. Só chamar depois de validar.
	function collectPickup(player: Player, model: Model)
		local state = PlayerState.get(player)
		if not state then
			return
		end

		local newFlashlight, gained = FlashlightLogic.recharge(state.flashlight, Config.BATTERY_PICKUP_AMOUNT)
		if gained <= 0 then
			Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.PICKUP_RESULT):FireClient(player, {
				ok = false,
				reason = "cheia",
			})
			return
		end

		FlashlightLogic.apply(state.flashlight, newFlashlight)
		state.lastBatteryStep = FlashlightLogic.toStep(newFlashlight.battery)

		Remotes.getServerSide(remoteFolder, Remotes.SERVER_TO_CLIENT.PICKUP_RESULT):FireClient(player, {
			ok = true,
			gained = gained,
			battery = newFlashlight.battery,
		})

		replicate(player)
		PlayerState.applySpeed(state)

		model:Destroy()

		task.delay(Config.BATTERY_PICKUP_RESPAWN, function()
			if not pickupFolder.Parent then
				return
			end

			local points = collectPoints()

			if #points > 0 then
				spawnPickup(points[math.random(1, #points)])
			end
		end)
	end

	function spawnPickup(position: Vector3)
		local model = makePickup(position, pickupFolder)

		local core = model:FindFirstChild("Core")
		local prompt = core and core:FindFirstChildOfClass("ProximityPrompt")

		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				-- A validação fica no `tryPickup`, para o prompt e o
				-- RemoteEvent usarem exatamente o mesmo caminho.
				local ok = tryPickup(player, model)
				if not ok then
					return
				end
			end)
		end
	end

	local function spawnInitial()
		for child in pickupFolder:GetChildren() do
			child:Destroy()
		end

		local points = collectPoints()

		if #points == 0 then
			warn("[FlashlightService] nenhum ponto de pilha encontrado (TerrorMap.PickupPoints)")
			return
		end

		for index = 1, math.min(Config.BATTERY_PICKUP_MAX, #points) do
			spawnPickup(points[index])
		end
	end

	--- Liga/desliga a lanterna.
	local function handleToggle(player: Player, on: any)
		local state = PlayerState.get(player)
		if not state or state.isCaught then
			return
		end

		local now = os.clock()

		local desired = on
		if type(desired) ~= "boolean" then
			desired = not state.flashlight.on
		end

		if desired == state.flashlight.on then
			return
		end

		-- Usa a MESMA regra do jogo (anti-spam + bateria).
		local toggled = state.flashlight
		if FlashlightLogic.canToggle(toggled, now) == false then
			return
		end

		if desired then
			if FlashlightLogic.isDead(state.flashlight.battery) then
				replicate(player)
				return
			end
			FlashlightLogic.apply(state.flashlight, {
				on = true,
				battery = state.flashlight.battery,
				lastToggleAt = now,
			})
		else
			FlashlightLogic.apply(state.flashlight, {
				on = false,
				battery = state.flashlight.battery,
				lastToggleAt = now,
			})
		end

		replicate(player)
		PlayerState.applySpeed(state)
	end

	--- Pedido de pilha por RemoteEvent (mesmo caminho do ProximityPrompt).
	local function handlePickup(player: Player, pickup: any)
		if typeof(pickup) ~= "Instance" or not pickup:IsA("Model") then
			return
		end

		tryPickup(player, pickup)
	end

	--- Tick do servidor: consome bateria e replica de forma econômica.
	local function tick(dt: number, now: number)
		for player, state in PlayerState.all() do
			if not player.Parent then
				continue
			end

			local before = state.flashlight
			local newFlashlight, changed = FlashlightLogic.step(before, dt, now)
			-- Aplica no lugar: a HUD e o `PlayerState` leem esta referência.
			FlashlightLogic.apply(state.flashlight, newFlashlight)

			local step = FlashlightLogic.toStep(newFlashlight.battery)
			local crossedLow = FlashlightLogic.isLow(newFlashlight.battery) ~= FlashlightLogic.isLow(before.battery)

			-- Replica só em mudança de passo (2%), de estado ou na virada do
			-- "bateria baixa" — evita um remote por frame.
			if changed or crossedLow or step ~= state.lastBatteryStep then
				state.lastBatteryStep = step
				replicate(player)
				PlayerState.applySpeed(state)
			end
		end
	end

	return {
		folder = pickupFolder,
		handleToggle = handleToggle,
		handlePickup = handlePickup,
		tick = tick,
		spawnInitial = spawnInitial,
	}
end

return FlashlightService

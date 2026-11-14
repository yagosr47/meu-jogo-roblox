--!strict
-- Estado autoritativo de cada jogador no servidor.
--
-- Aqui mora a regra: o SERVIDOR decide estamina, velocidade e bateria. O
-- cliente só declara intenção ("estou correndo", "liga a lanterna") e desenha.

local Players = game:GetService("Players")

local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(shared.Config)
local StaminaLogic = require(shared.StaminaLogic)
local FlashlightLogic = require(shared.FlashlightLogic)

local PlayerState = {}

export type State = {
	player: Player,
	stamina: StaminaLogic.State,
	flashlight: FlashlightLogic.State,
	sprinting: boolean,
	moving: boolean,
	lastInputAt: number,
	isCaught: boolean,
	caughtUntil: number,
	callTimestamps: { number },
	pickupTimestamps: { number },
	lastReplicatedStep: number,
	lastBatteryStep: number,
}

local states: { [Player]: State } = {}

function PlayerState.create(player: Player): State
	local state: State = {
		player = player,
		stamina = StaminaLogic.new(),
		flashlight = FlashlightLogic.new(),
		sprinting = false,
		moving = false,
		lastInputAt = 0,
		isCaught = false,
		caughtUntil = 0,
		callTimestamps = {},
		pickupTimestamps = {},
		lastReplicatedStep = StaminaLogic.toStep(Config.STAMINA_MAX),
		lastBatteryStep = FlashlightLogic.toStep(Config.BATTERY_MAX),
	}

	states[player] = state
	return state
end

function PlayerState.get(player: Player): State?
	return states[player]
end

function PlayerState.remove(player: Player)
	states[player] = nil
end

function PlayerState.all(): { [Player]: State }
	return states
end

--- Rate limit por jogador: quantas chamadas de remote por segundo.
function PlayerState.isFlooding(state: State, now: number): boolean
	local recent: { number } = {}
	for _, timestamp in state.callTimestamps do
		if (now - timestamp) <= 1 then
			table.insert(recent, timestamp)
		end
	end
	state.callTimestamps = recent

	if #recent >= Config.REMOTE_CALLS_PER_SECOND then
		return true
	end

	table.insert(recent, now)
	state.callTimestamps = recent
	return false
end

--- Habilita/desabilita o controle durante o jumpscare.
function PlayerState.setCaught(state: State, caught: boolean, now: number)
	state.isCaught = caught
	-- Congela só o tempo do jumpscare; depois o personagem morre (respawn).
	state.caughtUntil = if caught then now + Config.MONSTER_JUMPSCARE_SECONDS else 0
	state.sprinting = false
	state.moving = false
end

--- Aplica a velocidade que o servidor decidiu ao Humanoid.
function PlayerState.applySpeed(state: State)
	local character = state.player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local frozen = state.isCaught or humanoid.Health <= 0
	if frozen then
		humanoid.WalkSpeed = 0
		humanoid:SetAttribute("Sprinting", false)
		return
	end

	humanoid.WalkSpeed = StaminaLogic.speedFor(state.stamina, state.sprinting)
	humanoid:SetAttribute("Sprinting", state.sprinting)
	humanoid:SetAttribute("Stamina", state.stamina.stamina)
	humanoid:SetAttribute("Exhausted", state.stamina.exhausted)
	humanoid:SetAttribute("FlashlightOn", state.flashlight.on)
	humanoid:SetAttribute("Battery", state.flashlight.battery)
end

--- O monstro usa isso para saber se o jogador está correndo (som).
function PlayerState.isSprinting(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.sprinting and state.moving and not state.isCaught
end

--- Detecta se o jogador está se movendo, sem confiar no cliente:
--- compara a posição do HumanoidRootPart com a do último tick.
local lastPositions: { [Player]: Vector3 } = {}

function PlayerState.updateMovement(player: Player, state: State): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		state.moving = false
		return false
	end

	local previous = lastPositions[player]
	local current = root.Position
	lastPositions[player] = current

	if not previous then
		state.moving = false
		return false
	end

	local delta = current - previous
	state.moving = (Vector3.new(delta.X, 0, delta.Z)).Magnitude > 0.35
	return state.moving
end

function PlayerState.clearMovement(player: Player)
	lastPositions[player] = nil
end

--- Remove o estado de quem saiu do jogo.
function PlayerState.cleanup()
	for player in states do
		if not player.Parent then
			states[player] = nil
			lastPositions[player] = nil
		end
	end
end

return PlayerState

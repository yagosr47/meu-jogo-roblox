--!strict
-- Cérebro do monstro (puro, sem Instâncias).
--
-- TUDO o que decide "o monstro viu o jogador / ouviu o jogador / pegou o
-- jogador" está aqui e roda no servidor. O cliente só recebe o estado para
-- tocar música de tensão.
--
-- O raycast de linha de visão (PathfindingService/Raycast do Roblox) não cabe
-- num módulo puro, então ele é injetado como `obstructionRatio`: a fração de
-- amostras do raio que bateram em parede. 0 = visão limpa, 0.5 = metade
-- bloqueada, 1 = totalmente bloqueado.

local Config = require(script.Parent.Config)

local MonsterAI = {}

export type Vec3 = { x: number, y: number, z: number }

export type State = {
	mode: "Patrol" | "Chase",
	targetUserId: number?,
	targetName: string?,
	position: Vec3,
	lastSeenAt: number,
	lastSensedAt: number,
	nextRetargetAt: number,
	lastSwingAt: number,
}

export type PlayerSample = {
	userId: number,
	name: string,
	position: Vec3,
	isSprinting: boolean,
	isMoving: boolean,
	obstructionRatio: number, -- fração do raycast bloqueada (0..1)
	alive: boolean,
	isCaught: boolean,
}

export type SenseResult = {
	spotted: boolean,
	heard: boolean,
	reason: string,
	score: number,
}

-- ----------------------------------------------------------------------
-- Mat
-- ----------------------------------------------------------------------

function MonsterAI.distance(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Ângulo (graus) entre dois vetores, no plano XZ.
function MonsterAI.angleBetweenXZ(a: Vec3, b: Vec3): number
	local lenA = math.sqrt(a.x * a.x + a.z * a.z)
	local lenB = math.sqrt(b.x * b.x + b.z * b.z)
	if lenA < 1e-6 or lenB < 1e-6 then
		return 180 -- sem direção: trata como fora do campo de visão
	end

	local dot = (a.x * b.x + a.z * b.z) / (lenA * lenB)
	dot = math.clamp(dot, -1, 1)
	return math.deg(math.acos(dot))
end

function MonsterAI.sub(a: Vec3, b: Vec3): Vec3
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

--- Converte um Vector3 do Roblox para a forma pura.
function MonsterAI.fromVector(v: any): Vec3
	return { x = v.X, y = v.Y, z = v.Z }
end

--- Raio de audição efetivo, dependendo de como o jogador está se movendo.
function MonsterAI.hearingRadius(isSprinting: boolean, isMoving: boolean): number
	if isSprinting and isMoving then
		return Config.MONSTER_HEARING_RADIUS
	end
	if isMoving then
		return Config.MONSTER_HEARING_WALK
	end
	return 0
end

-- ----------------------------------------------------------------------
-- Percepção
-- ----------------------------------------------------------------------

--- O monstro percebe este jogador agora?
---
--- Visão:
---   * distância <= VIEW_DISTANCE
---   * dentro do FOV (ou colado: <= 12 studs sente em qualquer ângulo)
---   * linha de visão suficientemente desobstruída
---
--- Audição:
---   * correndo: raio MONSTER_HEARING_RADIUS
---   * andando: raio MONSTER_HEARING_WALK
---   * parado: não faz barulho
function MonsterAI.sense(state: State, sample: PlayerSample): SenseResult
	if not sample.alive or sample.isCaught then
		return { spotted = false, heard = false, reason = "indisponível", score = 0 }
	end

	local distance = MonsterAI.distance(state.position, sample.position)
	local toPlayer = MonsterAI.sub(sample.position, state.position)

	-- A direção para onde o monstro olha é derivada do alvo atual:
	-- sem target, ele "varre" na direção do jogador (patrulha).
	local forward = if state.targetUserId ~= nil
		then MonsterAI.sub(sample.position, state.position) -- perseguindo: sempre de frente
		else toPlayer

	local angle = MonsterAI.angleBetweenXZ(toPlayer, forward)
	local closeEnoughToFeel = distance <= 12
	local inFov = angle <= (Config.MONSTER_FOV_DEGREES / 2) or closeEnoughToFeel

	-- O raycast não bloqueia totalmente a menos que bata em parede.
	local cleanSight = (sample.obstructionRatio or 1) < 0.5

	local spotted = distance <= Config.MONSTER_VIEW_DISTANCE and inFov and cleanSight

	local heardRadius = MonsterAI.hearingRadius(sample.isSprinting, sample.isMoving)
	local heard = heardRadius > 0 and distance <= heardRadius

	-- Prioridade: visão vale mais que audição.
	local score = 0
	local reason = "nada"
	if spotted then
		reason = "visto"
		score = 1000 - distance
	elseif heard then
		reason = if sample.isSprinting then "ouvido correndo" else "ouvido andando"
		score = 500 - distance
	end

	return {
		spotted = spotted,
		heard = heard,
		reason = reason,
		score = score,
	}
end

--- Escolhe o melhor alvo entre todos os jogadores.
function MonsterAI.pickTarget(state: State, samples: { PlayerSample }): PlayerSample?
	local best: PlayerSample? = nil
	local bestScore = 0

	for _, sample in samples do
		-- Se já está perseguindo alguém, ele não troca a cada tick.
		local sameTarget = state.targetUserId == sample.userId

		local result = MonsterAI.sense(state, sample)
		if result.score > 0 then
			local score = result.score

			if sameTarget then
				score += 250 -- "gruda" no alvo atual
			end

			-- Quem se esconde (linha bloqueada) perde prioridade.
			score *= (1 - (sample.obstructionRatio or 0) * 0.6)

			if score > bestScore then
				bestScore = score
				best = sample
			end
		end
	end

	return best
end

-- ----------------------------------------------------------------------
-- Transições
-- ----------------------------------------------------------------------

function MonsterAI.new(position: Vec3): State
	return {
		mode = "Patrol",
		targetUserId = nil,
		targetName = nil,
		position = position,
		lastSeenAt = 0,
		lastSensedAt = 0,
		nextRetargetAt = 0,
		lastSwingAt = 0,
	}
end

--- Atualiza a perseguição: começa, mantém ou abandona.
--- Devolve o novo estado e se o modo mudou.
function MonsterAI.updateChase(state: State, samples: { PlayerSample }, now: number): (State, boolean)
	local previousMode = state.mode

	if now >= state.nextRetargetAt or state.targetUserId == nil then
		local target = MonsterAI.pickTarget(state, samples)
		state = table.clone(state)

		if target then
			local sensed = MonsterAI.sense(state, target)
			state.targetUserId = target.userId
			state.targetName = target.name
			state.lastSensedAt = now
			if sensed.spotted then
				state.lastSeenAt = now
			end
		else
			state.targetUserId = nil
			state.targetName = nil
		end

		state.nextRetargetAt = now + Config.MONSTER_RETARGET
	end

	-- O alvo sumiu / morreu / foi pego?
	local stillValid = false
	for _, sample in samples do
		if sample.userId == state.targetUserId and sample.alive and not sample.isCaught then
			local sensed = MonsterAI.sense(state, sample)
			if sensed.spotted then
				state.lastSeenAt = now
				state.lastSensedAt = now
			elseif sensed.heard then
				state.lastSensedAt = now
			end
			stillValid = true
			break
		end
	end

	local graceExpired = (now - state.lastSensedAt) > Config.MONSTER_LOSE_SIGHT_GRACE
	local mode: "Patrol" | "Chase" = if state.targetUserId ~= nil and stillValid and not graceExpired then "Chase" else "Patrol"

	if mode == "Patrol" then
		state.targetUserId = nil
		state.targetName = nil
		state.nextRetargetAt = 0
	end

	state.mode = mode
	return state, mode ~= previousMode
end

--- O monstro alcançou o jogador? (distância medida no servidor)
function MonsterAI.canCatch(state: State, sample: PlayerSample, now: number): boolean
	if not sample.alive or sample.isCaught then
		return false
	end

	if state.targetUserId ~= sample.userId then
		return false
	end

	if (now - state.lastSwingAt) < Config.MONSTER_CAUGHT_COOLDOWN then
		return false
	end

	return MonsterAI.distance(state.position, sample.position) <= Config.MONSTER_KILL_DISTANCE
end

--- Velocidade de movimento conforme o modo.
function MonsterAI.speedFor(mode: "Patrol" | "Chase"): number
	return if mode == "Chase" then Config.MONSTER_CHASE_SPEED else Config.MONSTER_PATROL_SPEED
end

--- Escolhe o próximo ponto de patrulha (aleatório, evitando repetir o atual).
function MonsterAI.nextWaypointIndex(current: number, total: number, random: (() -> number)?): number
	if total <= 1 then
		return 1
	end

	local rng = random or math.random
	local index = current
	for _ = 1, 8 do
		index = math.floor(rng() * total) + 1
		if index ~= current then
			return index
		end
	end

	-- Fallback determinístico.
	return (current % total) + 1
end

--- O monstro deve se teleportar de volta ao spawn? (ficou preso / longe demais)
function MonsterAI.needsRespawn(state: State, spawn: Vec3, now: number, lastProgressAt: number): boolean
	if state.mode == "Chase" then
		return false
	end
	return MonsterAI.distance(state.position, spawn) > 400 or (now - lastProgressAt) > 30
end

return MonsterAI

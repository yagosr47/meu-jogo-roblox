--!strict
-- Regras de estamina (puras, sem Instâncias).
--
-- O SERVIDOR é a fonte da verdade: ele acumula o tempo em que o jogador
-- declarou estar correndo e decide velocidade/estamina. O cliente só desenha
-- a barra com o valor replicado.

local Config = require(script.Parent.Config)

local StaminaLogic = {}

export type State = {
	stamina: number,
	sprinting: boolean,
	exhausted: boolean,
	lastSprintAt: number,
	lastMovementAt: number,
}

export type Input = {
	sprinting: boolean,
	moving: boolean,
}

--- Estado inicial de um jogador.
function StaminaLogic.new(): State
	return {
		stamina = Config.STAMINA_MAX,
		sprinting = false,
		exhausted = false,
		lastSprintAt = 0,
		lastMovementAt = 0,
	}
end

--- Quantos passos discretos (Config.STAMINA_STEP) representam este valor.
--- Serve para o servidor saber se vale a pena replicar.
function StaminaLogic.toStep(value: number): number
	return math.floor(math.clamp(value, 0, Config.STAMINA_MAX) / Config.STAMINA_STEP + 0.5)
end

--- Está "cansado" (perto de zerar)?  Usado para a respiração ofegante.
function StaminaLogic.isTired(state: State): boolean
	return state.stamina <= Config.STAMINA_EXHAUSTED_UNTIL or state.exhausted
end

-- ----------------------------------------------------------------------
-- Atualização por tick do servidor
-- ----------------------------------------------------------------------

--- Avança a estamina por `dt` segundos.
--- `sprinting` é o que o cliente DECLAROU; o servidor aceita, mas o consumo e
--- o corte por cansaço são dele.
function StaminaLogic.step(state: State, dt: number, input: Input, now: number): (State, boolean)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt > 5 then
		dt = 0
	end

	local stamina = state.stamina
	local exhausted = state.exhausted
	local sprinting = false
	local wasTired = StaminaLogic.isTired(state)

	local wantsSprint = input.sprinting == true and input.moving ~= false

	if wantsSprint and not exhausted and stamina > 0 then
		sprinting = true
		stamina -= Config.STAMINA_DRAIN_PER_SECOND * dt
		if stamina <= 0 then
			-- Bateu no fundo: entra em cansaço até recuperar.
			stamina = 0
			sprinting = false
			exhausted = true
		end
	else
		-- Regeneração: mais lenta andando, mais rápida parado.
		local sinceSprint = now - state.lastSprintAt
		if sinceSprint >= Config.STAMINA_REGEN_DELAY then
			local rate = Config.STAMINA_REGEN_PER_SECOND
			if input.moving ~= false then
				rate *= Config.STAMINA_REGEN_RATIO
			end
			stamina = math.min(Config.STAMINA_MAX, stamina + rate * dt)
		end
	end

	stamina = math.clamp(stamina, 0, Config.STAMINA_MAX)

	-- Saída do cansaço: reavaliada DEPOIS da regeneração, senão quem está
	-- recuperando exatamente no limite nunca sairia do estado cansado.
	if exhausted and stamina >= Config.STAMINA_EXHAUSTED_UNTIL then
		exhausted = false
	end

	local newState: State = {
		stamina = stamina,
		sprinting = sprinting,
		exhausted = exhausted,
		lastSprintAt = if sprinting then now else state.lastSprintAt,
		lastMovementAt = if input.moving ~= false then now else state.lastMovementAt,
	}

	-- segundo retorno: true se mudou o suficiente para replicar
	local changed = StaminaLogic.toStep(stamina) ~= StaminaLogic.toStep(state.stamina)
		or sprinting ~= state.sprinting
		or exhausted ~= state.exhausted
		or StaminaLogic.isTired(newState) ~= wasTired

	return newState, changed
end

--- Aplica o resultado de `step` dentro do MESMO objeto de estado.
--- O servidor guarda referências para esse objeto; trocar a tabela no meio do
--- tick fazia o loop de movimento ler dados velhos.
function StaminaLogic.apply(state: State, updated: State): State
	state.stamina = updated.stamina
	state.sprinting = updated.sprinting
	state.exhausted = updated.exhausted
	state.lastSprintAt = updated.lastSprintAt
	state.lastMovementAt = updated.lastMovementAt
	return state
end

--- Velocidade que o servidor aplica ao Humanoid agora.
function StaminaLogic.speedFor(state: State, requestedSprint: boolean): number
	if requestedSprint and state.sprinting and state.stamina > 0 and not state.exhausted then
		return Config.SPRINT_SPEED
	end
	return Config.WALK_SPEED
end

--- O cliente pode estar mentindo sobre a estamina dele? O servidor usa o
--- próprio valor; esta função só decide se aceita a corrida declarada.
function StaminaLogic.canSprint(state: State): boolean
	return not state.exhausted and state.stamina > Config.STAMINA_MIN_TO_SPRINT
end

return StaminaLogic

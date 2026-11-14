--!strict
-- Regras da lanterna e da bateria (puras, sem Instâncias).
--
-- Divisão de responsabilidade:
--   * O SERVIDOR decide se a lanterna pode ficar ligada e quanto de bateria
--     existe (é ele que persiste).
--   * O CLIENTE desenha a luz (SpotLight) e faz o efeito de piscar — mas o
--     brilho/piscar vem de `getLightState`, que é a MESMA função.

local Config = require(script.Parent.Config)

local FlashlightLogic = {}

export type State = {
	on: boolean,
	battery: number,
	lastToggleAt: number,
}

export type LightState = {
	enabled: boolean,
	brightness: number,
}

--- Estado inicial.
function FlashlightLogic.new(): State
	return {
		on = false,
		battery = Config.BATTERY_MAX,
		lastToggleAt = 0,
	}
end

--- Quantos passos discretos de bateria (Config.BATTERY_STEP).
function FlashlightLogic.toStep(battery: number): number
	return math.floor(math.clamp(battery, 0, Config.BATTERY_MAX) / Config.BATTERY_STEP + 0.5)
end

--- Bateria baixa (abaixo do limite que faz piscar).
function FlashlightLogic.isLow(battery: number): boolean
	return battery < Config.BATTERY_LOW_THRESHOLD
end

--- Bateria zerada: apaga de vez.
function FlashlightLogic.isDead(battery: number): boolean
	return battery <= 0
end

--- O jogador pode ligar a lanterna agora?
--- `toppling` protege contra spam de F; `dead` impede ligar sem bateria.
function FlashlightLogic.canToggle(state: State, now: number): boolean
	if FlashlightLogic.isDead(state.battery) then
		return false
	end

	-- `lastToggleAt` começa em 0 ("nunca tocou") e o relógio do Roblox NÃO
	-- começa necessariamente em 0 no cliente. Comparar direto fazia o
	-- primeiro F logo no spawn ser recusado — nunca use 0 como se fosse um
	-- instante válido.
	if state.lastToggleAt <= 0 then
		return true
	end

	return (now - state.lastToggleAt) >= Config.FLASHLIGHT_TOGGLE_COOLDOWN
end

-- ----------------------------------------------------------------------
-- Atualização por tick (usada nos dois lados)
-- ----------------------------------------------------------------------

--- Avança a bateria por `dt` segundos.
--- Devolve o novo estado e se algo relevante mudou (para replicar).
function FlashlightLogic.step(state: State, dt: number, now: number): (State, boolean)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt > 5 then
		dt = 0
	end

	local on = state.on
	local battery = state.battery

	if on and dt > 0 then
		battery -= Config.BATTERY_DRAIN_PER_SECOND * dt
		if battery <= 0 then
			battery = 0
			on = false -- apaga ao zerar
		end
	end

	battery = math.clamp(battery, 0, Config.BATTERY_MAX)

	local newState: State = {
		on = on,
		battery = battery,
		lastToggleAt = state.lastToggleAt,
	}

	local changed = FlashlightLogic.toStep(battery) ~= FlashlightLogic.toStep(state.battery) or on ~= state.on
	return newState, changed
end

--- Recarrega a bateria (pilha). Devolve o novo estado e quanto entrou de fato.
function FlashlightLogic.recharge(state: State, amount: number): (State, number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return state, 0
	end

	local before = state.battery
	local battery = math.clamp(before + amount, 0, Config.BATTERY_MAX)

	local newState: State = {
		on = state.on,
		battery = battery,
		lastToggleAt = state.lastToggleAt,
	}

	return newState, battery - before
end

--- Aplica o resultado dentro do MESMO objeto (as referências são guardadas
--- pelo servidor).
function FlashlightLogic.apply(state: State, updated: State): State
	state.on = updated.on
	state.battery = updated.battery
	state.lastToggleAt = updated.lastToggleAt
	return state
end

--- Liga/desliga se permitido. Devolve estado novo e se houve mudança.
function FlashlightLogic.toggle(state: State, now: number): (State, boolean)
	if not FlashlightLogic.canToggle(state, now) then
		return state, false
	end

	local newState: State = {
		on = not state.on,
		battery = state.battery,
		lastToggleAt = now,
	}

	return newState, true
end

-- ----------------------------------------------------------------------
-- Aparência da luz (divisão entre os dois lados)
-- ----------------------------------------------------------------------

--- Calcula o brilho da luz neste instante.
---
--- Bateria baixa NÃO apaga: pisca usando uma onda determinística baseada no
--- tempo, e nos vales o brilho vai a 0 por uns instantes. Como a função é
--- determinística (mesmo `now` = mesmo resultado), o servidor consegue
--- registrar o instante de uma piscada forte como eventuais "falhas de luz".
function FlashlightLogic.getLightState(state: State, now: number): LightState
	if not state.on or FlashlightLogic.isDead(state.battery) then
		return { enabled = false, brightness = 0 }
	end

	if not FlashlightLogic.isLow(state.battery) then
		return { enabled = true, brightness = Config.FLASHLIGHT_BRIGHTNESS }
	end

	-- Onda lenta entre 0 e 1.
	local t = math.max(0, now)
	local wave = 0.5 + 0.5 * math.sin(t * 3.1) * math.sin(t * 1.7 + 0.6)

	-- Abaixo do limiar, simula falhas: nos trechos ruins a luz cai.
	local threshold = 0.35
	if wave < threshold then
		return { enabled = true, brightness = Config.FLASHLIGHT_BRIGHTNESS * 0.12 }
	end

	return { enabled = true, brightness = Config.FLASHLIGHT_BRIGHTNESS * (0.55 + 0.45 * wave) }
end

--- O servidor usa isto para registrar picos (não confia no cliente para
--- decidir "luz fraca").
function FlashlightLogic.isFlickerStrong(state: State, now: number): boolean
	if not state.on or not FlashlightLogic.isLow(state.battery) then
		return false
	end
	return FlashlightLogic.getLightState(state, now).brightness < Config.FLASHLIGHT_BRIGHTNESS * 0.2
end

--- Intervalo até a próxima piscada fraca (só conveniência para o cliente).
function FlashlightLogic.nextFlickerDelay(battery: number): number
	local ratio = math.clamp(battery / Config.BATTERY_LOW_THRESHOLD, 0, 1)
	return Config.BATTERY_FLICKER_MIN + (Config.BATTERY_FLICKER_MAX - Config.BATTERY_FLICKER_MIN) * (1 - ratio)
end

return FlashlightLogic

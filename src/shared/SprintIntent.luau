--!strict
-- Máquina de estados da INTENÇÃO de correr (pura, sem Instâncias).
--
-- Por que existe: o servidor é quem manda na velocidade, e ele pode cortar a
-- corrida sozinho (quando a estamina esgota). Se o cliente apenas guardasse
-- "já avisei que estou correndo", nunca mais mandaria nada depois do corte e
-- a corrida só voltaria se o jogador soltasse e apertasse o Shift de novo.
--
-- Aqui ficam as três perguntas, resolvidas num só lugar e testáveis:
--   * preciso avisar o servidor agora?
--   * o que eu acho que ele aceitou?
--   * quando vale a pena reafirmar (watchdog)?
--
-- O cliente só desenha e manda o RemoteEvent; nenhuma decisão de velocidade
-- acontece aqui.

local Config = require(script.Parent.Config)

local SprintIntent = {}

-- Quanto tempo esperar por confirmação do servidor antes de reafirmar.
SprintIntent.WATCHDOG = 0.5

export type State = {
	-- O que o servidor nos contou (último STATE recebido).
	serverSprinting: boolean,
	-- O que o jogador está fazendo com o Shift.
	holdingKey: boolean,
	-- O que acreditamos ter avisado por último.
	declared: boolean,
	-- 0 = nada em observação; >0 = instante a partir do qual reafirmar.
	watchdogAt: number,
}

function SprintIntent.new(): State
	return {
		serverSprinting = false,
		holdingKey = false,
		declared = false,
		watchdogAt = 0,
	}
end

--- O jogador apertou/soltou o Shift (ou a janela perdeu o foco).
--- `undefined` = o servidor não considera o jogador correndo.
--- Devolve `true` se é preciso mandar um RemoteEvent AGORA.
function SprintIntent.pressKey(state: State, holding: boolean, now: number): boolean
	state.holdingKey = holding

	-- Apertar/soltar é sempre uma mudança real de intenção: manda na hora,
	-- sem deduplicação que possa engolir o "parei" e travar o jogador.
	state.declared = holding
	state.watchdogAt = if holding then now + SprintIntent.WATCHDOG else 0
	return true
end

--- Chegou um STATE do servidor.
function SprintIntent.onServerState(state: State, payload: any, now: number)
	state.serverSprinting = payload == true

	if state.serverSprinting then
		-- O servidor está correndo: pedido aceito, nada a reafirmar.
		state.declared = true
		state.watchdogAt = 0
		return
	end

	if not state.holdingKey then
		-- Parado: nada pendente.
		state.declared = false
		state.watchdogAt = 0
		return
	end

	-- Segurando o Shift mas o servidor não está correndo: ou ele cortou a
	-- corrida ao esgotar a estamina, ou recusou o pedido. Esquece o pedido
	-- anterior (senão a deduplicação engoliria a reafirmação) e arma o
	-- watchdog UMA vez — rearmar a cada STATE faria o prazo nunca chegar.
	state.declared = false
	if state.watchdogAt == 0 then
		state.watchdogAt = now + SprintIntent.WATCHDOG
	end
end

--- Passou um frame: é hora de reafirmar a intenção?
--- `canTry` é a condição de estamina (quem decide de verdade é o servidor).
function SprintIntent.shouldResync(state: State, now: number, canTry: boolean): boolean
	if not state.holdingKey or state.declared then
		return false
	end
	if not canTry then
		return false
	end
	if state.watchdogAt == 0 or now < state.watchdogAt then
		return false
	end

	-- Rearma para não mandar um pacote por frame.
	state.declared = true
	state.watchdogAt = now + SprintIntent.WATCHDOG
	return true
end

--- O servidor cortou a corrida (RESET). Não solta a tecla: apenas esquece a
--- confirmação para que o watchdog reconecte quando a estamina voltar.
function SprintIntent.onReset(state: State, now: number)
	state.declared = false
	if state.holdingKey then
		state.watchdogAt = math.max(state.watchdogAt, now + SprintIntent.WATCHDOG)
	end
end

--- A estamina permite tentar correr? (espelha `StaminaLogic.canSprint`)
function SprintIntent.mayTry(stamina: number, maxStamina: number, exhausted: boolean): boolean
	if exhausted then
		return false
	end
	return stamina > Config.STAMINA_EXHAUSTED_UNTIL and maxStamina > 0
end

return SprintIntent

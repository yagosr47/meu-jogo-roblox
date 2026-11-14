--!strict
-- Regras puras do sistema de checkpoints.
--
-- Este módulo é a fonte única de verdade da validação: o servidor usa
-- `evaluateClaim` para aceitar/recusar cada claim, e o cliente usa as mesmas
-- funções só para UI (previsão). Nada aqui acessa Instâncias, então dá para
-- rodar testes fora do Roblox.

local Config = require(script.Parent.Config)

local RaceLogic = {}

export type Phase = "Idle" | "Countdown" | "Running" | "Finished"

export type ClaimContext = {
	phase: Phase,
	nextIndex: number,
	totalCheckpoints: number,
	claimedIndex: any,
	distance: number,
	alive: boolean,
	now: number,
	startedAt: number,
	lastClaimAt: number,
	recentClaims: { number },
}

export type Verdict = {
	accepted: boolean,
	reason: string,
	finished: boolean,
}

local function reject(reason: string): Verdict
	return { accepted = false, reason = reason, finished = false }
end

-- ----------------------------------------------------------------------
-- Utilidades
-- ----------------------------------------------------------------------

--- Formata segundos como "MM:SS.cc".
function RaceLogic.formatTime(seconds: number): string
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
		return "00:00.00"
	end

	-- Arredonda ANTES de separar, senão 59.999 vira "00:60.00".
	local centiseconds = math.floor(seconds * 100 + 0.5)
	local minutes = centiseconds // 6000
	local rest = centiseconds % 6000
	local secs = rest // 100
	local cents = rest % 100

	return string.format("%02d:%02d.%02d", minutes, secs, cents)
end

--- Verifica se o valor é um índice de checkpoint válido (inteiro em 1..total).
function RaceLogic.isValidCheckpointIndex(value: any, totalCheckpoints: number): boolean
	if type(value) ~= "number" or value ~= value then
		return false -- NaN
	end
	if value % 1 ~= 0 then
		return false -- fracionário
	end
	return value >= 1 and value <= totalCheckpoints
end

--- Conta quantas claims aconteceram dentro da janela `window`.
function RaceLogic.countRecent(timestamps: { number }, now: number, window: number): number
	local count = 0
	for _, timestamp in ipairs(timestamps) do
		if type(timestamp) == "number" and (now - timestamp) <= window then
			count += 1
		end
	end
	return count
end

--- Remove da lista (in-place) as claims mais antigas que a janela.
function RaceLogic.pruneClaims(timestamps: { number }, now: number, window: number): { number }
	local kept = {}
	for _, timestamp in ipairs(timestamps) do
		if type(timestamp) == "number" and (now - timestamp) <= window then
			table.insert(kept, timestamp)
		end
	end
	return kept
end

--- Ordena o ranking (menor tempo primeiro) e devolve no máximo `max` entradas.
function RaceLogic.sortLeaderboard(entries: { { name: string, time: number } }, max: number): { { name: string, time: number } }
	local copy = table.clone(entries)
	table.sort(copy, function(a, b)
		if a.time == b.time then
			return a.name < b.name
		end
		return a.time < b.time
	end)

	local limited = {}
	for index, entry in ipairs(copy) do
		if index > max then
			break
		end
		table.insert(limited, entry)
	end
	return limited
end

-- ----------------------------------------------------------------------
-- Validação principal
-- ----------------------------------------------------------------------

--- Decide se uma claim de checkpoint deve ser aceita pelo servidor.
--- A ordem das checagens importa: primeiro o estado mais barato/óbvio,
--- depois as checagens de posição e tempo.
function RaceLogic.evaluateClaim(ctx: ClaimContext): Verdict
	if not ctx.alive then
		return reject("Personagem inválido ou morto.")
	end

	if ctx.phase ~= "Running" then
		return reject("Nenhuma corrida em andamento.")
	end

	if not RaceLogic.isValidCheckpointIndex(ctx.claimedIndex, ctx.totalCheckpoints) then
		return reject("Índice de checkpoint inválido.")
	end

	if ctx.claimedIndex ~= ctx.nextIndex then
		return reject(string.format("Checkpoint fora de ordem (esperado %d).", ctx.nextIndex))
	end

	-- Distância medida no SERVIDOR, nunca enviada pelo cliente.
	if type(ctx.distance) ~= "number" or ctx.distance ~= ctx.distance or ctx.distance > Config.MAX_CLAIM_DISTANCE then
		return reject("Longe demais do checkpoint.")
	end

	local elapsed = ctx.now - ctx.startedAt
	if elapsed < 0 then
		return reject("Relógio inválido.")
	end

	if elapsed > Config.RACE_TIME_LIMIT then
		return reject("Tempo da corrida esgotado.")
	end

	if ctx.lastClaimAt > 0 and (ctx.now - ctx.lastClaimAt) < Config.MIN_SECONDS_PER_CHECKPOINT then
		return reject("Checkpoints em sequência rápida demais.")
	end

	if RaceLogic.countRecent(ctx.recentClaims, ctx.now, Config.CLAIM_WINDOW_SECONDS) >= Config.MAX_CLAIMS_PER_WINDOW then
		return reject("Muitas requisições em pouco tempo.")
	end

	return {
		accepted = true,
		reason = "ok",
		finished = ctx.claimedIndex >= ctx.totalCheckpoints,
	}
end

return RaceLogic

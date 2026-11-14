--!strict
-- Regras de progressão da corrida, no lado do servidor.
--
-- Separado do script principal para poder ser testado sem Roblox: aqui só
-- entram números e booleanos, nunca Instâncias ou Players.

local RaceLogic = require(script.Parent.Parent.shared.RaceLogic)

export type Outcome = {
	ok: boolean,
	reason: string,
	totalCheckpoints: number,
	finished: boolean,
	elapsed: number,
}

export type Progression = {
	nextIndex: number,
	lastClaimAt: number,
	startedAt: number,
	recentClaims: { number },
}

local RaceServerLogic = {}

--- Primeiro checkpoint esperado depois de um `claimed`.
function RaceServerLogic.nextIndexAfter(claimed: number): number
	return claimed + 1
end

--- Processa uma claim já validada por `RaceLogic.evaluateClaim`.
--- Devolve o novo estado e o resultado para o cliente.
function RaceServerLogic.applyClaim(progression: Progression, claimed: number, total: number, now: number): (Progression, Outcome)
	local elapsed = now - progression.startedAt

	local updated: Progression = {
		nextIndex = RaceServerLogic.nextIndexAfter(claimed),
		lastClaimAt = now,
		startedAt = progression.startedAt,
		recentClaims = RaceLogic.pruneClaims(progression.recentClaims, now, 10),
	}
	table.insert(updated.recentClaims, now)

	local finished = claimed >= total

	return updated, {
		ok = true,
		reason = "ok",
		totalCheckpoints = total,
		finished = finished,
		elapsed = elapsed,
	}
end

--- Monta o contexto que `RaceLogic.evaluateClaim` espera.
function RaceServerLogic.buildContext(params: {
	phase: RaceLogic.Phase,
	progression: Progression,
	claimed: any,
	distance: number,
	alive: boolean,
	now: number,
	total: number,
}): RaceLogic.ClaimContext
	return {
		phase = params.phase,
		nextIndex = params.progression.nextIndex,
		totalCheckpoints = params.total,
		claimedIndex = params.claimed,
		distance = params.distance,
		alive = params.alive,
		now = params.now,
		startedAt = params.progression.startedAt,
		lastClaimAt = params.progression.lastClaimAt,
		recentClaims = params.progression.recentClaims,
	}
end

--- O progresso serve para alguma coisa? (usado para limpar salas antigas)
function RaceServerLogic.isStale(progression: Progression, now: number, idleSeconds: number): boolean
	return (now - progression.lastClaimAt) > idleSeconds and (now - progression.startedAt) > idleSeconds
end

return RaceServerLogic

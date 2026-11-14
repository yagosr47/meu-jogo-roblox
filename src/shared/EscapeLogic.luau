--!strict
-- Regras do objetivo principal de fuga (puro, sem Instâncias).
--
-- Um único lugar decide: quantos fusíveis existem, quem pode carregar qual,
-- quanto tempo leva para instalar, quando o gerador fica completo e quando o
-- portão abre. O servidor usa estas funções para validar; o cliente usa as
-- mesmas funções só para desenhar a barra de progresso.
--
-- Regras do pedido, todas aqui:
--   * 5 fusíveis no mapa;
--   * cada jogador carrega no MÁXIMO 1 (vários jogadores ao mesmo tempo, ok);
--   * instalar leva 3 segundos de barra;
--   * com os 5 instalados, o portão abre.

local Config = require(script.Parent.Config)

local EscapeLogic = {}

-- ----------------------------------------------------------------------
-- Tipos
-- ----------------------------------------------------------------------

export type Phase = "NeedFuses" | "ReadyToExit" | "Finished"

export type Fuse = {
	id: number,
	collected: boolean,
	byUserId: number?,
}

export type Progress = {
	installed: number,
	required: number,
	-- UserId -> id do fusível na mão. Cada jogador só pode ter UM, mas vários
	-- jogadores podem carregar ao mesmo tempo (o pedido é por jogador).
	holders: { [number]: number },
	-- Quem está instalando agora e desde quando (relógio do servidor).
	installingBy: number?,
	installStartedAt: number,
	gateOpen: boolean,
	phase: Phase,
	completedAt: number?,
}

export type Verdict = {
	ok: boolean,
	reason: string,
}

export type InstallVerdict = {
	ok: boolean,
	reason: string,
	completed: boolean,
}

-- ----------------------------------------------------------------------
-- Estado
-- ----------------------------------------------------------------------

function EscapeLogic.newFuse(id: number): Fuse
	return { id = id, collected = false, byUserId = nil }
end

--- Cria o estado inicial: nada coletado, nada instalado.
function EscapeLogic.newProgress(): Progress
	return {
		installed = 0,
		required = Config.FUSE_COUNT,
		holders = {},
		installingBy = nil,
		installStartedAt = 0,
		gateOpen = false,
		phase = "NeedFuses",
		completedAt = nil,
	}
end

--- O fusível que este jogador está carregando (ou nil).
function EscapeLogic.holdingOf(progress: Progress, userId: number): number?
	return progress.holders[userId]
end

--- Quantos jogadores estão carregando fusível agora.
function EscapeLogic.holdersCount(progress: Progress): number
	local count = 0
	for _ in progress.holders do
		count += 1
	end
	return count
end

--- Sentinela para "apagar este campo".
---
--- `{ installingBy = nil }` NÃO funciona em Lua: a chave simplesmente não
--- existe no table, então o `for` não itera e o valor antigo continua lá.
--- (Era exatamente esse o bug que travava a segunda instalação.)
local CLEAR = newproxy(false)
EscapeLogic.CLEAR = CLEAR

--- Cópia do progresso com uma alteração pontual. Evita repetir os 8 campos
--- em cada transição (e evita esquecer um, que já causou bugs sutis).
---
--- Use `EscapeLogic.CLEAR` para zerar um campo opcional.
local function withChanges(progress: Progress, changes: { [string]: any }): Progress
	local nextProgress: { [string]: any } = {
		installed = progress.installed,
		required = progress.required,
		holders = (table.clone(progress.holders) :: any),
		installingBy = progress.installingBy,
		installStartedAt = progress.installStartedAt,
		gateOpen = progress.gateOpen,
		phase = progress.phase,
		completedAt = progress.completedAt,
	}

	for key, value in changes do
		nextProgress[key] = if value == CLEAR then nil else value
	end

	return (nextProgress :: any) :: Progress
end

EscapeLogic.withChanges = withChanges

--- O gerador está completo?
function EscapeLogic.isComplete(installed: number): boolean
	return installed >= Config.FUSE_COUNT
end

--- Quantos fusíveis ainda faltam instalar.
function EscapeLogic.remaining(installed: number): number
	return math.max(0, Config.FUSE_COUNT - installed)
end

-- ----------------------------------------------------------------------
-- Coleta
-- ----------------------------------------------------------------------

--- O jogador pode pegar este fusível?
---
--- `progress` é o estado da partida e `userId` é quem está tentando pegar.
function EscapeLogic.canCollect(
	progress: Progress,
	fuse: Fuse?,
	userId: number,
	distance: number,
	alive: boolean
): Verdict
	if not alive then
		return { ok = false, reason = "personagem indisponível" }
	end

	if progress.phase == "Finished" then
		return { ok = false, reason = "a partida já terminou" }
	end

	if fuse == nil then
		return { ok = false, reason = "fusível inexistente" }
	end

	if fuse.collected then
		return { ok = false, reason = "fusível já coletado" }
	end

	-- REGRA CENTRAL: no máximo 1 fusível na mão, por jogador.
	if progress.holders[userId] ~= nil then
		return { ok = false, reason = "você já carrega um fusível" }
	end

	-- O mesmo fusível não pode ir para duas mãos.
	for _, heldId in progress.holders do
		if heldId == fuse.id then
			return { ok = false, reason = "fusível já está com outro jogador" }
		end
	end

	if type(distance) ~= "number" or distance ~= distance or distance > Config.FUSE_COLLECT_MAX_DISTANCE then
		return { ok = false, reason = "longe demais" }
	end

	return { ok = true, reason = "ok" }
end

--- Marca o fusível como coletado por este jogador.
function EscapeLogic.markCollected(progress: Progress, fuse: Fuse, userId: number): Progress
	fuse.collected = true
	fuse.byUserId = userId

	local holders = table.clone(progress.holders)
	holders[userId] = fuse.id

	return withChanges(progress, { holders = holders })
end

--- Devolve à mão vazia e libera o fusível para voltar ao mapa.
---
--- Usado quando o jogador morre ou sai: o fusível NÃO pode ser perdido, senão
--- a partida fica impossível de vencer.
function EscapeLogic.releaseFuse(progress: Progress, fuse: Fuse, userId: number): Progress
	fuse.collected = false
	fuse.byUserId = nil

	local holders = table.clone(progress.holders)
	holders[userId] = nil

	local installingBy: any = progress.installingBy
	if installingBy == userId then
		installingBy = CLEAR
	end

	return withChanges(progress, {
		holders = holders,
		installingBy = installingBy,
		installStartedAt = 0,
	})
end

-- ----------------------------------------------------------------------
-- Instalação (barra de 3 segundos)
-- ----------------------------------------------------------------------

--- `progress` pode começar uma instalação por parte deste jogador?
function EscapeLogic.canStartInstall(
	progress: Progress,
	userId: number,
	distance: number,
	now: number,
	alive: boolean
): InstallVerdict
	if not alive then
		return { ok = false, reason = "personagem indisponível", completed = false }
	end

	if progress.phase == "Finished" then
		return { ok = false, reason = "a partida já terminou", completed = false }
	end

	if EscapeLogic.isComplete(progress.installed) then
		return { ok = false, reason = "o gerador já está completo", completed = false }
	end

	if progress.holders[userId] == nil then
		return { ok = false, reason = "você não está carregando um fusível", completed = false }
	end

	if progress.installingBy ~= nil then
		return { ok = false, reason = "já está instalando", completed = false }
	end

	if type(distance) ~= "number" or distance ~= distance or distance > Config.FUSE_INSTALL_MAX_DISTANCE then
		return { ok = false, reason = "longe demais do gerador", completed = false }
	end

	if progress.installStartedAt > 0 and (now - progress.installStartedAt) < Config.FUSE_INSTALL_COOLDOWN then
		return { ok = false, reason = "aguarde um instante", completed = false }
	end

	return { ok = true, reason = "ok", completed = false }
end

--- Começa a instalação. O instante vem SEMPRE do servidor.
function EscapeLogic.beginInstall(progress: Progress, userId: number, now: number): Progress
	return withChanges(progress, {
		installingBy = userId,
		installStartedAt = now,
	})
end

--- Fração 0..1 da barra, medida no relógio do servidor.
function EscapeLogic.installProgress(progress: Progress, now: number): number
	if progress.installingBy == nil then
		return 0
	end

	if type(now) ~= "number" or now ~= now then
		return 0
	end

	local elapsed = now - progress.installStartedAt
	if elapsed <= 0 then
		return 0
	end

	return math.clamp(elapsed / Config.FUSE_INSTALL_SECONDS, 0, 1)
end

--- A instalação em andamento já pode ser concluída?
function EscapeLogic.canFinishInstall(
	progress: Progress,
	userId: number,
	now: number,
	distance: number,
	alive: boolean
): InstallVerdict
	if progress.installingBy ~= userId then
		return { ok = false, reason = "não há instalação sua em andamento", completed = false }
	end

	if not alive then
		return { ok = false, reason = "personagem indisponível", completed = false }
	end

	if EscapeLogic.installProgress(progress, now) < 1 then
		return { ok = false, reason = "ainda está instalando", completed = false }
	end

	-- Continua precisando estar perto: não dá para instalar e sair correndo.
	if type(distance) ~= "number" or distance ~= distance or distance > Config.FUSE_INSTALL_ABORT_DISTANCE then
		return { ok = false, reason = "longe demais do gerador", completed = false }
	end

	return { ok = true, reason = "ok", completed = true }
end

--- Cancela a instalação (saiu de perto, morreu, desistiu). O fusível continua
--- na mão de quem estava instalando.
function EscapeLogic.cancelInstall(progress: Progress): Progress
	return withChanges(progress, {
		installingBy = CLEAR,
		installStartedAt = 0,
	})
end

--- Conclui a instalação: consome o fusível da mão e incrementa o contador.
function EscapeLogic.completeInstall(progress: Progress, userId: number, now: number): Progress
	local fuseId = progress.holders[userId]
	if fuseId == nil then
		return progress
	end

	local installed = math.min(progress.installed + 1, Config.FUSE_COUNT)
	local done = installed >= Config.FUSE_COUNT

	local holders = table.clone(progress.holders)
	holders[userId] = nil

	return withChanges(progress, {
		installed = installed,
		holders = holders,
		installingBy = CLEAR,
		installStartedAt = now,
		-- O portão abre sozinho quando o último fusível entra.
		gateOpen = done,
		phase = if done then "ReadyToExit" else progress.phase,
		completedAt = if done then now else progress.completedAt,
	})
end

--- Quem está instalando se afastou demais?
function EscapeLogic.shouldAbortInstall(progress: Progress, distance: number): boolean
	if progress.installingBy == nil then
		return false
	end

	if type(distance) ~= "number" or distance ~= distance then
		return true
	end

	return distance > Config.FUSE_INSTALL_ABORT_DISTANCE
end

-- ----------------------------------------------------------------------
-- Portão de saída / vitória
-- ----------------------------------------------------------------------

--- O portão está aberto?
---
--- Ele abre AUTOMATICAMENTE quando o último fusível é instalado
--- (`completeInstall`) — não existe uma segunda ação de "abrir". O servidor
--- observa essa transição para mexer na geometria e avisar os clientes.
function EscapeLogic.isGateOpen(progress: Progress): boolean
	return progress.gateOpen
end

--- O jogador venceu? (encostou no portão aberto)
function EscapeLogic.canWin(progress: Progress, distance: number, alive: boolean): Verdict
	if not alive then
		return { ok = false, reason = "personagem indisponível" }
	end

	if progress.phase == "Finished" then
		return { ok = false, reason = "a partida já terminou" }
	end

	if not progress.gateOpen then
		return { ok = false, reason = "o portão está fechado" }
	end

	-- 75% da largura do portão é a "boca" da saída: folga suficiente para
	-- não frustrar quem já cruzou.
	if type(distance) ~= "number" or distance ~= distance or distance > Config.EXIT_GATE_WIDTH * 0.75 then
		return { ok = false, reason = "longe do portão" }
	end

	return { ok = true, reason = "ok" }
end

function EscapeLogic.markFinished(progress: Progress, now: number): Progress
	return withChanges(progress, {
		holders = {},
		installingBy = CLEAR,
		installStartedAt = 0,
		gateOpen = true,
		phase = "Finished",
		completedAt = if progress.completedAt == nil then now else progress.completedAt,
	})
end

-- ----------------------------------------------------------------------
-- Estado para o cliente (só o necessário para a HUD)
-- ----------------------------------------------------------------------

--- `userId` é de quem vai receber o pacote: a HUD de cada jogador mostra o
--- fusível DA PRÓPRIA mão, não o de outra pessoa.
function EscapeLogic.toPayload(progress: Progress, userId: number, now: number): { [string]: any }
	return {
		installed = progress.installed,
		required = progress.required,
		holding = progress.holders[userId],
		holders = EscapeLogic.holdersCount(progress),
		installing = progress.installingBy ~= nil,
		installProgress = EscapeLogic.installProgress(progress, now),
		installSeconds = Config.FUSE_INSTALL_SECONDS,
		gateOpen = progress.gateOpen,
		phase = progress.phase,
	}
end

return EscapeLogic

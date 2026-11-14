--!strict
-- Configurações compartilhadas entre servidor e cliente.
-- Só números, strings e booleanos aqui (nada de Instâncias), para o módulo
-- poder ser testado fora do Roblox.

local Config = {
	-- ------------------------------------------------------------------
	-- Estrutura da corrida
	-- ------------------------------------------------------------------
	CHECKPOINT_COUNT = 5, -- o último checkpoint é a linha de chegada
	COUNTDOWN_SECONDS = 3,
	RACE_TIME_LIMIT = 300, -- segundos até a corrida expirar
	START_COOLDOWN = 4, -- espera entre tentativas de largada
	USE_DATASTORE = true, -- ranking persistente (desligue se o jogo não tiver API access)

	-- ------------------------------------------------------------------
	-- Validação no servidor (anti-cheat)
	-- O servidor nunca confia no cliente: tudo abaixo é conferido lá.
	-- ------------------------------------------------------------------
	MAX_CLAIM_DISTANCE = 20, -- studs entre o HumanoidRootPart e o checkpoint
	MAX_START_DISTANCE = 30, -- studs entre o HumanoidRootPart e o pad de largada
	MIN_SECONDS_PER_CHECKPOINT = 0.35, -- tempo mínimo entre dois checkpoints
	MAX_CLAIMS_PER_WINDOW = 4, -- claims aceitas por janela
	CLAIM_WINDOW_SECONDS = 1,
	MAX_REMOTE_CALLS_PER_SECOND = 15, -- teto global de chamadas por jogador

	-- ------------------------------------------------------------------
	-- Geometria da pista (usada pelo CourseBuilder)
	-- ------------------------------------------------------------------
	TRACK_SPACING = 65, -- distância entre checkpoints
	START_PAD_WIDTH = 24,
	CHECKPOINT_WIDTH = 22,
	CHECKPOINT_DEPTH = 10,
	CHECKPOINT_HEIGHT = 12,
	FLOOR_WIDTH = 80,
	FLOOR_MARGIN = 40,
	FLOOR_THICKNESS = 2,

	-- ------------------------------------------------------------------
	-- Ranking
	-- ------------------------------------------------------------------
	LEADERBOARD_SIZE = 10,
}

return table.freeze(Config)

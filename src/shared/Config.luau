--!strict
-- Configuração única do jogo de terror.
--
-- Só números, strings e booleanos: nada de Instâncias, para os módulos de
-- regra (StaminaLogic, FlashlightLogic, MonsterAI) rodarem em testes fora do
-- Roblox.

local Config = {
	-- ------------------------------------------------------------------
	-- Jogador
	-- ------------------------------------------------------------------
	WALK_SPEED = 10,
	SPRINT_SPEED = 19,
	JUMP_POWER = 42,

	-- ------------------------------------------------------------------
	-- Estamina
	-- ------------------------------------------------------------------
	STAMINA_MAX = 100,
	-- O servidor guarda a estamina em passos discretos para não ficar
	-- recebendo réplica a cada frame.
	STAMINA_STEP = 5,
	STAMINA_DRAIN_PER_SECOND = 22,
	STAMINA_REGEN_PER_SECOND = 14,
	STAMINA_REGEN_DELAY = 1.0, -- segundos parado depois de correr
	STAMINA_REGEN_RATIO = 0.25, -- regenera mais devagar andando do que parado
	STAMINA_MIN_TO_SPRINT = 5,
	STAMINA_EXHAUSTED_UNTIL = 20, -- abaixo disso não dá para voltar a correr
	SERVER_STAMINA_TOLERANCE = 20, -- folga entre o cliente e o servidor

	-- ------------------------------------------------------------------
	-- Primeira pessoa (view bobbing, só no cliente)
	-- ------------------------------------------------------------------
	VIEW_BOB_SPEED = 11,
	VIEW_BOB_VERTICAL = 0.11,
	VIEW_BOB_HORIZONTAL = 0.06,
	VIEW_BOB_TILT = 0.45, -- graus
	VIEW_BOB_SMOOTHING = 12,

	-- ------------------------------------------------------------------
	-- Lanterna
	-- ------------------------------------------------------------------
	FLASHLIGHT_RANGE = 65,
	FLASHLIGHT_ANGLE = 55,
	FLASHLIGHT_BRIGHTNESS = 2.2,
	FLASHLIGHT_COLOR = { 1, 0.96, 0.86 }, -- [0..1]
	FLASHLIGHT_TOGGLE_COOLDOWN = 0.15, -- anti-spam entre dois F
	BATTERY_MAX = 100,
	BATTERY_DRAIN_PER_SECOND = 1.1, -- ligada, 100% -> ~90s
	BATTERY_STEP = 2, -- o servidor só persiste a cada 2%
	BATTERY_LOW_THRESHOLD = 20, -- abaixo disso, pisca
	BATTERY_FLICKER_MIN = 0.8,
	BATTERY_FLICKER_MAX = 2.4,
	BATTERY_BLINK_ON = 0.05,
	BATTERY_BLINK_OFF = 0.12,

	-- ------------------------------------------------------------------
	-- Pilhas coletáveis
	-- ------------------------------------------------------------------
	BATTERY_PICKUP_AMOUNT = 35,
	BATTERY_PICKUP_MAX = 12, -- quantas existem no mapa ao mesmo tempo
	BATTERY_PICKUP_RESPAWN = 12, -- segundos até repor o que foi pego
	BATTERY_PICKUP_MAX_DISTANCE = 20, -- validação no servidor
	BATTERY_PICKUP_MAX_PER_MINUTE = 10,
	FALLBACK_PICKUP_POINTS = 10,

	-- ------------------------------------------------------------------
	-- Monstro (IA)
	-- ------------------------------------------------------------------
	MONSTER_WAYPOINTS = {
		{ 0, 3, 12 },
		{ 30, 3, 18 },
		{ 46, 3, -6 },
		{ 24, 3, -26 },
		{ -8, 3, -20 },
		{ -34, 3, -2 },
		{ -34, 3, 30 },
		{ -2, 3, 30 },
	},
	MONSTER_SPAWN = { -20, 3, -30 },
	MONSTER_PATROL_SPEED = 7,
	MONSTER_CHASE_SPEED = 16,
	MONSTER_IDLE_MIN = 1.0,
	MONSTER_IDLE_MAX = 2.5,
	MONSTER_PATH_RECOMPUTE = 0.8,
	MONSTER_WAYPOINT_TOLERANCE = 3,

	MONSTER_VIEW_DISTANCE = 65,
	MONSTER_FOV_DEGREES = 130, -- visão "de frente"; perto disso ele sente de qualquer ângulo
	MONSTER_HEARING_RADIUS = 45, -- ouve o jogador correndo
	MONSTER_HEARING_WALK = 14, -- ouve andando (bem mais curto)
	MONSTER_RAYCAST_STEP = 0.3,
	MONSTER_LOSE_SIGHT_GRACE = 2.5, -- continua perseguindo por alguns segundos
	MONSTER_KILL_DISTANCE = 3.5,

	MONSTER_SPAWN_REPEAT = 10,
	MONSTER_CAUGHT_COOLDOWN = 6, -- não pode pegar o mesmo jogador de novo antes disso
	MONSTER_JUMPSCARE_SECONDS = 2.6, -- congelado vendo o jumpscare, e então morre
	MONSTER_MAX_PLAYERS_PER_HUNT = 1,
	MONSTER_RETARGET = 3.0,

	-- ------------------------------------------------------------------
	-- Mapa (gerado em runtime por MapBuilder)
	-- ------------------------------------------------------------------
	MAP_FLOOR_SIZE = 120,
	MAP_WALL_HEIGHT = 16,
	MAP_WALL_THICKNESS = 2,
	-- 9 luzes (grade 3x3) cobrem o salão inteiro. Com 6 num círculo o centro
	-- e as quinas ficavam no escuro absoluto.
	MAP_LIGHT_COUNT = 9,
	-- Range precisa alcançar o chão (a luz fica a 14 de altura) sem vazar
	-- pelo teto: 34 cobre um raio de ~34 studs para baixo e para os lados.
	MAP_LIGHT_RANGE = 34,
	-- Brilho calibrado pelo decaimento do PointLight: a 14 studs de altura o
	-- chão recebe ~35% da intensidade. Com 0.9 dava 0.31 — invisível com
	-- ExposureCompensation = -0.35. 2.2 deixa o chão em ~0.76 (dá para andar
	-- sem lanterna), ainda escuro o bastante para o clima.
	MAP_LIGHT_BRIGHTNESS = 2.2,

	-- ------------------------------------------------------------------
	-- Objetivo de fuga: fusíveis, gerador e portão
	-- ------------------------------------------------------------------
	FUSE_COUNT = 5,
	FUSE_INSTALL_SECONDS = 3, -- barra de progresso de instalação
	FUSE_COLLECT_MAX_DISTANCE = 12, -- validação no servidor
	FUSE_INSTALL_MAX_DISTANCE = 12, -- validação no servidor
	FUSE_INSTALL_COOLDOWN = 0.5, -- entre tentativas
	FUSE_INSTALL_ABORT_DISTANCE = 16, -- se afastar além disso, cancela
	FUSE_SPAWN_MARGIN = 8, -- distância mínima das paredes
	FUSE_SPAWN_SEPARATION = 18, -- distância mínima entre fusíveis
	FUSE_PICKUP_MAX_PER_MINUTE = 8,

	-- Quanto o gerador precisa estar perto de um pilar para não ser sorteado
	-- fusível em cima dele (o gerador em si é sólido).
	GENERATOR_PADDING = 5,

	-- Posições no mapa (0,0 é o centro; o piso vai de -60 a 60).
	-- O gerador fica longe do nascimento (o jogador tem que explorar) e o
	-- portão fica no lado oposto. Y = altura do PISO (as peças sobem a partir
	-- daí), não do centro das peças.
	GENERATOR_POSITION = { -34, 0, 4 },
	EXIT_GATE_POSITION = { 0, 6.5, 57 },
	EXIT_GATE_WIDTH = 22,
	EXIT_GATE_HEIGHT = 13, -- cabe sob o teto (MAP_WALL_HEIGHT = 16)

	-- Pontos a evitar ao sortear fusíveis: nascimento do jogador e gerador.
	FUSE_AVOID_SPAWN = 16,
	FUSE_AVOID_GENERATOR = 16,
	FUSE_AVOID_GATE = 18,

	-- ------------------------------------------------------------------
	-- Diversos
	-- ------------------------------------------------------------------
	REMOTE_CALLS_PER_SECOND = 20,
}

return table.freeze(Config)

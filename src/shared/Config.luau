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
	MAP_LIGHT_COUNT = 6,
	MAP_LIGHT_RANGE = 26,
	MAP_LIGHT_BRIGHTNESS = 0.8,

	-- ------------------------------------------------------------------
	-- Diversos
	-- ------------------------------------------------------------------
	REMOTE_CALLS_PER_SECOND = 20,
}

return table.freeze(Config)

-- Testes das regras do jogo de terror (Luau puro).

local Config = __require("Config")
local StaminaLogic = __require("StaminaLogic")
local FlashlightLogic = __require("FlashlightLogic")
local MonsterAI = __require("MonsterAI")

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then passed += 1; __log("  [OK]   " .. name)
	else failed += 1; __log("  [FALHA] " .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or "")) end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 0.001)
end

-- ======================================================================
__log("== STAMINA: basico ==")
local s = StaminaLogic.new()
check("comeca cheia", s.stamina == Config.STAMINA_MAX)
check("comeca parado", s.sprinting == false and s.exhausted == false)

local s2, changed = StaminaLogic.step(s, 1, { sprinting = true, moving = true }, 100)
check("correndo drena", near(s2.stamina, Config.STAMINA_MAX - Config.STAMINA_DRAIN_PER_SECOND), s2.stamina)
check("marca sprintando", s2.sprinting == true)
check("replicou mudanca", changed == true)

local s3 = StaminaLogic.step(s2, 1, { sprinting = true, moving = true }, 101)
check("continua drenando", s3.stamina < s2.stamina)

__log("== STAMINA: esgotar ==")
local drained = StaminaLogic.new()
drained.stamina = 10
local s4 = StaminaLogic.step(drained, 1, { sprinting = true, moving = true }, 200)
check("zera ao acabar", s4.stamina == 0, s4.stamina)
check("nao fica negativo", s4.stamina >= 0)
check("entra em cansaço", s4.exhausted == true)
check("para de sprintar", s4.sprinting == false)

local s5 = StaminaLogic.step(s4, 0.1, { sprinting = true, moving = true }, 210)
check("cansado nao sprintar", s5.sprinting == false)
check("cansado nao drena", s5.stamina >= s4.stamina)

__log("== STAMINA: regeneracao ==")
local tired = StaminaLogic.new()
tired.stamina = 30
tired.lastSprintAt = 1000
local s6 = StaminaLogic.step(tired, 1, { sprinting = false, moving = false }, 1000.5)
check("sem regen antes do delay", near(s6.stamina, 30), s6.stamina)
local s7 = StaminaLogic.step(tired, 1, { sprinting = false, moving = false }, 1002)
check("regen parado", near(s7.stamina, 30 + Config.STAMINA_REGEN_PER_SECOND), s7.stamina)
local s8 = StaminaLogic.step(tired, 1, { sprinting = false, moving = true }, 1002)
check("regen andando e menor", near(s8.stamina, 30 + Config.STAMINA_REGEN_PER_SECOND * Config.STAMINA_REGEN_RATIO), s8.stamina)

local full = StaminaLogic.new()
local s9 = StaminaLogic.step(full, 100, { sprinting = false, moving = false }, 5000)
check("nao passa do maximo", s9.stamina == Config.STAMINA_MAX)

__log("== STAMINA: saida do cansaco ==")
local ex = StaminaLogic.new()
ex.stamina = 5
ex.exhausted = true
ex.lastSprintAt = 0
local s10 = StaminaLogic.step(ex, 0.1, { sprinting = true, moving = true }, 100)
check("continua cansado abaixo do limite", s10.exhausted == true, s10.stamina)
-- recuperando exatamente no limite deve sair do cansaco
local ex2 = StaminaLogic.new()
ex2.stamina = Config.STAMINA_EXHAUSTED_UNTIL - 1
ex2.exhausted = true
ex2.lastSprintAt = 0
local s11 = StaminaLogic.step(ex2, 0.5, { sprinting = true, moving = false }, 100)
check("sai do cansaco ao recuperar no limite", s11.exhausted == false, s11.stamina)

-- transicao de respiracao ofegante precisa ser replicada
local calm = StaminaLogic.new()
local _, transition = StaminaLogic.step(calm, 0.1, { sprinting = false, moving = false }, 100)
check("sem mudanca quando esta tudo calmo", transition == false)
local breathless = StaminaLogic.new()
breathless.stamina = 30
local tiredStep, tiredChanged = StaminaLogic.step(breathless, 0.1, { sprinting = true, moving = true }, 100)
check("virar cansado conta como mudanca", tiredChanged == true)

__log("== STAMINA: entradas invalidas ==")
local badDt = StaminaLogic.step(StaminaLogic.new(), -5, { sprinting = true, moving = true }, 10)
check("dt negativo nao quebra", badDt.stamina == Config.STAMINA_MAX)
local nanDt = StaminaLogic.step(StaminaLogic.new(), 0/0, { sprinting = true, moving = true }, 10)
check("dt NaN nao quebra", nanDt.stamina == Config.STAMINA_MAX)
local hugeDt = StaminaLogic.step(StaminaLogic.new(), 999, { sprinting = true, moving = true }, 10)
check("dt absurdo e ignorado", hugeDt.stamina == Config.STAMINA_MAX)

__log("== STAMINA: velocidade ==")
local run = { stamina = 100, sprinting = true, exhausted = false, lastSprintAt = 0, lastMovementAt = 0 }
check("velocidade de corrida", StaminaLogic.speedFor(run, true) == Config.SPRINT_SPEED)
check("velocidade andando", StaminaLogic.speedFor(run, false) == Config.WALK_SPEED)
local noStam = { stamina = 0, sprinting = true, exhausted = true, lastSprintAt = 0, lastMovementAt = 0 }
check("sem estamina = andar", StaminaLogic.speedFor(noStam, true) == Config.WALK_SPEED)
check("canSprint falso quando cansado", StaminaLogic.canSprint(noStam) == false)
check("canSprint verdadeiro cheio", StaminaLogic.canSprint(run) == true)
check("isTired detecta", StaminaLogic.isTired(noStam) == true)
check("isTired ok cheio", StaminaLogic.isTired(run) == false)

-- ======================================================================
__log("== LANTERNA: basico ==")
local f = FlashlightLogic.new()
check("comeca desligada", f.on == false)
check("bateria cheia", f.battery == Config.BATTERY_MAX)

local on = FlashlightLogic.toggle(f, 100)
check("liga", on.on == true)
check("registra horario", on.lastToggleAt == 100)

local off = FlashlightLogic.toggle(on, 100.05)
check("anti-spam bloqueia toggle rapido", off.on == true)
local off2 = FlashlightLogic.toggle(on, 101)
check("desliga depois", off2.on == false)

__log("== LANTERNA: consumo ==")
local lit = { on = true, battery = 100, lastToggleAt = 0 }
local d1 = FlashlightLogic.step(lit, 1, 500)
check("drena 1 por segundo", near(d1.battery, 100 - Config.BATTERY_DRAIN_PER_SECOND), d1.battery)
local idle = { on = false, battery = 100, lastToggleAt = 0 }
local d2 = FlashlightLogic.step(idle, 10, 500)
check("desligada nao drena", d2.battery == 100)

local dying = { on = true, battery = 0.5, lastToggleAt = 0 }
local d3 = FlashlightLogic.step(dying, 1, 500)
check("zera bateria", d3.battery == 0, d3.battery)
check("apaga ao zerar", d3.on == false)

__log("== LANTERNA: recarga ==")
local low = { on = false, battery = 10, lastToggleAt = 0 }
local r1, gained = FlashlightLogic.recharge(low, Config.BATTERY_PICKUP_AMOUNT)
check("recarrega", near(r1.battery, 45), r1.battery)
check("informa quanto entrou", near(gained, 35), gained)
local r2, gained2 = FlashlightLogic.recharge({ on = true, battery = 95, lastToggleAt = 0 }, 35)
check("nao passa do maximo", r2.battery == Config.BATTERY_MAX, r2.battery)
check("ganho limitado ao espaco", near(gained2, 5), gained2)
local r3, gained3 = FlashlightLogic.recharge({ on = false, battery = 100, lastToggleAt = 0 }, 35)
check("cheia nao ganha nada", gained3 == 0)
local r4, gained4 = FlashlightLogic.recharge(low, -50)
check("recarga negativa ignorada", gained4 == 0 and r4.battery == 10)
local r5, gained5 = FlashlightLogic.recharge(low, 0/0)
check("recarga NaN ignorada", gained5 == 0)

__log("== LANTERNA: nao liga sem bateria ==")
local dead = { on = false, battery = 0, lastToggleAt = 0 }
local deadToggle = FlashlightLogic.toggle(dead, 100)
check("zerada nao liga", deadToggle.on == false)
check("isDead", FlashlightLogic.isDead(0) == true)
check("isLow 19", FlashlightLogic.isLow(19) == true)
check("isLow 20 nao", FlashlightLogic.isLow(20) == false)

__log("== LANTERNA: piscar abaixo de 20% ==")
local okLight = FlashlightLogic.getLightState({ on = true, battery = 80, lastToggleAt = 0 }, 10)
check("cheia: brilho normal", okLight.enabled and near(okLight.brightness, Config.FLASHLIGHT_BRIGHTNESS))

local flickerSamples, minB, maxB = 0, math.huge, -math.huge
for i = 0, 600 do
	local ls = FlashlightLogic.getLightState({ on = true, battery = 10, lastToggleAt = 0 }, i * 0.05)
	if ls.enabled then
		flickerSamples += 1
		minB = math.min(minB, ls.brightness)
		maxB = math.max(maxB, ls.brightness)
	end
end
check("baixa: pisca (brilho varia)", maxB - minB > 0.5, string.format("min=%.2f max=%.2f", minB, maxB))
check("baixa: chega a quase apagar", minB < Config.FLASHLIGHT_BRIGHTNESS * 0.2, minB)
check("baixa: continua ligada normal as vezes", maxB > Config.FLASHLIGHT_BRIGHTNESS * 0.5, maxB)

local offLight = FlashlightLogic.getLightState({ on = false, battery = 100, lastToggleAt = 0 }, 10)
check("desligada: luz off", offLight.enabled == false)
local zeroLight = FlashlightLogic.getLightState({ on = true, battery = 0, lastToggleAt = 0 }, 10)
check("sem bateria: luz off mesmo com on", zeroLight.enabled == false)

local deterministic = true
for i = 0, 20 do
	local t = i * 0.37
	local a = FlashlightLogic.getLightState({ on = true, battery = 5, lastToggleAt = 0 }, t)
	local b = FlashlightLogic.getLightState({ on = true, battery = 5, lastToggleAt = 0 }, t)
	if a.brightness ~= b.brightness then deterministic = false end
end
check("piscar e deterministico (servidor e cliente concordam)", deterministic == true)

-- ======================================================================
__log("== MONSTRO: matematica ==")
check("distancia 3-4-0", near(MonsterAI.distance({x=0,y=0,z=0},{x=3,y=0,z=4}), 5))
check("angulo frente", near(MonsterAI.angleBetweenXZ({x=0,y=0,z=10},{x=0,y=0,z=10}), 0))
check("angulo 90", near(MonsterAI.angleBetweenXZ({x=10,y=0,z=0},{x=0,y=0,z=10}), 90))
check("angulo tras", near(MonsterAI.angleBetweenXZ({x=0,y=0,z=-10},{x=0,y=0,z=10}), 180))
check("vetor zero = 180", MonsterAI.angleBetweenXZ({x=0,y=0,z=0},{x=0,y=0,z=1}) == 180)
check("audicao correndo", MonsterAI.hearingRadius(true, true) == Config.MONSTER_HEARING_RADIUS)
check("audicao andando", MonsterAI.hearingRadius(false, true) == Config.MONSTER_HEARING_WALK)
check("audicao parado", MonsterAI.hearingRadius(false, false) == 0)

__log("== MONSTRO: visao ==")
local mState = MonsterAI.new({x=0,y=0,z=0})
local function sample(over: any?): any
	local s = { userId = 1, name = "P1", position = {x=0,y=0,z=20}, isSprinting = false, isMoving = false, obstructionRatio = 0, alive = true, isCaught = false }
	for k, v in over or {} do s[k] = v end
	return s
end
check("ve de perto", MonsterAI.sense(mState, sample()).spotted == true)
check("nao ve longe demais", MonsterAI.sense(mState, sample({ position = {x=0,y=0,z=Config.MONSTER_VIEW_DISTANCE + 5} })).spotted == false)
check("nao ve com parede", MonsterAI.sense(mState, sample({ obstructionRatio = 0.9 })).spotted == false)
check("ve com visao limpa", MonsterAI.sense(mState, sample({ obstructionRatio = 0.2 })).spotted == true)
check("nao ve morto", MonsterAI.sense(mState, sample({ alive = false })).spotted == false)
check("nao ve ja pego", MonsterAI.sense(mState, sample({ isCaught = true })).spotted == false)
check("sente colado mesmo de tras", MonsterAI.sense(mState, sample({ position = {x=0,y=0,z=-5} })).spotted == true)

__log("== MONSTRO: audicao ==")
local farNoisy = sample({ position = {x=0,y=0,z=Config.MONSTER_HEARING_RADIUS - 2}, isSprinting = true, isMoving = true, obstructionRatio = 1 })
local heard = MonsterAI.sense(mState, farNoisy)
check("ouve corrida com parede no meio", heard.heard == true and heard.spotted == false, heard.reason)
local quiet = sample({ position = {x=0,y=0,z=30}, isSprinting = false, isMoving = false, obstructionRatio = 1 })
check("nao ouve parado", MonsterAI.sense(mState, quiet).heard == false)
local walkFar = sample({ position = {x=0,y=0,z=Config.MONSTER_HEARING_RADIUS - 2}, isSprinting = false, isMoving = true, obstructionRatio = 1 })
check("andar longe nao faz barulho", MonsterAI.sense(mState, walkFar).heard == false)

__log("== MONSTRO: escolha de alvo ==")
local samples = {
	sample({ userId = 1, position = {x=0,y=0,z=60} }),
	sample({ userId = 2, position = {x=0,y=0,z=8} }),
	sample({ userId = 3, position = {x=0,y=0,z=30}, obstructionRatio = 0.9 }),
}
local picked = MonsterAI.pickTarget(mState, samples)
check("escolhe o mais perto e visivel", picked ~= nil and picked.userId == 2, picked and picked.userId)

local hidden = { sample({ userId = 1, position = {x=0,y=0,z=5}, obstructionRatio = 1 }) }
check("nao persegue quem esta escondido atras de parede", MonsterAI.pickTarget(mState, hidden) == nil)

local noneVisible = {
	sample({ userId = 9, position = {x=0,y=0,z=300} }),
}
check("nada ao alcance = nil", MonsterAI.pickTarget(mState, noneVisible) == nil)

__log("== MONSTRO: transicoes ==")
local st = MonsterAI.new({x=0,y=0,z=0})
local seenSamples = { sample({ userId = 1, position = {x=0,y=0,z=10} }) }
local st2, modeChanged = MonsterAI.updateChase(st, seenSamples, 100)
check("entra em perseguicao", st2.mode == "Chase", st2.mode)
check("avisa mudanca de modo", modeChanged == true)
check("guarda o alvo", st2.targetUserId == 1)

-- jogador foge para longe: continua por um tempo (grace) e depois volta
local st3 = MonsterAI.updateChase(st2, { sample({ userId = 1, position = {x=0,y=0,z=300} }) }, 101)
check("mantem perseguicao na tolerancia", st3.mode == "Chase", st3.mode)
local st4 = MonsterAI.updateChase(st3, { sample({ userId = 1, position = {x=0,y=0,z=300} }) }, 110)
check("desiste depois da tolerancia", st4.mode == "Patrol", st4.mode)
check("limpa o alvo ao desistir", st4.targetUserId == nil)

__log("== MONSTRO: captura ==")
local chasing = { mode = "Chase", targetUserId = 1, targetName = "P1", position = {x=0,y=0,z=0}, lastSeenAt = 0, lastSensedAt = 0, nextRetargetAt = 0, lastSwingAt = 0 }
check("pega colado", MonsterAI.canCatch(chasing, sample({ position = {x=0,y=0,z=2} }), 100) == true)
check("nao pega longe", MonsterAI.canCatch(chasing, sample({ position = {x=0,y=0,z=20} }), 100) == false)
check("nao pega quem nao e o alvo", MonsterAI.canCatch(chasing, sample({ userId = 99, position = {x=0,y=0,z=2} }), 100) == false)
check("respeita cooldown", MonsterAI.canCatch({ mode="Chase", targetUserId=1, targetName="P1", position={x=0,y=0,z=0}, lastSeenAt=0, lastSensedAt=0, nextRetargetAt=0, lastSwingAt=99 }, sample({ position = {x=0,y=0,z=2} }), 100) == false)
check("nao pega morto", MonsterAI.canCatch(chasing, sample({ position = {x=0,y=0,z=2}, alive = false }), 100) == false)

__log("== MONSTRO: velocidade e waypoints ==")
check("corre mais rapido que anda", MonsterAI.speedFor("Chase") > MonsterAI.speedFor("Patrol"))
local seq = { 0.5, 0.99, 0.0, 0.42 }
local i = 0
local function fakeRandom(): number i += 1; return seq[((i - 1) % #seq) + 1] end
local wp = MonsterAI.nextWaypointIndex(2, 8, fakeRandom)
check("waypoint valido", wp >= 1 and wp <= 8, wp)
check("nao repete o atual", MonsterAI.nextWaypointIndex(1, 1, fakeRandom) == 1)
local counts = {}
for k = 1, 200 do
	local r = math.random()
	local idx = MonsterAI.nextWaypointIndex(1, 5, function() return r end)
	counts[idx] = (counts[idx] or 0) + 1
end
check("waypoints dentro do intervalo", (counts[1] == nil or counts[6] == nil), "")

-- ======================================================================
__log("== APPLY: mutacao no lugar ==")
local target = StaminaLogic.new()
local ref = target
local updated, _ = StaminaLogic.step(target, 2, { sprinting = true, moving = true }, 50)
local applied = StaminaLogic.apply(target, updated)
check("apply devolve o mesmo objeto", applied == ref)
check("apply muda o valor", math.abs(target.stamina - updated.stamina) < 0.001, target.stamina)
check("referencia continua valida", ref.stamina == target.stamina)

local fl = FlashlightLogic.new()
local flRef = fl
local newFl, _ = FlashlightLogic.step({ on = true, battery = 50, lastToggleAt = 0 }, 1, 10)
FlashlightLogic.apply(fl, newFl)
check("apply da lanterna preserva referencia", flRef == fl and fl.battery < 50, fl.battery)
check("apply da lanterna mantem ligada", fl.on == true and flRef.on == true)

-- ======================================================================
__log("== GEOMETRIA: waypoints dentro do mapa e fora dos pilares ==")
-- (espelha GAME/map do MapBuilder: pilares nas posicoes abaixo)
local PILARES = {
	{ x = 20, z = 20, w = 10, d = 10 },
	{ x = -22, z = 16, w = 8, d = 14 },
	{ x = 26, z = -18, w = 14, d = 8 },
	{ x = -18, z = -22, w = 10, d = 10 },
	{ x = 2, z = 2, w = 12, d = 6 },
}
local half = Config.MAP_FLOOR_SIZE / 2

local function insidePillar(x: number, z: number, padding: number): boolean
	for _, p in PILARES do
		if math.abs(x - p.x) < (p.w / 2 + padding) and math.abs(z - p.z) < (p.d / 2 + padding) then
			return true
		end
	end
	return false
end

local waypointsOk = true
for i, wp in Config.MONSTER_WAYPOINTS do
	local x, z = wp[1], wp[3]
	if math.abs(x) >= half - 3 or math.abs(z) >= half - 3 then
		waypointsOk = false
		__log("   waypoint " .. i .. " fora do mapa: " .. x .. "," .. z)
	end
	if insidePillar(x, z, 1.5) then
		waypointsOk = false
		__log("   waypoint " .. i .. " dentro de um pilar: " .. x .. "," .. z)
	end
end
check("todos os waypoints sao validos", waypointsOk == true)

check("spawn do monstro fora de pilar", insidePillar(Config.MONSTER_SPAWN[1], Config.MONSTER_SPAWN[3], 2) == false)

local spawnOk = math.abs(Config.MONSTER_SPAWN[1]) < half and math.abs(Config.MONSTER_SPAWN[3]) < half
check("spawn do monstro dentro do mapa", spawnOk == true)

local origemOk = true
for i = 1, 10 do
	local angle = (i / 10) * math.pi * 2 + 0.4
	local x = math.cos(angle) * half * 0.72
	local z = math.sin(angle) * half * 0.72
	if insidePillar(x, z, 1) or math.abs(x) >= half - 2 or math.abs(z) >= half - 2 then
		origemOk = false
	end
end
check("pontos de pilha validos", origemOk == true)
check("pelo menos 1 waypoint", #Config.MONSTER_WAYPOINTS >= 2)

__log("")
__log(string.format("RESULTADO: %d passaram, %d falharam", passed, failed))
if failed > 0 then error(string.format("%d teste(s) falharam", failed)) end

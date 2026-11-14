-- Testes das regras do jogo de terror (Luau puro).

local Config = __require("Config")
local StaminaLogic = __require("StaminaLogic")
local FlashlightLogic = __require("FlashlightLogic")
local MonsterAI = __require("MonsterAI")
local SprintIntent = __require("SprintIntent")

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

-- ======================================================================
__log("== ESCAPE: estado inicial ==")
local EscapeLogic = __require("EscapeLogic")
local FuseSpawner = __require("FuseSpawner")

local prog = EscapeLogic.newProgress()
check("comeca sem fusivel na mao", EscapeLogic.holdingOf(prog, 1) == nil)
check("comeca com 0 instalado", prog.installed == 0)
check("precisa de FUSE_COUNT", prog.required == Config.FUSE_COUNT)
check("portao fechado", prog.gateOpen == false)
check("fase inicial", prog.phase == "NeedFuses")
check("5 fusiveis (requisito do pedido)", Config.FUSE_COUNT == 5)

__log("== ESCAPE: coleta ==")
local fuse1 = EscapeLogic.newFuse(1)
local v = EscapeLogic.canCollect(prog, fuse1, 42, 3, true)
check("pode coletar perto", v.ok == true, v.reason)
check("recusa longe", EscapeLogic.canCollect(prog, fuse1, 42, 999, true).ok == false)
check("recusa morto", EscapeLogic.canCollect(prog, fuse1, 42, 3, false).ok == false)
check("recusa fusivel inexistente", EscapeLogic.canCollect(prog, nil, 42, 3, true).ok == false)
check("recusa distancia NaN", EscapeLogic.canCollect(prog, fuse1, 42, 0/0, true).ok == false)
check("recusa distancia string", EscapeLogic.canCollect(prog, fuse1, 42, "3" :: any, true).ok == false)

local holding = EscapeLogic.markCollected(prog, fuse1, 42)
check("marca como coletado", fuse1.collected == true and fuse1.byUserId == 42)
check("guardou na mao", EscapeLogic.holdingOf(holding, 42) == 1)

-- REGRA PRINCIPAL: 1 fusivel por jogador
local fuse2 = EscapeLogic.newFuse(2)
local second = EscapeLogic.canCollect(holding, fuse2, 42, 3, true)
check("nao carrega 2 fusiveis", second.ok == false, second.reason)
check("fusivel ja coletado nao repete", EscapeLogic.canCollect(prog, fuse1, 42, 3, true).ok == false)

-- outro jogador pode carregar ao mesmo tempo (o limite e' POR jogador)
local outro = EscapeLogic.canCollect(holding, fuse2, 99, 3, true)
check("outro jogador pode pegar outro fusivel", outro.ok == true, outro.reason)
check("mesmo fusivel nao vai para duas maos", EscapeLogic.canCollect(holding, fuse1, 99, 3, true).ok == false)

__log("== ESCAPE: instalacao (3s) ==")
check("nao instala sem fusivel", EscapeLogic.canStartInstall(prog, 42, 3, 100, true).ok == false)
check("pode comecar com fusivel", EscapeLogic.canStartInstall(holding, 42, 3, 100, true).ok == true)
check("outro jogador nao instala a minha mao", EscapeLogic.canStartInstall(holding, 99, 3, 100, true).ok == false)
check("recusa longe do gerador", EscapeLogic.canStartInstall(holding, 42, 999, 100, true).ok == false)

local installing = EscapeLogic.beginInstall(holding, 42, 100)
check("marcou instalando", installing.installingBy == 42)
check("progresso 0 no inicio", EscapeLogic.installProgress(installing, 100) == 0)
check("progresso ~0.5 em 1.5s", math.abs(EscapeLogic.installProgress(installing, 101.5) - 0.5) < 0.001)
check("progresso 1 em 3s", EscapeLogic.installProgress(installing, 103) == 1)
check("progresso nao passa de 1", EscapeLogic.installProgress(installing, 999) == 1)
check("nao termina antes de 3s", EscapeLogic.canFinishInstall(installing, 42, 101, 3, true).ok == false)
check("termina em 3s", EscapeLogic.canFinishInstall(installing, 42, 103, 3, true).ok == true)
check("outro nao conclui a instalacao alheia", EscapeLogic.canFinishInstall(installing, 99, 103, 3, true).ok == false)
check("tempo medido no servidor (NaN = 0)", EscapeLogic.installProgress(installing, 0/0) == 0)

-- afastar cancela
check("afastar pede cancelamento", EscapeLogic.shouldAbortInstall(installing, 100) == true)
check("perto nao cancela", EscapeLogic.shouldAbortInstall(installing, 5) == false)
local cancelled = EscapeLogic.cancelInstall(installing)
check("cancelar zera progresso", cancelled.installingBy == nil and EscapeLogic.installProgress(cancelled, 200) == 0)
check("cancelar mantem o fusivel na mao", EscapeLogic.holdingOf(cancelled, 42) == 1)

__log("== ESCAPE: instalar os 5 ==")
local state = EscapeLogic.newProgress()
local fuses = {}
for i = 1, Config.FUSE_COUNT do
	fuses[i] = EscapeLogic.newFuse(i)
end

local JUMP = 7
local now = 1000
local allOk = true
for i = 1, Config.FUSE_COUNT do
	local f = fuses[i]
	if not EscapeLogic.canCollect(state, f, JUMP, 2, true).ok then
		allOk = false
		__log("   falhou coleta do fusivel " .. i)
		break
	end
	state = EscapeLogic.markCollected(state, f, JUMP)

	now += 1
	if not EscapeLogic.canStartInstall(state, JUMP, 2, now, true).ok then
		allOk = false
		__log("   falhou inicio da instalacao " .. i)
		break
	end
	state = EscapeLogic.beginInstall(state, JUMP, now)

	now += Config.FUSE_INSTALL_SECONDS
	if not EscapeLogic.canFinishInstall(state, JUMP, now, 2, true).ok then
		allOk = false
		__log("   falhou fim da instalacao " .. i)
		break
	end
	state = EscapeLogic.completeInstall(state, JUMP, now)
end

check("fluxo completo dos 5 fusiveis", allOk == true)
check("instalou todos", state.installed == Config.FUSE_COUNT, state.installed)
check("mao vazia no fim", EscapeLogic.holdingOf(state, JUMP) == nil)
check("gerador completo", EscapeLogic.isComplete(state.installed) == true)
check("portao aberto ao completar", state.gateOpen == true)
check("fase pronto para sair", state.phase == "ReadyToExit", state.phase)
check("nada restante", EscapeLogic.remaining(state.installed) == 0)
check("nao instala mais que o necessario", EscapeLogic.canStartInstall(state, JUMP, 2, now + 10, true).ok == false)

__log("== ESCAPE: portao e vitoria ==")
local fresh = EscapeLogic.newProgress()
check("portao fechado no inicio", EscapeLogic.isGateOpen(fresh) == false)
local closedGate = EscapeLogic.canWin(fresh, 2, true)
check("nao vence com portao fechado", closedGate.ok == false, closedGate.reason)

-- o portao abre sozinho ao instalar o ultimo fusivel (sem acao extra)
check("portao aberto ao completar o gerador", EscapeLogic.isGateOpen(state) == true)
local opened = state

check("vence perto do portao", EscapeLogic.canWin(opened, 5, true).ok == true)
check("nao vence longe", EscapeLogic.canWin(opened, 999, true).ok == false)
check("nao vence morto", EscapeLogic.canWin(opened, 5, false).ok == false)

local finished = EscapeLogic.markFinished(opened, now)
check("fase final", finished.phase == "Finished")
check("nao vence duas vezes", EscapeLogic.canWin(finished, 5, true).ok == false)

__log("== ESCAPE: payload da HUD ==")
local payload = EscapeLogic.toPayload(installing, 42, 101.5)
check("payload tem instalados", payload.installed == 0)
check("payload tem total", payload.required == Config.FUSE_COUNT)
check("payload tem progresso", math.abs(payload.installProgress - 0.5) < 0.001)
check("payload tem fase", payload.phase == "NeedFuses")

-- ======================================================================
__log("== SPAWNER: fusiveis em pontos validos ==")
-- Espelha a geometria do MapBuilder.
local PILARES_SP = {
	{ x = 20, z = 20, w = 10, d = 10 },
	{ x = -22, z = 16, w = 8, d = 14 },
	{ x = 26, z = -18, w = 14, d = 8 },
	{ x = -18, z = -22, w = 10, d = 10 },
	{ x = 2, z = 2, w = 12, d = 6 },
}
local halfMap = Config.MAP_FLOOR_SIZE / 2

-- Obstáculos de PRODUÇÃO: pilares + o próprio gerador (que é sólido).
local OBSTACULOS_PROD = {}
for _, p in PILARES_SP do
	table.insert(OBSTACULOS_PROD, p)
end
table.insert(OBSTACULOS_PROD, {
	x = Config.GENERATOR_POSITION[1],
	z = Config.GENERATOR_POSITION[3],
	w = 8 + Config.GENERATOR_PADDING,
	d = 6 + Config.GENERATOR_PADDING,
})

local mapOptions = {
	halfSize = halfMap,
	obstacles = OBSTACULOS_PROD,
	spawn = { x = 0, y = 0, z = -halfMap + 12 },
	generator = { x = Config.GENERATOR_POSITION[1], y = 0, z = Config.GENERATOR_POSITION[3] },
	gate = { x = Config.EXIT_GATE_POSITION[1], y = 0, z = Config.EXIT_GATE_POSITION[3] },
}

-- gerador mutavel: simula outro mapa (o sorteio precisa ser generico)
local genMoved = {
	halfSize = halfMap,
	obstacles = PILARES_SP,
	spawn = { x = 0, y = 0, z = -halfMap + 12 },
	generator = { x = 30, y = 0, z = 0 },
	gate = { x = 0, y = 0, z = halfMap - 3 },
}

local seed = 0
local function seeded(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local pontos = FuseSpawner.roll(mapOptions, Config.FUSE_COUNT, seeded)
check("sorteou a quantidade certa", #pontos == Config.FUSE_COUNT, #pontos)

local validos, motivo = FuseSpawner.validate(pontos, mapOptions)
check("todos os pontos sao validos", validos == true, motivo)

-- nenhum dentro de pilar
local dentroDePilar = 0
for _, p in pontos do
	if FuseSpawner.blocked(p.x, p.z, OBSTACULOS_PROD, 0) then
		dentroDePilar += 1
	end
end
check("nenhum dentro de pilar/gerador", dentroDePilar == 0, dentroDePilar)

-- todos separados
local muitoPerto = 0
for i = 1, #pontos do
	for j = i + 1, #pontos do
		if FuseSpawner.distance2D(pontos[i], pontos[j]) < Config.FUSE_SPAWN_SEPARATION then
			muitoPerto += 1
		end
	end
end
check("todos bem separados", muitoPerto == 0, muitoPerto)

-- longe do gerador e do portao
local pertoDoGerador = 0
for _, p in pontos do
	if FuseSpawner.distance2D(p, mapOptions.generator) < Config.FUSE_AVOID_GENERATOR then
		pertoDoGerador += 1
	end
end
check("nenhum colado no gerador", pertoDoGerador == 0, pertoDoGerador)

-- varios sorteios diferentes, todos validos
local todosValidos = true
for k = 1, 25 do
	local outroSeed = k * 7919
	local function r(): number
		outroSeed = (outroSeed * 1103515245 + 12345) % 2147483648
		return outroSeed / 2147483648
	end
	local sorteio = FuseSpawner.roll(mapOptions, Config.FUSE_COUNT, r)
	local ok2, motivo2 = FuseSpawner.validate(sorteio, mapOptions)
	if not ok2 or #sorteio ~= Config.FUSE_COUNT then
		todosValidos = false
		__log("   sorteio " .. k .. " invalido: " .. tostring(motivo2))
		break
	end
end
check("25 sorteios diferentes, todos validos", todosValidos == true)

-- sorteio ruim (random sempre 0) cai no fallback de grade e ainda funciona
local zerado = FuseSpawner.roll(mapOptions, Config.FUSE_COUNT, function() return 0 end)
check("random degenerado ainda gera 5", #zerado == Config.FUSE_COUNT, #zerado)
local okZero, motivoZero = FuseSpawner.validate(zerado, mapOptions)
check("fallback tambem e valido", okZero == true, motivoZero)

local generico = FuseSpawner.roll(genMoved, Config.FUSE_COUNT, seeded)
local okGen = FuseSpawner.validate(generico, genMoved)
check("funciona com gerador em outra posicao", okGen == true)

__log("== GEOMETRIA: gerador e portao no mapa ==")
local gx, gz = Config.GENERATOR_POSITION[1], Config.GENERATOR_POSITION[3]
local tx, tz = Config.EXIT_GATE_POSITION[1], Config.EXIT_GATE_POSITION[3]

check("gerador dentro do piso", math.abs(gx) + 4 < halfMap and math.abs(gz) + 3 < halfMap)
check("portao dentro do piso", math.abs(tx) + Config.EXIT_GATE_WIDTH / 2 < halfMap and math.abs(tz) < halfMap)
check("portao cabe sob o teto", Config.EXIT_GATE_HEIGHT + 2 <= Config.MAP_WALL_HEIGHT)

-- O gerador nao pode estar dentro de um pilar.
local geradorEmPilar = false
for _, p in PILARES_SP do
	if math.abs(gx - p.x) < (p.w / 2 + 4) and math.abs(gz - p.z) < (p.d / 2 + 3) then
		geradorEmPilar = true
	end
end
check("gerador fora dos pilares", geradorEmPilar == false)

-- O portao nao pode estar dentro de um pilar.
local portaoEmPilar = false
for _, p in PILARES_SP do
	if math.abs(tx - p.x) < (p.w / 2 + Config.EXIT_GATE_WIDTH / 2) and math.abs(tz - p.z) < (p.d / 2 + 1.5) then
		portaoEmPilar = true
	end
end
check("portao fora dos pilares", portaoEmPilar == false)

-- O jogador nasce longe do gerador: tem que explorar.
local spawnZ = -halfMap + 12
check(
	"gerador longe do nascimento",
	math.sqrt(gx * gx + (gz - spawnZ) * (gz - spawnZ)) >= 40,
	math.sqrt(gx * gx + (gz - spawnZ) * (gz - spawnZ))
)

-- Gerador e portao em lados opostos: a fuga atravessa o mapa.
check("gerador e portao distantes", math.sqrt((gx - tx) ^ 2 + (gz - tz) ^ 2) >= 50)

__log("== ESCAPE: devolver fusivel (portador saiu) ==")
-- O servidor reseta `collected` e reexibe o modelo. Aqui testamos a parte
-- pura: depois de "devolver", o mesmo fusivel volta a poder ser coletado.
local f3 = EscapeLogic.newFuse(3)
local s1 = EscapeLogic.markCollected(EscapeLogic.newProgress(), f3, 99)
check("fusivel 3 na mao", EscapeLogic.holdingOf(s1, 99) == 3)
check("nao pode pegar outro", EscapeLogic.canCollect(s1, EscapeLogic.newFuse(4), 99, 2, true).ok == false)

-- devolucao (equivalente a releaseOrphans)
local devolvido = EscapeLogic.releaseFuse(s1, f3, 99)
check("apos devolver, mao vazia", EscapeLogic.holdingOf(devolvido, 99) == nil)
check("fusivel volta a nao-coletado", f3.collected == false and f3.byUserId == nil)
check("fusivel devolvido pode ser pego de novo", EscapeLogic.canCollect(devolvido, f3, 99, 2, true).ok == true)
check("progresso de instalacao preservado", devolvido.installed == s1.installed)
check("release nao quebra a fase", devolvido.phase == s1.phase)
check("release nao abre o portao", devolvido.gateOpen == false)

-- release durante a instalacao: cancela a barra mas mantem o instalado
local meio = EscapeLogic.newProgress()
meio = EscapeLogic.withChanges(meio, { installed = 2 })
local f9 = EscapeLogic.newFuse(9)
meio = EscapeLogic.markCollected(meio, f9, 5)
meio = EscapeLogic.beginInstall(meio, 5, 100)
local solto = EscapeLogic.releaseFuse(meio, f9, 5)
check("release para a barra", solto.installingBy == nil)
check("release mantem instalados", solto.installed == 2)
check("release zera a mao", EscapeLogic.holdingOf(solto, 5) == nil)

__log("== ESCAPE: co-op (progresso e compartilhado) ==")
-- Jogador A pega, jogador B nao pode pegar o mesmo; A instala, B ve o numero.
local co = EscapeLogic.newProgress()
local fa = EscapeLogic.newFuse(1)
local fb = EscapeLogic.newFuse(2)
co = EscapeLogic.markCollected(co, fa, 1)
check("A pegou", EscapeLogic.holdingOf(co, 1) == 1)
check("B nao pode pegar o mesmo fusivel", EscapeLogic.canCollect(co, fa, 2, 2, true).ok == false)
check("B pode pegar outro fusivel", EscapeLogic.canCollect(co, fb, 2, 2, true).ok == true)

-- B pega o dele: dois jogadores carregando ao mesmo tempo
co = EscapeLogic.markCollected(co, fb, 2)
check("A e B carregam juntos", EscapeLogic.holdersCount(co) == 2)

local t = 500
co = EscapeLogic.beginInstall(co, 1, t)
check("A instalando", co.installingBy == 1)
co = EscapeLogic.completeInstall(co, 1, t + Config.FUSE_INSTALL_SECONDS)
check("instalacao de A conta para todos", co.installed == 1)
check("mao de A liberada", EscapeLogic.holdingOf(co, 1) == nil)
check("B continua com o dele", EscapeLogic.holdingOf(co, 2) == 2)
check("restou 1 carregando", EscapeLogic.holdersCount(co) == 1)

__log("== REGRESSAO: campo opcional apagado de verdade ==")
-- `{ installingBy = nil }` NAO apaga a chave em Lua (o `for` nao itera), o
-- valor antigo continuava e a segunda instalacao falhava com "ja esta
-- instalando". Este teste garante que cancelar/terminar limpa de fato.
local r = EscapeLogic.newProgress()
local fr = EscapeLogic.newFuse(1)
r = EscapeLogic.markCollected(r, fr, 1)
r = EscapeLogic.beginInstall(r, 1, 100)
check("instalando antes", r.installingBy == 1)

local rc = EscapeLogic.cancelInstall(r)
check("cancelInstall limpa installingBy", rc.installingBy == nil, rc.installingBy)

-- E possivel instalar DE NOVO depois de cancelar.
local r2 = EscapeLogic.beginInstall(rc, 1, 102)
check("segunda instalacao inicia", r2.installingBy == 1)
local r3 = EscapeLogic.completeInstall(r2, 1, 106)
check("completeInstall limpa installingBy", r3.installingBy == nil)

-- Idem para releaseFuse quando ELE era quem instalava.
local r4 = EscapeLogic.newProgress()
local fr4 = EscapeLogic.newFuse(4)
r4 = EscapeLogic.markCollected(r4, fr4, 8)
r4 = EscapeLogic.beginInstall(r4, 8, 200)
local r5 = EscapeLogic.releaseFuse(r4, fr4, 8)
check("releaseFuse limpa installingBy", r5.installingBy == nil)
check("releaseFuse limpa a mao", EscapeLogic.holdingOf(r5, 8) == nil)

-- markFinished limpa tudo.
local r6 = EscapeLogic.markFinished(r3, 300)
check("fim limpa installingBy", r6.installingBy == nil)
check("fim limpa as maos", EscapeLogic.holdersCount(r6) == 0)

-- ======================================================================
__log("== REGRESSAO: Shift e lanterna no comeco da partida ==")
-- Bug 1: `lastToggleAt` comeca em 0 ("nunca tocou"), mas o relogio do
-- Roblox NAO comeca em 0 no cliente. A comparacao direta recusava o
-- primeiro F logo no spawn.
local fresh = FlashlightLogic.new()
check("primeiro F funciona com relogio pequeno", FlashlightLogic.canToggle(fresh, 0.02) == true)
check("primeiro F funciona com relogio grande", FlashlightLogic.canToggle(fresh, 5000) == true)
check("primeiro F funciona em relogio negativo", FlashlightLogic.canToggle(fresh, -1) == true)

-- O anti-spam continua valendo depois do primeiro toque.
local touched = { on = true, battery = 100, lastToggleAt = 10 }
check("anti-spam ainda bloqueia", FlashlightLogic.canToggle(touched, 10.05) == false)
check("anti-spam libera depois", FlashlightLogic.canToggle(touched, 10.5) == true)
check("cooldown vem do Config", Config.FLASHLIGHT_TOGGLE_COOLDOWN > 0)

-- Sem bateria nao liga, nem com lastToggleAt zerado.
check("sem bateria nao liga", FlashlightLogic.canToggle({ on = false, battery = 0, lastToggleAt = 0 }, 999) == false)

-- Bug 2: o servidor corta a corrida ao esgotar a estamina; ao recuperar, o
-- jogador PRECISA voltar a correr sem soltar o Shift. A regra que garante
-- isso e `canSprint` liberar de novo depois da recuperacao.
local recup = { stamina = Config.STAMINA_EXHAUSTED_UNTIL + 1, sprinting = false, exhausted = false, lastSprintAt = 0, lastMovementAt = 0 }
check("corre de novo apos recuperar", StaminaLogic.canSprint(recup) == true)
-- `speedFor` exige os DOIS lados: o pedido do jogador e o aval do servidor.
local recupSprint = { stamina = Config.STAMINA_EXHAUSTED_UNTIL + 1, sprinting = true, exhausted = false, lastSprintAt = 0, lastMovementAt = 0 }
check("velocidade volta a sprint", StaminaLogic.speedFor(recupSprint, true) == Config.SPRINT_SPEED)
check("sem aval do servidor nao corre", StaminaLogic.speedFor(recup, true) == Config.WALK_SPEED)

-- A virada "bateria baixa" precisa ser detectada comparando o valor ANTES
-- do apply (o `before` é a mesma tabela do state).
local lowBefore = FlashlightLogic.isLow(20.5)
local lowAfter = FlashlightLogic.isLow(19.5)
check("virada para bateria baixa e detectavel", lowBefore ~= lowAfter)

-- ======================================================================
__log("== REGRESSAO: intencao de corrida (SprintIntent) ==")
-- O bug: o servidor corta a corrida ao esgotar a estamina. Se o cliente
-- continuar achando que "ja avisou true", a corrida nunca mais volta sem
-- soltar o Shift. Estes testes travam o comportamento correto.

local si = SprintIntent.new()
check("comeca sem correr", si.holdingKey == false and si.declared == false)

-- Apertar manda na hora.
check("apertar avisa o servidor", SprintIntent.pressKey(si, true, 10) == true)
check("marcou como declarado", si.declared == true and si.holdingKey == true)

-- Soltar TAMBEM manda na hora (nunca pode ser engolido).
check("soltar avisa sempre", SprintIntent.pressKey(si, false, 10.01) == true)
check("parou de segurar", si.holdingKey == false)

-- Servidor cortou a corrida (esgotou) com o dedo ainda apertado.
local s2 = SprintIntent.new()
SprintIntent.pressKey(s2, true, 100)
SprintIntent.onServerState(s2, true, 100.1)
check("confirmado nao pede resync", SprintIntent.shouldResync(s2, 100.2, true) == false)

-- Agora o servidor corta: sprinting=false, jogador segurando.
SprintIntent.onServerState(s2, false, 101)
check("corte libera a deduplicacao", s2.declared == false)
check("watchdog armado", s2.watchdogAt > 0)
check("ainda nao e hora", SprintIntent.shouldResync(s2, 101.1, true) == false)
check("sem estamina nao tenta", SprintIntent.shouldResync(s2, 999, false) == false)

-- Passado o prazo e com estamina, reafirma UMA vez (nao a cada frame).
check("hora de reafirmar", SprintIntent.shouldResync(s2, 101.6, true) == true)
check("nao repete no frame seguinte", SprintIntent.shouldResync(s2, 101.7, true) == false)

-- Soltar o Shift zera tudo: ninguem fica preso correndo.
local s3 = SprintIntent.new()
SprintIntent.pressKey(s3, true, 5)
SprintIntent.onServerState(s3, true, 5.1)
SprintIntent.pressKey(s3, false, 6)
check("soltar limpa o watchdog", s3.watchdogAt == 0 and s3.declared == false)
check("parado nunca faz resync", SprintIntent.shouldResync(s3, 9999, true) == false)

-- Um STATE atrasado (sprinting=true de antes do key-up) nao pode rearmar a
-- deduplicacao e travar o proximo Shift.
local s4 = SprintIntent.new()
SprintIntent.pressKey(s4, true, 1)
SprintIntent.onServerState(s4, true, 1.1)
SprintIntent.pressKey(s4, false, 2)
SprintIntent.onServerState(s4, true, 2.5) -- chegou atrasado
check("state atrasado nao trava o proximo Shift", SprintIntent.pressKey(s4, true, 3) == true)

-- mayTry: a estamina manda, e o servidor continua sendo quem decide.
check("pode tentar com estamina cheia", SprintIntent.mayTry(Config.STAMINA_MAX, Config.STAMINA_MAX, false) == true)
check("nao pode tentar exausto", SprintIntent.mayTry(Config.STAMINA_MAX, Config.STAMINA_MAX, true) == false)
check("nao pode tentar sem estamina", SprintIntent.mayTry(0, Config.STAMINA_MAX, false) == false)
check("limiar vem do Config", SprintIntent.mayTry(Config.STAMINA_EXHAUSTED_UNTIL, Config.STAMINA_MAX, false) == false)

__log("")
__log(string.format("RESULTADO: %d passaram, %d falharam", passed, failed))
if failed > 0 then error(string.format("%d teste(s) falharam", failed)) end

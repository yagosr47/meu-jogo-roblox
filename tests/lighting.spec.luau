-- Testes de iluminacao do mapa (Luau puro).
--
-- Ficam em arquivo separado de logic.spec.luau porque o compilador do Luau
-- tem limite de 200 registradores por script e o spec principal ja esta no
-- limite. Usa a MESMA `check`/`__log` injetadas pelo harness.

local size, height = Config.MAP_FLOOR_SIZE, Config.MAP_WALL_HEIGHT

-- ======================================================================
__log("== ILUMINACAO: posicao e cintilacao ==")
-- As luzes do mapa ficavam num circulo de raio 36: o centro e as quinas
-- ficavam no escuro. Agora vem de uma grade derivada do tamanho do mapa.

local positions = LightingLogic.lightPositions(size, height, Config.MAP_LIGHT_COUNT)

check("gera a quantidade pedida", #positions == Config.MAP_LIGHT_COUNT, #positions)

-- Uma funcao so faz toda a medicao e devolve numeros.
-- Motivo: o Luau tem limite de 200 registradores POR SCRIPT, e o bundle de
-- teste concatena todos os specs num arquivo unico. Cada `local` de topo
-- gasta um registrador ate o fim do script.
local function measure(list, pillars)
	local inside, belowTop, belowFloor, hasCenter = 0, 0, 0, false
	local maxDistance = 0
	local pillarHits, outsideMap, duplicates = 0, 0, 0

	for i, pos in list do
		local x, y, z = pos[1], pos[2], pos[3]
		local d = math.sqrt(x * x + z * z)

		if math.abs(x) > size / 2 or math.abs(z) > size / 2 then
			outsideMap += 1
		else
			inside += 1
		end
		if y < height then belowTop += 1 end
		if y <= 0 then belowFloor += 1 end
		if math.abs(x) < 1 and math.abs(z) < 1 then hasCenter = true end
		if d > maxDistance then maxDistance = d end

		if pillars then
			for _, pillar in pillars do
				if math.abs(x - pillar.x) <= pillar.w / 2 + 4
					and math.abs(z - pillar.z) <= pillar.d / 2 + 4 then
					pillarHits += 1
				end
			end
		end

		for j = i + 1, #list do
			local other = list[j]
			if math.abs(x - other[1]) < 0.01 and math.abs(z - other[3]) < 0.01 then
				duplicates += 1
			end
		end
	end

	-- Cobertura: quantas celulas da grade tem luz a uma distancia util.
	local covered, cells = 0, 0
	for gx = -50, 50, 10 do
		for gz = -50, 50, 10 do
			cells += 1
			local best = math.huge
			for _, pos in list do
				local dd = math.sqrt((gx - pos[1]) ^ 2 + (gz - pos[3]) ^ 2)
				if dd < best then best = dd end
			end
			if best < Config.MAP_LIGHT_RANGE then covered += 1 end
		end
	end

	return {
		count = #list,
		inside = inside,
		belowTop = belowTop,
		belowFloor = belowFloor,
		hasCenter = hasCenter,
		maxDistance = maxDistance,
		pillarHits = pillarHits,
		outsideMap = outsideMap,
		duplicates = duplicates,
		covered = covered,
		cells = cells,
	}
end

local m = measure(positions, nil)
check("todas dentro do piso", m.inside == m.count, m.outsideMap)
check("todas abaixo do teto", m.belowTop == m.count, m.count - m.belowTop)
check("nenhuma abaixo do chao", m.belowFloor == 0, m.belowFloor)
check("luz nunca colada no teto", positions[1][2] <= height - 1, positions[1][2])
check("grade ilumina o centro", m.hasCenter)
check("luzes chegam perto das paredes", m.maxDistance > size * 0.3, m.maxDistance)
check("nenhuma luz duplicada", m.duplicates == 0, m.duplicates)

check("respeita contagem menor", #LightingLogic.lightPositions(size, height, 4) == 4)
check("pedido invalido vira 1", #LightingLogic.lightPositions(size, height, -5) == 1)
check("nunca passa do teto de luzes", #LightingLogic.lightPositions(size, height, 999) <= LightingLogic.MAX_LIGHTS)

-- Cintilacao: nunca passa do brilho base, nunca apaga.
local flicker = { max = 0, min = math.huge, positive = true }
for i = 0, 400 do
	local value = LightingLogic.brightnessAt(1.0, 3, i * 0.05)
	if value > flicker.max then flicker.max = value end
	if value < flicker.min then flicker.min = value end
	if value <= 0 then flicker.positive = false end
end
check("cintilacao nunca passa do base", flicker.max <= 1 + 1e-9, flicker.max)
check("cintilacao nunca apaga", flicker.positive)
check("cintilacao varia de verdade", flicker.max - flicker.min > 0.05, flicker.max - flicker.min)
check("brilho zero continua zero", LightingLogic.brightnessAt(0, 1, 10) == 0)
check("fases distintas por luz",
	math.abs(LightingLogic.brightnessAt(1.0, 1, 2) - LightingLogic.brightnessAt(1.0, 2, 2)) > 0.001)

-- Sombra: so a lanterna do jogador projeta. Luz ambiente com sombra e o que
-- faz o mapa cintilar ao andar.
check("luz ambiente sem sombra", LightingLogic.shouldCastShadow(false) == false)
check("lanterna com sombra", LightingLogic.shouldCastShadow(true) == true)

-- ======================================================================
__log("== ILUMINACAO: pilares e duplicatas ==")
-- Regressao: a luz central caia DENTRO do Pilar5 (x=2,z=2) e virava um
-- clarão chapado. O deslocamento tambem ja colocou duas luzes na MESMA
-- posicao e outra fora do mapa (x=84 num mapa de 120).
local PILLARS_TEST = {
	{ x = 20, z = 20, w = 10, d = 10 },
	{ x = -22, z = 16, w = 8, d = 14 },
	{ x = 26, z = -18, w = 14, d = 8 },
	{ x = -18, z = -22, w = 10, d = 10 },
	{ x = 2, z = 2, w = 12, d = 6 },
}

local mp = measure(LightingLogic.lightPositions(size, height, Config.MAP_LIGHT_COUNT, PILLARS_TEST), PILLARS_TEST)
check("ainda gera todas", mp.count == Config.MAP_LIGHT_COUNT, mp.count)
check("nenhuma luz dentro de pilar", mp.pillarHits == 0, mp.pillarHits)
check("nenhuma luz fora do piso", mp.outsideMap == 0, mp.outsideMap)
check("nenhuma luz duplicada (com pilares)", mp.duplicates == 0, mp.duplicates)
check("cobre a maior parte do salao", mp.covered / mp.cells >= 0.9,
	string.format("%d/%d", mp.covered, mp.cells))

-- Mapa pequeno nao pode gerar coordenada absurda.
local tiny = measure(LightingLogic.lightPositions(20, 8, 9, {}), nil)
local tinyOk = true
for _, pos in LightingLogic.lightPositions(20, 8, 9, {}) do
	if math.abs(pos[1]) > 10 or math.abs(pos[3]) > 10 then tinyOk = false end
end
check("mapa pequeno respeita os limites", tinyOk and tiny.count == 9, tiny.count)

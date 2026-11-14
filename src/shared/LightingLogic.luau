--!strict
-- Iluminação do mapa: onde ficam as luzes e quão fortes são ao longo do tempo
-- (puro, sem Instâncias — dá para testar fora do Studio).
--
-- Dois problemas reais que este módulo resolve:
--
--  1. LUZES "PISCANDO" AO ANDAR. Um `PointLight` com `Shadows = true` dentro
--     de um Part de 1 stud faz o motor recalcular o shadow map toda vez que
--     sua bounding box entra/sai do frustum. Com 6 luzes assim, o mapa
--     cintila ao caminhar. A saída é tirar o `Shadows` das luzes ambientes
--     (fonte de luz de preenchimento, não de tensão) e deixar sombra só na
--     lanterna do jogador.
--
--  2. LUZ CEGA E CHAPADA. Range 26 com teto a 16 studs vazava pelo teto e
--     pelas paredes, e a posição (raio 36) deixava o centro do mapa no escuro.
--     Aqui a posição é derivada do tamanho do mapa e da altura do teto.

local Config = require(script.Parent.Config)

local LightingLogic = {}

-- Quanto a luz "respira" (variação de brilho entre 0 e 1).
LightingLogic.FLICKER_DEPTH = 0.18

-- Quantas luzes, no máximo, para não estourar o orçamento de luzes.
LightingLogic.MAX_LIGHTS = 24

--- Posições (x, y, z) das luzes do teto, em grade.
---
--- Usa uma grade em vez de um círculo porque o mapa é retangular: um círculo
--- deixa as quinas escuras e o centro vazio.
--- `size` = lado do piso; `height` = altura do teto.
--- `true` se (x, z) cai dentro da pegada de algum pilar.
---
--- Uma luz pendurada sobre um pilar fica com o facho batendo na laje dele:
--- o pilar vira um bloco de luz estourada e o chão ao redor continua escuro.
--- `pillars` é a lista do MapBuilder ({ x, z, w, d }) — opcional.
local function insidePillar(x: number, z: number, pillars: { any }?, margin: number): boolean
	if not pillars then
		return false
	end

	for _, pillar in pillars do
		local px = tonumber(pillar.x)
		local pz = tonumber(pillar.z)
		local pw = tonumber(pillar.w)
		local pd = tonumber(pillar.d)

		if px and pz and pw and pd then
			if math.abs(x - px) <= pw / 2 + margin and math.abs(z - pz) <= pd / 2 + margin then
				return true
			end
		end
	end

	return false
end

function LightingLogic.lightPositions(
	size: number,
	height: number,
	count: number,
	pillars: { any }?
): { { number } }
	local total = math.max(1, math.floor(count))
	if total > LightingLogic.MAX_LIGHTS then
		total = LightingLogic.MAX_LIGHTS
	end

	-- A luz fica pendurada um pouco abaixo do teto, nunca colada nele.
	local y = height - 2

	local side = math.ceil(math.sqrt(total))
	if side < 1 then
		side = 1
	end

	-- As luzes ficam a 70% do meio-lado: perto o bastante das paredes para
	-- iluminar as quinas, longe o bastante para não encostar nelas.
	local spread = (size / 2) * 0.7
	local step = if side > 1 then (spread * 2) / (side - 1) else 0

	-- A luz tem raio de alcance, não é um ponto: encostada na lateral de um
	-- pilar ela já vira um clarão chapado na parede dele.
	local margin = 4

	-- Limite duro: nunca fora do piso (com folga para a parede).
	local limit = size / 2 - 4

	-- ------------------------------------------------------------------
	-- Estratégia: gerar candidatos na grade, descartar os inviáveis e
	-- escolher os melhores por pontuação.
	-- ------------------------------------------------------------------
	-- Tentar "empurrar" cada luz que caía num pilar era frágil: dois
	-- deslocamentos podiam convergir para o mesmo ponto (duas luzes na mesma
	-- posição) ou para fora do mapa. Aqui cada luz escolhe o melhor ponto
	-- livre de uma vez.
	local candidates: { { number } } = {}

	for row = 0, side - 1 do
		for column = 0, side - 1 do
			local baseX = if side > 1 then -spread + step * column else 0
			local baseZ = if side > 1 then -spread + step * row else 0

			-- Cada nó da grade oferece a si mesmo e quatro deslocamentos
			-- curtos. Pontuação menor = melhor (mais central para o nó).
			for _, offset in {
				{ baseX, baseZ, 0 },
				{ baseX + step * 0.5, baseZ, 1 },
				{ baseX - step * 0.5, baseZ, 1 },
				{ baseX, baseZ + step * 0.5, 1 },
				{ baseX, baseZ - step * 0.5, 1 },
				{ baseX + step * 0.5, baseZ + step * 0.5, 2 },
				{ baseX - step * 0.5, baseZ + step * 0.5, 2 },
				{ baseX + step * 0.5, baseZ - step * 0.5, 2 },
				{ baseX - step * 0.5, baseZ - step * 0.5, 2 },
			} do
				local x, z, cost = offset[1], offset[2], offset[3]
				local ok = math.abs(x) <= limit and math.abs(z) <= limit
					and not insidePillar(x, z, pillars, margin)

				if ok then
					table.insert(candidates, { x, z, cost })
				end
			end
		end
	end

	-- Ordena por custo; empate desempata pela distância até o centro (as
	-- luzes ficam mais úteis espalhadas, não empilhadas numa quina).
	table.sort(candidates, function(a, b)
		if a[3] ~= b[3] then
			return a[3] < b[3]
		end
		local da = a[1] * a[1] + a[2] * a[2]
		local db = b[1] * b[1] + b[2] * b[2]
		return da > db
	end)

	-- Distância mínima entre duas luzes: evita empilhar duas no mesmo canto.
	local minSpacing = if side > 1 then step * 0.45 else 0

	local out: { { number } } = {}

	for _, candidate in candidates do
		if #out >= total then
			break
		end

		local x, z = candidate[1], candidate[2]
		local tooClose = false

		for _, placed in out do
			local dx = placed[1] - x
			local dz = placed[3] - z
			if dx * dx + dz * dz < minSpacing * minSpacing then
				tooClose = true
				break
			end
		end

		if not tooClose then
			table.insert(out, { x, y, z })
		end
	end

	-- Rede de segurança: se a filtragem foi agressiva demais (mapa cheio de
	-- pilares), completa com as posições da grade que couberem. É melhor
	-- uma luz mal posicionada do que um salão às escuras.
	if #out < total then
		for row = 0, side - 1 do
			for column = 0, side - 1 do
				if #out >= total then
					break
				end

				local x = if side > 1 then -spread + step * column else 0
				local z = if side > 1 then -spread + step * row else 0
				local duplicate = false

				for _, placed in out do
					if math.abs(placed[1] - x) < 0.01 and math.abs(placed[3] - z) < 0.01 then
						duplicate = true
						break
					end
				end

				if not duplicate then
					table.insert(out, { x, y, z })
				end
			end
		end
	end

	return out
end

--- Brilho da luz `index` no instante `now`.
---
--- Devolve um valor entre `base * (1 - FLICKER_DEPTH)` e `base`. Cada luz tem
--- uma fase própria (derivada do índice), então elas não piscam em uníssono —
--- o que pareceria um bug, não uma atmosfera.
function LightingLogic.brightnessAt(base: number, index: number, now: number): number
	if base <= 0 then
		return 0
	end

	local depth = LightingLogic.FLICKER_DEPTH
	if depth <= 0 then
		return base
	end

	-- Duas senoides de períodos incomensuráveis: não repete visualmente.
	local phase = index * 2.399963 -- ângulo áureo (espalha as fases)
	local wave = math.sin(now * 0.9 + phase) * math.sin(now * 0.37 + phase * 1.7)

	-- `wave` está em [-1, 1]; normaliza para [0, 1].
	local normalized = (wave + 1) / 2

	return base * (1 - depth + depth * normalized)
end

--- `true` se esta luz deve projetar sombra.
---
--- Só a lanterna do jogador projeta sombra: as luzes ambientes com sombra são
--- a causa do mapa cintilando ao andar (recálculo de shadow map por frustum).
function LightingLogic.shouldCastShadow(isPlayerFlashlight: boolean): boolean
	return isPlayerFlashlight
end

return LightingLogic

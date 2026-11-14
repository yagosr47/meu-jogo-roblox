--!strict
-- Sorteio dos pontos dos fusíveis (puro, sem Instâncias).
--
-- Recebe a geometria do mapa como dados e devolve posições válidas. Fica no
-- lado compartilhado para poder ser testado: um sorteio que cai dentro de um
-- pilar deixaria o objetivo impossível de completar.

local Config = require(script.Parent.Config)

local FuseSpawner = {}

export type Vec3 = { x: number, y: number, z: number }

--- Obstáculo retangular no plano XZ (pilares).
export type Obstacle = {
	x: number,
	z: number,
	w: number,
	d: number,
}

export type SpawnOptions = {
	halfSize: number, -- metade do lado do piso
	obstacles: { Obstacle },
	spawn: Vec3,
	generator: Vec3,
	gate: Vec3,
}

local function distance2D(a: Vec3, b: Vec3): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

--- O ponto está dentro de (ou colado em) algum obstáculo?
function FuseSpawner.blocked(x: number, z: number, obstacles: { Obstacle }, padding: number): boolean
	for _, obstacle in obstacles do
		if math.abs(x - obstacle.x) < (obstacle.w / 2 + padding) and math.abs(z - obstacle.z) < (obstacle.d / 2 + padding) then
			return true
		end
	end

	return false
end

--- Um ponto é aceitável para um fusível?
function FuseSpawner.isValidPoint(point: Vec3, options: SpawnOptions, others: { Vec3 }): (boolean, string)
	local limit = options.halfSize - Config.FUSE_SPAWN_MARGIN

	if math.abs(point.x) > limit or math.abs(point.z) > limit then
		return false, "fora dos limites do piso"
	end

	if FuseSpawner.blocked(point.x, point.z, options.obstacles, 2.5) then
		return false, "dentro de um pilar"
	end

	if distance2D(point, options.spawn) < Config.FUSE_AVOID_SPAWN then
		return false, "perto do nascimento do jogador"
	end

	if distance2D(point, options.generator) < Config.FUSE_AVOID_GENERATOR then
		return false, "perto do gerador"
	end

	if distance2D(point, options.gate) < Config.FUSE_AVOID_GATE then
		return false, "perto do portão"
	end

	for _, other in others do
		if distance2D(point, other) < Config.FUSE_SPAWN_SEPARATION then
			return false, "perto demais de outro fusível"
		end
	end

	return true, "ok"
end

--- Sorteia `count` posições válidas.
---
--- `random` é injetável para os testes ficarem determinísticos.
--- Se não achar pontos suficientes em `attemptsPerFuse`, cai para uma grade
--- regular — o objetivo NUNCA pode ficar impossível.
function FuseSpawner.roll(options: SpawnOptions, count: number, random: (() -> number)?, attemptsPerFuse: number?): { Vec3 }
	local rng = random or math.random
	local attempts = attemptsPerFuse or 400
	local limit = options.halfSize - Config.FUSE_SPAWN_MARGIN

	local points: { Vec3 } = {}

	for _ = 1, count do
		local placed = false

		for _ = 1, attempts do
			local x = (rng() * 2 - 1) * limit
			local z = (rng() * 2 - 1) * limit
			local candidate: Vec3 = { x = x, y = 1.5, z = z }

			local ok = FuseSpawner.isValidPoint(candidate, options, points)
			if ok then
				table.insert(points, candidate)
				placed = true
				break
			end
		end

		if not placed then
			-- Fallback determinístico: varre uma grade e usa o primeiro livre.
			local fallback: Vec3? = nil
			local steps = 12

			for ix = 0, steps do
				for iz = 0, steps do
					local x = -limit + (2 * limit) * (ix / steps)
					local z = -limit + (2 * limit) * (iz / steps)
					local candidate: Vec3 = { x = x, y = 1.5, z = z }

					if FuseSpawner.isValidPoint(candidate, options, points) then
						fallback = candidate
						break
					end
				end

				if fallback then
					break
				end
			end

			if fallback then
				table.insert(points, fallback)
			else
				-- Último recurso: aceita sem as restrições de distância.
				table.insert(points, { x = -limit, y = 1.5, z = -limit })
			end
		end
	end

	return points
end

--- Verifica um conjunto já sorteado (usado nos testes e na inicialização).
function FuseSpawner.validate(points: { Vec3 }, options: SpawnOptions): (boolean, string)
	for index, point in points do
		local others: { Vec3 } = {}
		for otherIndex, other in points do
			if otherIndex ~= index then
				table.insert(others, other)
			end
		end

		local ok, reason = FuseSpawner.isValidPoint(point, options, others)
		if not ok then
			return false, `ponto {index}: {reason}`
		end
	end

	return true, "ok"
end

FuseSpawner.distance2D = distance2D

return FuseSpawner

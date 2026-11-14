--!strict
-- Servidor: pode ser clicado/solicitado por qualquer jogador, mas cada
-- requisição é validada em RaceService (ordem, distância real, ritmo).
--
-- Script de entrada do lado servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local RaceService = require(script.Parent.RaceService)

-- Assegura que o SpawnLocation da pista seja o respawn do jogador, mesmo que o
-- lugar tenha outro spawn (ex.: template padrão do Studio).
RaceService.start()

-- Marca como principal o spawn da pista.
do
	local raceCourse = Workspace:FindFirstChild("RaceCourse")
	local spawn = raceCourse and raceCourse:FindFirstChild("RaceSpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		for _, root in Workspace:GetChildren() do
			-- desativa outros SpawnLocations para o novo jogador nascer no RaceSpawn
			if root:IsA("SpawnLocation") and root ~= spawn then
				root.Enabled = false
			end
		end
	end
end

-- Roblox não tem um scheduler periódico nativo; usamos uma thread com
-- `task.wait` para limpar corridas expiradas.
task.spawn(function()
	while true do
		task.wait(5)
		local ok, err = pcall(RaceService.cleanup)
		if not ok then
			warn("[RaceServer] erro na limpeza:", err)
		end
	end
end)

-- Teleporte de segurança: se o jogador cair da pista, volta para o spawn.
-- (Sem isso, um jogador pode ficar preso no vazio.)
task.spawn(function()
	while true do
		task.wait(2)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and root.Position.Y < -50 then
				local spawn = Workspace:FindFirstChild("RaceCourse") and Workspace.RaceCourse:FindFirstChild("RaceSpawn")
				if spawn and spawn:IsA("SpawnLocation") then
					root.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
				end
			end
		end
	end
end)

print(string.format("[RaceServer] Pronto. %d checkpoints, corrida de até %ds.", Config.CHECKPOINT_COUNT, Config.RACE_TIME_LIMIT))

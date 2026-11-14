--!strict
-- Interação com o objetivo de fuga.
--
-- Os ProximityPrompt existem no mundo (criados pelo servidor), mas quem os
-- "liga" ao servidor aqui é o cliente. Regra: o cliente só manda INTENÇÃO
-- ("quero pegar o fusível 3", "quero instalar"). Distância, posse, tempo de
-- instalação e se o portão abriu são decididos no servidor.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local Remotes = require(shared.Remotes)

local player = Players.LocalPlayer
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

-- Estado espelhado do servidor (só para leitura).
local installing = false
local lastInstallAt = 0

local function fireCollect(fuseId: number)
	remotes[Remotes.CLIENT_TO_SERVER.COLLECT_FUSE]:FireServer(fuseId)
end

local function fireInstall(action: string)
	remotes[Remotes.CLIENT_TO_SERVER.INSTALL_FUSE]:FireServer(action)
end

-- ----------------------------------------------------------------------
-- Um único handler para todos os prompts: o nome do prompt decide a ação.
-- ----------------------------------------------------------------------
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggerPlayer: Player)
	if triggerPlayer ~= player then
		return
	end

	if prompt.Name == "CollectPrompt" then
		-- O prompt é filho do corpo do fusível; o servidor confere o id.
		local part = prompt.Parent
		local model = part and part:FindFirstAncestorOfClass("Model")

		if model and model.Name == "Fusivel" then
			local fuseId = model:GetAttribute("FuseId")
			if typeof(fuseId) == "number" then
				fireCollect(fuseId)
			end
		end
	elseif prompt.Name == "InstallPrompt" then
		local agora = os.clock()
		if (agora - lastInstallAt) < 0.3 then
			return
		end

		lastInstallAt = agora
		fireInstall("start")
	end
end)

-- ----------------------------------------------------------------------
-- Espelha o estado do servidor (nada é decidido aqui)
-- ----------------------------------------------------------------------
remotes[Remotes.SERVER_TO_CLIENT.ESCAPE_STATE].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	installing = payload.installing == true

end)

-- ----------------------------------------------------------------------
-- Cancelar quando o jogador se afasta do gerador no meio da instalação.
-- (O servidor também cancela por conta própria; isto só acelera a resposta.)
-- ----------------------------------------------------------------------
local generatorPart: BasePart? = nil

task.spawn(function()
	local objective = Workspace:WaitForChild("TerrorMap", 30)
	if not objective then
		return
	end

	local folder = objective:WaitForChild("ObjetivoFuga", 30)
	if not folder then
		return
	end

	-- O centro do gerador fica no atributo; se não houver, usa a Base.
	local generator = folder:WaitForChild("GeradorCentral", 30)
	if generator and generator:IsA("Model") and generator.PrimaryPart then
		generatorPart = generator.PrimaryPart
	end
end)

local abortDistance = Config.FUSE_INSTALL_ABORT_DISTANCE

task.spawn(function()
	while true do
		task.wait(0.4)

		if not installing then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local target = generatorPart

		if not root or not target or not root:IsA("BasePart") then
			continue
		end

		if (root.Position - target.Position).Magnitude > abortDistance then
			fireInstall("cancel")
		end
	end
end)

-- ----------------------------------------------------------------------
-- Fim da partida: solta tudo
-- ----------------------------------------------------------------------
remotes[Remotes.SERVER_TO_CLIENT.ESCAPED].OnClientEvent:Connect(function()
	installing = false
end)

player.CharacterAdded:Connect(function()
	installing = false
end)

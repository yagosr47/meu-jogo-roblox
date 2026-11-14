--!strict
-- Nomes e helpers dos RemoteEvents usados pelo sistema de corrida.
--
-- O servidor CRIA os remotes; o cliente ESPERA por eles. Assim não é preciso
-- colocar RemoteEvents no default.project.json.

local Remotes = {}

Remotes.FOLDER_NAME = "RaceRemotes"

-- Servidor -> cliente
Remotes.SERVER_TO_CLIENT = {
	RACE_STATE = "RaceStateChanged",
	RACE_FINISHED = "RaceFinished",
	LEADERBOARD = "LeaderboardUpdated",
	NOTIFY = "Notify",
}

-- Cliente -> servidor (tudo validado no servidor)
Remotes.CLIENT_TO_SERVER = {
	REQUEST_START = "RequestStart",
	CLAIM_CHECKPOINT = "ClaimCheckpoint",
	CANCEL_RACE = "CancelRace",
}

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--- Cria (ou reutiliza) a pasta de remotes. Só deve ser chamado no servidor.
function Remotes.createServerSide(parent: Instance): Folder
	local folder = ensureFolder(parent, Remotes.FOLDER_NAME)

	for _, name in Remotes.CLIENT_TO_SERVER do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	for _, name in Remotes.SERVER_TO_CLIENT do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	return folder
end

--- Espera a pasta de remotes no cliente e devolve um mapa nome -> RemoteEvent.
function Remotes.awaitClientSide(parent: Instance): { [string]: RemoteEvent }
	local folder = parent:WaitForChild(Remotes.FOLDER_NAME)

	local remotes: { [string]: RemoteEvent } = {}
	for _, name in Remotes.CLIENT_TO_SERVER do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end
	for _, name in Remotes.SERVER_TO_CLIENT do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end

	return remotes
end

--- No servidor, devolve o RemoteEvent pelo nome (erro claro se não existir).
function Remotes.getServerSide(folder: Folder, name: string): RemoteEvent
	local event = folder:FindFirstChild(name)
	if not event or not event:IsA("RemoteEvent") then
		error(`RemoteEvent ausente: {name}`, 2)
	end
	return event
end

return Remotes

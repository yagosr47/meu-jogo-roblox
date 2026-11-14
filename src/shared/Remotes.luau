--!strict
-- Nomes dos RemoteEvents e helpers de criação/espera.
--
-- O servidor CRIA os remotes; o cliente ESPERA por eles.

local Remotes = {}

Remotes.FOLDER_NAME = "TerrorRemotes"

-- Cliente -> servidor (tudo validado no servidor)
Remotes.CLIENT_TO_SERVER = {
	SET_SPRINTING = "SetSprinting",
	SET_FLASHLIGHT = "SetFlashlight",
	REQUEST_PICKUP = "RequestPickup",
	MONSTER_SOUND = "MonsterSound", -- ping de áudio para os outros jogadores
}

-- Servidor -> cliente
Remotes.SERVER_TO_CLIENT = {
	STATE = "StateChanged", -- estamina, bateria, lanterna
	PICKUP_RESULT = "PickupResult",
	CAUGHT = "Caught", -- jumpscare
	RESET = "ResetPlayer",
	MONSTER_STATE = "MonsterStateChanged",
	MONSTER_NEAR = "MonsterNear", -- ping de áudio remoto
	AMBIENT = "AmbientEvent", -- estímulos sonoros do mapa
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

--- Cria (ou reutiliza) a pasta de remotes. Só no servidor.
function Remotes.createServerSide(parent: Instance): Folder
	local folder = ensureFolder(parent, Remotes.FOLDER_NAME)

	local function ensure(name: string)
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end

	for _, name in Remotes.CLIENT_TO_SERVER do
		ensure(name)
	end
	for _, name in Remotes.SERVER_TO_CLIENT do
		ensure(name)
	end

	return folder
end

--- Espera a pasta de remotes no cliente: mapa nome -> RemoteEvent.
function Remotes.awaitClientSide(parent: Instance): { [string]: RemoteEvent }
	local folder = parent:WaitForChild(Remotes.FOLDER_NAME, 60)
	if not folder then
		error("TerrorRemotes não apareceu; o servidor não iniciou?")
	end

	local remotes: { [string]: RemoteEvent } = {}
	for _, name in Remotes.CLIENT_TO_SERVER do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end
	for _, name in Remotes.SERVER_TO_CLIENT do
		remotes[name] = folder:WaitForChild(name) :: RemoteEvent
	end

	return remotes
end

--- No servidor, pega um RemoteEvent pelo nome com erro claro.
function Remotes.getServerSide(folder: Folder, name: string): RemoteEvent
	local event = folder:FindFirstChild(name)
	if not event or not event:IsA("RemoteEvent") then
		error(`RemoteEvent ausente: {name}`, 2)
	end
	return event
end

return Remotes

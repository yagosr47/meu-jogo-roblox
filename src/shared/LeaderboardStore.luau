--!strict
-- Guarda os melhores tempos.
--
-- Toda a lógica (ordenação, limite, formato) fica aqui e é testável fora do
-- Roblox. `LeaderboardStore.new` recebe de fora as funções de carregar/salvar,
-- então o DataStore só é ligado no script de servidor.

local Config = require(script.Parent.Config)
local RaceLogic = require(script.Parent.RaceLogic)

export type Entry = { name: string, time: number }

export type Backend = {
	load: () -> { Entry }?,
	save: (entries: { Entry }) -> (),
}

local LeaderboardStore = {}
LeaderboardStore.__index = LeaderboardStore

export type Store = {
	entries: { Entry },
	add: (self: Store, name: string, time: number) -> (boolean, number?),
	getEntries: (self: Store) -> { Entry },
}

--- Valida um valor vindo do DataStore. Nunca confie no que está salvo:
--- o save pode ter sido escrito por uma versão antiga do jogo.
function LeaderboardStore.sanitizeEntries(raw: any): { Entry }
	local clean: { Entry } = {}
	if type(raw) ~= "table" then
		return clean
	end

	for _, item in ipairs(raw) do
		if type(item) == "table" then
			local name = item.name
			local time = item.time
			if type(name) == "string" and name ~= "" and #name <= 40 and type(time) == "number" and time == time and time > 0 and time < math.huge then
				table.insert(clean, { name = name, time = time })
			end
		end
	end

	return RaceLogic.sortLeaderboard(clean, Config.LEADERBOARD_SIZE)
end

function LeaderboardStore.new(backend: Backend?): Store
	local self = setmetatable({}, LeaderboardStore) :: any
	self.entries = {}

	if backend then
		local loaded = backend.load()
		self.entries = LeaderboardStore.sanitizeEntries(loaded)
	end

	self.backend = backend
	return self
end

--- Adiciona um tempo. Devolve `true` + a posição se entrou no ranking.
function LeaderboardStore:add(name: string, time: number): (boolean, number?)
	if type(name) ~= "string" or name == "" then
		return false, nil
	end

	if type(time) ~= "number" or time ~= time or time <= 0 or time >= math.huge then
		return false, nil
	end

	local combined: { Entry } = table.clone(self.entries)
	table.insert(combined, { name = name, time = time })

	local ranked = RaceLogic.sortLeaderboard(combined, Config.LEADERBOARD_SIZE)

	-- O tempo só "entrou" se estiver na lista final.
	local entered = false
	local position: number? = nil
	for index, entry in ipairs(ranked) do
		if entry.name == name and entry.time == time then
			entered = true
			position = index
			break
		end
	end

	if not entered then
		return false, nil
	end

	self.entries = ranked

	if self.backend then
		self.backend.save(ranked)
	end

	return true, position
end

function LeaderboardStore:getEntries(): { Entry }
	return table.clone(self.entries)
end

return LeaderboardStore

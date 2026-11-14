--!strict
-- Cliente: HUD da corrida (countdown, tempo, checkpoints, ranking e avisos).
--
-- IMPORTANTE: este script NÃO decide nada. Ele pede a largada e pede cada
-- checkpoint; quem aceita ou recusa é sempre o servidor. O tempo mostrado
-- aqui é só previsão visual (baseado no relógio do servidor).
--
-- Script de entrada do lado cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared.Config)
local RaceLogic = require(shared.RaceLogic)
local Remotes = require(shared.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = Remotes.awaitClientSide(ReplicatedStorage)

-- ----------------------------------------------------------------------
-- HUD
-- ----------------------------------------------------------------------

local COLORS = {
	bg = Color3.fromRGB(18, 20, 26),
	accent = Color3.fromRGB(90, 200, 255),
	good = Color3.fromRGB(90, 220, 120),
	warn = Color3.fromRGB(255, 180, 60),
	bad = Color3.fromRGB(255, 90, 90),
	text = Color3.fromRGB(240, 244, 250),
	muted = Color3.fromRGB(150, 158, 172),
}

local function makeLabel(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = COLORS.text
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = false

	for key, value in properties do
		(label :: any)[key] = value
	end

	label.Parent = parent
	return label
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RaceHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 280, 0, 150)
root.Position = UDim2.new(0, 20, 0, 20)
root.BackgroundColor3 = COLORS.bg
root.BackgroundTransparency = 0.15
root.BorderSizePixel = 0
root.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = root

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 12)
padding.Parent = root

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 6)
list.Parent = root

local titleLabel = makeLabel(root, "Title", {
	Size = UDim2.new(1, 0, 0, 20),
	Text = "CORRIDA",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = COLORS.accent,
	LayoutOrder = 1,
})

local phaseLabel = makeLabel(root, "Phase", {
	Size = UDim2.new(1, 0, 0, 16),
	Text = "Pressione F para largar",
	TextColor3 = COLORS.muted,
	TextSize = 14,
	LayoutOrder = 2,
})

local timerLabel = makeLabel(root, "Timer", {
	Size = UDim2.new(1, 0, 0, 34),
	Text = "00:00.00",
	Font = Enum.Font.GothamBold,
	TextSize = 30,
	LayoutOrder = 3,
})

local progressLabel = makeLabel(root, "Progress", {
	Size = UDim2.new(1, 0, 0, 16),
	Text = string.format("Checkpoint 0/%d", Config.CHECKPOINT_COUNT),
	TextColor3 = COLORS.muted,
	TextSize = 14,
	LayoutOrder = 4,
})

local notifyLabel = makeLabel(root, "Notify", {
	Size = UDim2.new(1, 0, 0, 18),
	Text = "",
	TextSize = 14,
	TextWrapped = true,
	LayoutOrder = 5,
})

local leaderboardFrame = Instance.new("Frame")
leaderboardFrame.Name = "Leaderboard"
leaderboardFrame.Size = UDim2.new(0, 220, 0, 40)
leaderboardFrame.Position = UDim2.new(1, -240, 0, 20)
leaderboardFrame.BackgroundColor3 = COLORS.bg
leaderboardFrame.BackgroundTransparency = 0.25
leaderboardFrame.BorderSizePixel = 0
leaderboardFrame.Parent = screenGui

local lbCorner = Instance.new("UICorner")
lbCorner.CornerRadius = UDim.new(0, 10)
lbCorner.Parent = leaderboardFrame

local lbPadding = Instance.new("UIPadding")
lbPadding.PaddingTop = UDim.new(0, 10)
lbPadding.PaddingLeft = UDim.new(0, 12)
lbPadding.PaddingRight = UDim.new(0, 12)
lbPadding.PaddingBottom = UDim.new(0, 10)
lbPadding.Parent = leaderboardFrame

local lbList = Instance.new("UIListLayout")
lbList.FillDirection = Enum.FillDirection.Vertical
lbList.SortOrder = Enum.SortOrder.LayoutOrder
lbList.Padding = UDim.new(0, 3)
lbList.Parent = leaderboardFrame

local lbTitle = makeLabel(leaderboardFrame, "LbTitle", {
	Size = UDim2.new(1, 0, 0, 18),
	Text = "MELHORES TEMPOS",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = COLORS.accent,
	LayoutOrder = 1,
})

local lbRows: { TextLabel } = {}
for index = 1, Config.LEADERBOARD_SIZE do
	local row = makeLabel(leaderboardFrame, "Row" .. index, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = "",
		TextSize = 12,
		TextColor3 = COLORS.muted,
		LayoutOrder = index + 1,
	})
	lbRows[index] = row
end

-- ----------------------------------------------------------------------
-- Estado local (só para exibição)
-- ----------------------------------------------------------------------

type LocalState = {
	phase: RaceLogic.Phase,
	nextIndex: number,
	totalCheckpoints: number,
	startedAt: number,
	serverNow: number,
	receivedAt: number,
	finishedAt: number?,
}

local state: LocalState = {
	phase = "Idle",
	nextIndex = 1,
	totalCheckpoints = Config.CHECKPOINT_COUNT,
	startedAt = 0,
	serverNow = 0,
	receivedAt = 0,
	finishedAt = nil,
}

local notifyToken = 0

local function notify(message: string, color: Color3?)
	notifyToken += 1
	local token = notifyToken
	notifyLabel.Text = message
	notifyLabel.TextColor3 = color or COLORS.text

	task.delay(3, function()
		if token == notifyToken then
			notifyLabel.Text = ""
		end
	end)
end

--- Estimativa do tempo decorrido: usa o relógio do servidor + o tempo local
--- desde que a última atualização chegou. Puro conforto visual.
local function estimateElapsed(): number
	if state.phase == "Finished" and state.finishedAt then
		return state.finishedAt
	end
	if state.phase ~= "Running" then
		return 0
	end
	local drift = os.clock() - state.receivedAt
	return math.max(0, (state.serverNow - state.startedAt) + drift)
end

local function render()
	if state.phase == "Running" then
		phaseLabel.Text = "Em andamento"
		phaseLabel.TextColor3 = COLORS.good
		timerLabel.Text = RaceLogic.formatTime(estimateElapsed())
		timerLabel.TextColor3 = COLORS.text
	elseif state.phase == "Countdown" then
		phaseLabel.Text = "Prepare-se..."
		phaseLabel.TextColor3 = COLORS.warn
		timerLabel.Text = "00:00.00"
		timerLabel.TextColor3 = COLORS.warn
	elseif state.phase == "Finished" then
		phaseLabel.Text = "Corrida concluída"
		phaseLabel.TextColor3 = COLORS.accent
		timerLabel.Text = RaceLogic.formatTime(state.finishedAt or 0)
		timerLabel.TextColor3 = COLORS.accent
	else
		phaseLabel.Text = "Pressione F para largar"
		phaseLabel.TextColor3 = COLORS.muted
		timerLabel.Text = "00:00.00"
		timerLabel.TextColor3 = COLORS.text
	end

	local done = math.clamp(state.nextIndex - 1, 0, state.totalCheckpoints)
	progressLabel.Text = string.format("Checkpoint %d/%d", done, state.totalCheckpoints)
end

-- ----------------------------------------------------------------------
-- RemoteEvents (cliente -> servidor)
-- ----------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		if state.phase == "Idle" or state.phase == "Finished" then
			remotes[Remotes.CLIENT_TO_SERVER.REQUEST_START]:FireServer()
		elseif state.phase == "Running" or state.phase == "Countdown" then
			remotes[Remotes.CLIENT_TO_SERVER.CANCEL_RACE]:FireServer()
		end
	end
end)

-- ----------------------------------------------------------------------
-- RemoteEvents (servidor -> cliente)
-- ----------------------------------------------------------------------

remotes[Remotes.SERVER_TO_CLIENT.RACE_STATE].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	state.phase = payload.phase or "Idle"
	state.nextIndex = tonumber(payload.nextIndex) or 1
	state.totalCheckpoints = tonumber(payload.totalCheckpoints) or Config.CHECKPOINT_COUNT
	state.startedAt = tonumber(payload.startedAt) or 0
	state.serverNow = tonumber(payload.serverNow) or 0
	state.finishedAt = tonumber(payload.finishedAt)
	state.receivedAt = os.clock()

	render()
end)

remotes[Remotes.SERVER_TO_CLIENT.NOTIFY].OnClientEvent:Connect(function(message: any, color: any)
	if type(message) == "string" then
		notify(message, if typeof(color) == "Color3" then color else nil)
	end
end)

remotes[Remotes.SERVER_TO_CLIENT.RACE_FINISHED].OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local formatted = if type(payload.formatted) == "string" then payload.formatted else RaceLogic.formatTime(tonumber(payload.time) or 0)

	if payload.died == true then
		notify("Tempo parcial: " .. formatted, COLORS.bad)
	elseif payload.entered == true and payload.position then
		notify(string.format("Chegou! %s (#%d do ranking)", formatted, tonumber(payload.position) or 0), COLORS.good)
	else
		notify("Seu tempo: " .. formatted, COLORS.good)
	end
end)

remotes[Remotes.SERVER_TO_CLIENT.LEADERBOARD].OnClientEvent:Connect(function(entries: any)
	if type(entries) ~= "table" then
		return
	end

	for index, row in lbRows do
		local entry = entries[index]
		if type(entry) == "table" and type(entry.name) == "string" and type(entry.time) == "number" then
			row.Text = string.format("%d. %s — %s", index, entry.name, RaceLogic.formatTime(entry.time))
			row.TextColor3 = if entry.name == player.Name then COLORS.good else COLORS.muted
		else
			row.Text = ""
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if state.phase == "Running" then
		timerLabel.Text = RaceLogic.formatTime(estimateElapsed())
	end
end)

render()

-- Dica inicial (a HUD já mostra tudo; SetCore pode falhar em alguns lugares
-- e não é essencial, por isso fica só como mensagem local).
notify("Fique no pad verde para largar. F cancela.", COLORS.muted)

print("[RaceClient] HUD carregado.")

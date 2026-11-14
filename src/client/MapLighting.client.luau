--!strict
-- Cintilação suave das luzes do mapa.
--
-- Roda SÓ no cliente e só mexe em `Brightness` (uma propriedade local de
-- renderização): não gera tráfego de rede nem faz o servidor recalcular nada.
-- Se fosse no servidor, cada mudança de brilho seria replicada para todos os
-- jogadores todo frame.
--
-- As luzes do mapa são criadas pelo `MapBuilder` com os atributos
-- `FlickerBase` e `FlickerIndex`; é por eles que este script as encontra.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared")
local LightingLogic = require(shared.LightingLogic)

type Tracked = {
	light: PointLight,
	base: number,
	index: number,
}

local tracked: { Tracked } = {}

--- (Re)descobre as luzes do mapa. Roda de vez em quando porque o servidor
--- pode reconstruir o mapa (e o `MapBuilder.build` recria tudo).
local function refresh()
	local map = Workspace:FindFirstChild("TerrorMap")
	if not map then
		return
	end

	tracked = {}

	for _, descendant in map:GetDescendants() do
		if descendant:IsA("PointLight") then
			local index = descendant:GetAttribute("FlickerIndex")
			local base = descendant:GetAttribute("FlickerBase")

			if type(index) == "number" and type(base) == "number" then
				table.insert(tracked, {
					light = descendant,
					base = base,
					index = index,
				})
			end
		end
	end
end

refresh()

-- Repassa as luzes de vez em quando: o mapa pode ser reconstruído.
task.spawn(function()
	while true do
		task.wait(3)
		local map = Workspace:FindFirstChild("TerrorMap")
		local stillValid = map ~= nil and #tracked > 0

		if stillValid then
			for _, entry in tracked do
				if not entry.light.Parent then
					stillValid = false
					break
				end
			end
		end

		if not stillValid then
			refresh()
		end
	end
end)

-- Um único `RenderStepped` para todas as luzes (em vez de um loop por luz).
RunService.RenderStepped:Connect(function()
	local now = os.clock()

	for _, entry in tracked do
		local light = entry.light
		if light.Parent then
			light.Brightness = LightingLogic.brightnessAt(entry.base, entry.index, now)
		end
	end
end)

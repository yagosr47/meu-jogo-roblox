--!strict
-- Helpers de UI: criação de instâncias com propriedades e pequenos widgets.
--
-- A HUD é montada em código (não em StarterGui) porque o Resolver do Rojo 7
-- não aceita UDim2 nas propriedades do default.project.json — só números,
-- strings, enums, Vector3/Color3 e CFrame.

local HudKit = {}

--- Cria uma instância com as propriedades dadas.
function HudKit.create(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className)

	for key, value in props do
		(instance :: any)[key] = value
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

--- Cria um TextLabel padrão da HUD.
function HudKit.label(props: { [string]: any }, parent: Instance?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.fromRGB(235, 238, 245),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = false,
	}

	for key, value in props do
		defaults[key] = value
	end

	return HudKit.create("TextLabel", defaults, parent) :: TextLabel
end

--- Painel escuro semi-transparente com cantos arredondados.
function HudKit.panel(props: { [string]: any }, parent: Instance?): Frame
	local merged: { [string]: any } = {
		BackgroundColor3 = Color3.fromRGB(12, 13, 18),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}

	for key, value in props do
		merged[key] = value
	end

	local frame = HudKit.create("Frame", merged, parent) :: Frame

	HudKit.create("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	return frame
end

--- Cria uma barra (fundo + preenchimento) e devolve as duas partes.
function HudKit.bar(props: { [string]: any }, parent: Instance?): (Frame, Frame)
	local merged: { [string]: any } = {
		BackgroundColor3 = Color3.fromRGB(30, 32, 40),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}

	for key, value in props do
		merged[key] = value
	end

	local back = HudKit.create("Frame", merged, parent) :: Frame
	HudKit.create("UICorner", { CornerRadius = UDim.new(0, 4) }, back)

	local fill = HudKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(90, 200, 255),
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
	}, back) :: Frame

	HudKit.create("UICorner", { CornerRadius = UDim.new(0, 4) }, fill)

	return back, fill
end

--- Cria uma ScreenGui limpa (sem duplicar ao respawnar).
function HudKit.screenGui(name: string, playerGui: PlayerGui, displayOrder: number?): ScreenGui
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	return HudKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
	}, playerGui) :: ScreenGui
end

--- Cor de 0..1 pela porcentagem (verde -> amarelo -> vermelho).
function HudKit.colorForRatio(ratio: number): Color3
	local r = math.clamp(ratio, 0, 1)
	if r > 0.5 then
		local t = (r - 0.5) * 2
		return Color3.fromRGB(math.floor(230 - 120 * t), math.floor(190 + 30 * t), 70)
	end

	local t = r * 2
	return Color3.fromRGB(230, math.floor(70 + 120 * t), 60)
end

return HudKit

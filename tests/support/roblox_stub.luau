--!nolint
-- Stub mínimo do Roblox, usado por `tests/test_mapbuilder.mjs` para EXECUTAR
-- o MapBuilder fora do Studio.
--
-- Não é um emulador: implementa só o que o MapBuilder toca (Instance com
-- Parent de verdade, FindFirstChild, GetDescendants, Destroy, serviços).
-- O objetivo é reproduzir o erro real "ModuleScript não carrega" que só
-- aparece em runtime — o compilador de sintaxe não pega nada disso.

-- Stub minimo e correto de Roblox: o suficiente para EXECUTAR o MapBuilder.
local Stub = {}

local function makeInstance(className)
	local tmpl = {
		ClassName = className,
		_children = {},
		_parent = nil,
		_destroyed = false,
	}

	local function findIn(node, name)
		for _, c in node._children do
			if c.Name == name then
				return c
			end
		end
		return nil
	end

	function tmpl:GetFullName()
		local n = self.Name
		local p = self._parent
		while p do
			n = p.Name .. "." .. n
			p = p._parent
		end
		return n
	end

	function tmpl:IsA(c)
		return c == self.ClassName
	end

	function tmpl:FindFirstChild(name)
		return findIn(self, name)
	end

	function tmpl:FindFirstChildOfClass(c)
		for _, ch in self._children do
			if ch.ClassName == c then
				return ch
			end
		end
		return nil
	end

	function tmpl:GetChildren()
		local out = {}
		for _, c in self._children do
			table.insert(out, c)
		end
		return out
	end

	function tmpl:GetDescendants()
		local out = {}
		local function walk(node)
			for _, c in node._children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end

	function tmpl:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		local p = self._parent
		if p then
			for i, c in p._children do
				if c == self then
					table.remove(p._children, i)
					break
				end
			end
		end
		self._parent = nil
	end

	function tmpl:WaitForChild(name, timeout)
		return findIn(self, name)
	end

	return setmetatable({}, {
		__index = function(self, key)
			if key == "Parent" then
				return rawget(self, "_parent")
			end
			return tmpl[key]
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				local old = rawget(self, "_parent")
				if old then
					for i, c in old._children do
						if c == self then
							table.remove(old._children, i)
							break
						end
					end
				end
				rawset(self, "_parent", value)
				if value then
					table.insert(value._children, self)
				end
				return
			end
			rawset(self, key, value)
		end,
	})
end

Stub.makeInstance = makeInstance

--- Cria os servicos falsos que o MapBuilder usa.
function Stub.install(opts)
	local env = {}

	env.Workspace = makeInstance("Workspace")
	env.Workspace.Name = "Workspace"
	env.Lighting = makeInstance("Lighting")
	env.Lighting.Name = "Lighting"
	env.ReplicatedStorage = makeInstance("ReplicatedStorage")
	env.ReplicatedStorage.Name = "ReplicatedStorage"

	-- Opcional: Shared/Config
	if opts and opts.withShared then
		local shared = makeInstance("Folder")
		shared.Name = "Shared"
		shared.Parent = env.ReplicatedStorage

		-- Sem `withoutConfig`: a pasta Shared existe mas o ModuleScript não
		-- (o caso de um Rojo meio conectado / projeto desatualizado).
		if not (opts and opts.withoutConfig) then
			local cfg = makeInstance("ModuleScript")
			cfg.Name = "Config"
			cfg.Parent = shared
			cfg.__value = opts.config or {}
		end
	end

	_G.game = {
		GetService = function(_, name)
			return env[name]
		end,
	}
	_G.Instance = {
		new = function(class)
			return makeInstance(class)
		end,
	}
	_G.Enum = setmetatable({}, {
		__index = function()
			return setmetatable({}, {
				__index = function()
					return setmetatable({}, {
						__index = function() return 0 end,
					})
				end,
			})
		end,
	})
	_G.Vector3 = {
		new = function(x, y, z)
			return {
				X = x, Y = y, Z = z,
				Magnitude = math.sqrt(x * x + y * y + z * z),
				__isVector = true,
			}
		end,
	}
	_G.Color3 = {
		fromRGB = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
	}
	_G.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		table.insert(_G.__warnings, table.concat(parts, " "))
	end
	_G.__warnings = {}

	return env
end



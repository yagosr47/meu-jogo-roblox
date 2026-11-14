"""Acha métodos de instância chamados com `.` em vez de `:`.

Uso:  python3 tests/check_method_calls.py

Em Luau, `obj:Metodo()` passa `obj` como `self`; `obj.Metodo()` **não**.
Chamar um método de instância com `.` levanta, em runtime:

    Expected ':' not '.' calling member function Pause

O compilador de sintaxe (`lua_compile`) NÃO detecta isso — é checagem
semântica, que o `@luau-rs/luau` não expõe. Este script fecha esse buraco:
foi assim que `sound.Pause()` no Movement passou por compilação, 203
asserções e dois checadores estruturais, e só apareceu no Studio.

Cuidado com os falsos positivos legítimos, que este script respeita:
  * `CFrame.new(...)`  — construtor estático
  * `Vector3.new(...)` — construtor estático
  * `string.format(...)`, `math.min(...)`, `table.clone(...)`
  * `Enum.Material.X`, `Color3.fromRGB(...)`
ou seja: funções de biblioteca, que realmente se chamam com `.`.
"""

import os
import re
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")

# Bibliotecas cujas funções são chamadas com `.` legitimamente.
BUILTIN_NAMESPACES = {
    "math", "string", "table", "os", "coroutine", "task", "utf8", "bit32",
    "CFrame", "Vector3", "Vector2", "Color3", "UDim", "UDim2", "Rect",
    "NumberSequence", "NumberSequenceKeypoint", "ColorSequence",
    "ColorSequenceKeypoint", "NumberRange", "TweenInfo", "Ray", "Region3",
    "Enum", "BrickColor", "Font", "DateTime", "Random", "PhysicalProperties",
    "Instance", "TweenService", "game", "workspace", "script", "shared",
}

# Nomes que o Luau/versões recentes expõem como função global.
BUILTIN_GLOBALS = {
    "require", "print", "warn", "error", "assert", "pcall", "xpcall", "select",
    "type", "typeof", "tostring", "tonumber", "ipairs", "pairs", "next",
    "unpack", "rawget", "rawset", "rawequal", "rawlen", "setmetatable",
    "getmetatable", "newproxy", "loadstring", "collectgarbage", "tick",
    "time", "wait", "spawn", "delay", "elapsedTime", "settings", "debug",
    "table", "math", "string", "os", "coroutine",
}

# Métodos de instância conhecidos do Roblox (o que este projeto usa).
ROBLOX_METHODS = {
    "Pause", "Resume", "Play", "Stop", "Destroy", "Clone", "ClearAllChildren",
    "FindFirstChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA",
    "FindFirstAncestor", "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA",
    "GetChildren", "GetDescendants", "GetAttribute", "SetAttribute",
    "GetAttributes", "GetPivot", "PivotTo", "SetPivot",
    "IsA", "IsDescendantOf", "WaitForChild",
    "FireServer", "FireClient", "FireAllClients", "InvokeServer",
    "Connect", "Disconnect", "Once", "Wait",
    "GetPlayers", "GetPlayerByUserId", "GetPlayerFromCharacter", "GetService",
    "Kick", "CharacterAppendCharacterToCharacterList",
    "ComputeAsync", "CreatePath", "GetWaypoints", "Raycast",
    "Lerp", "SetCore", "GetCore", "TakeScreenshot", "Create",
    "GetMass", "ApplyImpulse", "BreakJoints", "LoadCharacter",
    "MoveTo", "EquipTool", "UnequipTools", "GetDescendants",
    "GetFullName", "GetDebugId", "GetPropertyChangedSignal",
    "GetJoints", "GetTouchingParts", "SetNetworkOwner", "GetNetworkOwner",
    "ToWorldSpace", "ToObjectSpace", "PointToObjectSpace", "VectorToWorldSpace",
    "Angle", "Inverse", "Components", "GetComponents", "ToEulerAnglesXYZ",
}

CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(")

errors = []

for dirpath, _, files in os.walk(root):
    for fname in sorted(files):
        if not fname.endswith(".luau"):
            continue

        path = os.path.join(dirpath, fname)
        rel = os.path.relpath(path, os.path.dirname(root))

        with open(path, encoding="utf-8") as handle:
            for lineno, raw in enumerate(handle, 1):
                line = raw.split("--", 1)[0]  # descarta comentários

                for obj, method in CALL_RE.findall(line):
                    if obj in BUILTIN_NAMESPACES or obj in BUILTIN_GLOBALS:
                        continue
                    if method not in ROBLOX_METHODS:
                        continue

                    errors.append(
                        f"{rel}:{lineno}: `{obj}.{method}(` — método de instância "
                        f"chamado com '.', use `{obj}:{method}(`"
                    )

if errors:
    for err in errors:
        print("ERRO:", err)
    sys.exit(1)

print("OK: nenhum método de instância chamado com '.'")

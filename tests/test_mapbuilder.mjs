// Executa o MapBuilder REAL contra um stub mínimo do Roblox.
//
// Existe porque o erro que derrubou o servidor no Studio (`require` de um
// caminho inexistente dentro de ServerScriptService.Server) passa batido por
// compilação e por lint: ele só aparece quando o módulo realmente carrega.
// Aqui o módulo é carregado de verdade, em seis cenários.
//
// Uso:  npm install @luau-rs/luau && node tests/test_mapbuilder.mjs

import { Lua } from '@luau-rs/luau';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');

let stub = readFileSync(join(HERE, 'support', 'roblox_stub.luau'), 'utf8')
  .replace(/return Stub\s*$/, '')
  ;
stub += '\nStub = Stub\n';

let mb = readFileSync(join(ROOT, 'src', 'server', 'MapBuilder.luau'), 'utf8')
  .replace(/return MapBuilder\s*$/, '')
  .replace('local MapBuilder = {}', 'MapBuilder = {}')
  .replace('local ok, result = pcall(require, configModule)',
           'local ok, result = pcall(function() return configModule.__value end)')
  .replace(/ReplicatedStorage:WaitForChild\("Shared", 10\)/g, 'ReplicatedStorage:FindFirstChild("Shared")')
  .replace(/shared:WaitForChild\("Config", 10\)/g, 'shared:FindFirstChild("Config")');

// Forca Config nil quando o cenário não tem Shared: `local Config` recebe
// FALLBACK_CONFIG, que é o comportamento pretendido. Nada a fazer.

const CFG_FULL = `{
  MAP_FLOOR_SIZE = 120, MAP_WALL_HEIGHT = 16, MAP_WALL_THICKNESS = 2,
  MAP_LIGHT_COUNT = 6, MAP_LIGHT_BRIGHTNESS = 1.2, MAP_LIGHT_RANGE = 34,
  FALLBACK_PICKUP_POINTS = 10,
}`;

function buildSource({ stubOpts, before, body }) {
  return `
${stub}
local out = {}
local checks, passed = 0, 0
local function say(s) table.insert(out, tostring(s)) end
local function check(name, ok, detail)
  checks = checks + 1
  if ok then
    passed = passed + 1
  else
    say(string.format("[FALHA] %s%s", name, detail ~= nil and (" -> " .. tostring(detail)) or ""))
  end
end

local env = Stub.install(${stubOpts})
__warnings = {}
${before || ''}

${mb}

body()

say(string.format("RESULTADO: %d/%d passaram", passed, checks))
return table.concat(out, "\\n")
`.replace('body()', body);
}

const scenarios = [
  {
    name: 'A — tudo presente (caminho feliz)',
    stubOpts: `{ withShared = true, config = ${CFG_FULL} }`,
    body: `
local map = MapBuilder.build(env.Workspace)
check("pasta TerrorMap no Workspace", map.folder.Parent == env.Workspace)
check("chao", map.folder:FindFirstChild("Piso") ~= nil)
check("teto", map.folder:FindFirstChild("Teto") ~= nil)
check("4 paredes", map.folder:FindFirstChild("ParedeNorte") ~= nil
  and map.folder:FindFirstChild("ParedeSul") ~= nil
  and map.folder:FindFirstChild("ParedeLeste") ~= nil
  and map.folder:FindFirstChild("ParedeOeste") ~= nil)
check("5 pilares", map.folder:FindFirstChild("Pilar1") ~= nil and map.folder:FindFirstChild("Pilar5") ~= nil)
check("spawn StartSpawn", map.spawn.Name == "StartSpawn")
check("10 pontos de pilha", #map.pickupPoints == 10, #map.pickupPoints)
check("config real detectado", MapBuilder.hasRealConfig() == true)
check("sem avisos", #__warnings == 0, #__warnings)

MapBuilder.applyAtmosphere()
check("Atmosphere criado", env.Lighting:FindFirstChildOfClass("Atmosphere") ~= nil)

MapBuilder.build(env.Workspace)
local maps = 0
for _, c in env.Workspace:GetChildren() do
  if c.Name == "TerrorMap" then maps = maps + 1 end
end
check("build 2x nao duplica", maps == 1, maps)
`,
  },
  {
    name: 'B — ReplicatedStorage.Shared AUSENTE (o erro do Studio)',
    stubOpts: `{ withShared = false }`,
    body: `
local ok, err = pcall(function()
  local map = MapBuilder.build(env.Workspace)
  check("NAO estoura sem Shared", true)
  check("chao criado com fallback", map.folder:FindFirstChild("Piso") ~= nil)
  check("10 pontos (fallback)", #map.pickupPoints == 10, #map.pickupPoints)
  check("luzes (fallback)", map.folder:FindFirstChild("Luz1") ~= nil)
  check("fallback detectado", MapBuilder.hasRealConfig() == false)
  check("avisou o usuario", #__warnings >= 1, #__warnings)
  MapBuilder.applyAtmosphere()
  check("Atmosphere criado", env.Lighting:FindFirstChildOfClass("Atmosphere") ~= nil)
end)
if not ok then say("ESTOUROU: " .. tostring(err)) end
`,
  },
  {
    name: 'C — Config incompleto',
    stubOpts: `{ withShared = true, config = { MAP_FLOOR_SIZE = 80 } }`,
    body: `
MapBuilder.reloadConfig()
local map = MapBuilder.build(env.Workspace)
check("Config incompleto nao estoura", map.folder:FindFirstChild("Piso") ~= nil)
check("luzes com default", map.folder:FindFirstChild("Luz1") ~= nil)
check("pontos com default", #map.pickupPoints == 10, #map.pickupPoints)
`,
  },
  {
    name: 'C2 — Config com NaN/string/negativo',
    stubOpts: `{ withShared = true, config = { MAP_FLOOR_SIZE = 0/0, MAP_WALL_HEIGHT = "alto", MAP_LIGHT_COUNT = -5 } }`,
    body: `
MapBuilder.reloadConfig()
local map = MapBuilder.build(env.Workspace)
check("NaN/string/invalido nao estoura", map.folder:FindFirstChild("Piso") ~= nil)
check("luzes com default", map.folder:FindFirstChild("Luz1") ~= nil)
`,
  },
  {
    name: 'D — Workspace com lixo de sessao antiga',
    stubOpts: `{ withShared = true, config = ${CFG_FULL} }`,
    before: `
local lixo = Instance.new("Part")
lixo.Name = "TerrorMap"
lixo.Parent = env.Workspace
local spawnAntigo = Instance.new("SpawnLocation")
spawnAntigo.Name = "SpawnAntigo"
spawnAntigo.Enabled = true
spawnAntigo.Parent = env.Workspace
`,
    body: `
MapBuilder.reloadConfig()
local map = MapBuilder.build(env.Workspace)
check("TerrorMap virou Folder", map.folder.ClassName == "Folder")
check("spawn antigo desativado", spawnAntigo.Enabled == false)
`,
  },
  {
    name: 'F — Shared existe mas Config NAO (Rojo meio conectado)',
    stubOpts: `{ withShared = true, withoutConfig = true }`,
    body: `
local map = MapBuilder.build(env.Workspace)
check("nao estoura sem Config dentro de Shared", map.folder:FindFirstChild("Piso") ~= nil)
check("usa fallback", MapBuilder.hasRealConfig() == false)
check("pontos de pilha com default", #map.pickupPoints == 10, #map.pickupPoints)
check("avisou o usuario", #__warnings >= 1, #__warnings)
`,
  },
  {
    name: 'E — build(nil) e ensureFolder idempotente',
    stubOpts: `{ withShared = true, config = ${CFG_FULL} }`,
    body: `
MapBuilder.reloadConfig()
local map = MapBuilder.build(nil)
check("build(nil) usa Workspace", map.folder.Parent == env.Workspace)
local f1 = MapBuilder.ensureFolder(env.Workspace, "Teste")
local f2 = MapBuilder.ensureFolder(env.Workspace, "Teste")
check("ensureFolder idempotente", f1 == f2)
`,
  },
];

let totalPass = 0, totalChecks = 0, anyFail = false;

for (const sc of scenarios) {
  const lua = await Lua.create();
  lua.loadLibraries();
  const src = buildSource(sc);
  let result = '';
  try {
    const fn = lua.load(src, 'scenario');
    result = await fn.call();
  } catch (e) {
    anyFail = true;
    console.log(`\n### ${sc.name}\n  ERRO FATAL: ${String(e.message ?? e).split('\n')[0]}`);
    continue;
  }
  const lines = String(result).split('\n').filter(Boolean);
  const res = lines.find(l => l.startsWith('RESULTADO')) || '';
  const fails = lines.filter(l => l.startsWith('[FALHA]'));
  const m = res.match(/(\d+)\/(\d+)/);
  if (m) { totalPass += +m[1]; totalChecks += +m[2]; }
  if (fails.length) anyFail = true;
  console.log(`\n### ${sc.name}`);
  console.log('  ' + (res || 'sem resultado'));
  fails.forEach(f => console.log('  ' + f));
}

console.log(`\n=== TOTAL: ${totalPass}/${totalChecks} ===`);
if (anyFail || totalPass !== totalChecks) process.exitCode = 1;

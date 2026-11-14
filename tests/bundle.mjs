// Monta um bundle Luau executável com os módulos puros de src/shared,
// reescrevendo `require(script.Parent.X)` para um registry local.
//
// Uso: node tests/bundle.mjs && node tests/run.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const shared = join(root, 'src', 'shared');

const mods = ['Config', 'StaminaLogic', 'FlashlightLogic', 'MonsterAI', 'EscapeLogic', 'FuseSpawner', 'SprintIntent', 'LightingLogic'];

let out = 'local __mods: { [string]: any } = {}\n';
out += 'local function __require(name: string): any\n';
out += '\tlocal m = __mods[name]\n';
out += '\tif m == nil then error("modulo: " .. name) end\n';
out += '\tif type(m) == "function" then local v = m(); __mods[name] = v; return v end\n';
out += '\treturn m\nend\n\n';
out += 'local __out: {string} = {}\nlocal function __log(s: string) table.insert(__out, s) end\n\n';

for (const name of mods) {
  let src = readFileSync(join(shared, `${name}.luau`), 'utf8');
  src = src.replace(/require\(script\.Parent\.(\w+)\)/g, '__require("$1")');
  src = src.replace(/^--!strict\s*$/m, '');
  out += `__mods["${name}"] = function()\n${src}\nend\n\n`;
}

// O Luau limita registradores por script, entao os testes de iluminacao
// ficam num arquivo separado. Ele entra ANTES do trecho final do logic.spec
// que imprime o RESULTADO — senao o placar sairia zerado.
const logicSpec = readFileSync(join(here, 'logic.spec.luau'), 'utf8');
const marker = '__log(string.format("RESULTADO:';
const cut = logicSpec.indexOf(marker);
if (cut < 0) throw new Error('logic.spec.luau perdeu a linha de RESULTADO');

out += logicSpec.slice(0, cut);
out += readFileSync(join(here, 'lighting.spec.luau'), 'utf8');
out += '\n';
out += logicSpec.slice(cut);
out += '\nreturn table.concat(__out, "\\n")\n';

writeFileSync(join(here, 'bundle.luau'), out);
console.log('bundle gerado em tests/bundle.luau');

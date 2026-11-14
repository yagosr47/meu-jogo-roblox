// Roda tests/bundle.luau no Luau real (WASM) e imprime o resultado.
//
// Requer: npm install @luau-rs/luau
// Uso: node tests/bundle.mjs && node tests/run.mjs
import { Lua } from '@luau-rs/luau';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const lua = await Lua.create();
lua.loadLibraries();

let src = readFileSync(join(here, 'bundle.luau'), 'utf8');
// deixa o `error` final de fora para imprimir a lista completa
src = src.replace(/if failed > 0 then[\s\S]*?end/, '');

const fn = lua.load(src, 'bundle');
const out = await fn.call();
console.log(Array.isArray(out) ? out.join('\n') : String(out));

const text = Array.isArray(out) ? out.join('\n') : String(out);
process.exitCode = /0 falharam/.test(text) ? 0 : 1;

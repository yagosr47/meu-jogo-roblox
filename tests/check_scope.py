"""Checagem estreita: `local function NAME` chamado antes da declaracao.

Uso:  python3 tests/check_scope.py

Em Luau um `local` só existe a partir da linha da declaração. Chamar antes
pega o global (nil) e estoura em tempo de execução — o compilador de sintaxe
não reclama disso.

Este teste já pegou dois bugs reais: `collectPickup`/`spawnPickup` no
FlashlightService (coletar uma pilha derrubava o servidor com "attempt to call
a nil value") e `collect` no EscapeService.
"""
import os, re, sys

from pathlib import Path
root = str(Path(__file__).resolve().parent.parent / 'src')
errs = []

def strip(line):
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    line = re.sub(r'`[^`]*`', '``', line)
    return re.sub(r'--.*$', '', line)

for dirpath, _, files in os.walk(root):
    for fn in sorted(files):
        if not fn.endswith('.luau'): continue
        path = os.path.join(dirpath, fn)
        raw = open(path, encoding='utf-8').read().split('\n')

        # marca linhas dentro de blocos `export type X = { ... }` / `type X = {`
        in_type = [False] * len(raw)
        depth, active = 0, False
        for i, line in enumerate(raw):
            if not active and re.match(r'\s*(export\s+)?type\s+\w+\s*=', line):
                active = True; depth = 0
            if active:
                in_type[i] = True
                depth += line.count('{') - line.count('}')
                if depth <= 0 and '{' in ''.join(raw[max(0,i-40):i+1]):
                    active = False
                    in_type[i] = True

        decls = {}
        for i, line in enumerate(raw):
            m = re.match(r'\s*local\s+function\s+(\w+)', line)
            if m and not in_type[i]:
                decls.setdefault(m.group(1), i)

        for name, decl_line in decls.items():
            for i in range(decl_line):
                if in_type[i]: continue
                code = strip(raw[i])
                # chamada: NAME(  mas nao `function NAME(`
                if re.search(rf'(?<!function )\b{re.escape(name)}\s*\(', code):
                    errs.append(f'{path.replace(root+"/","")}:{i+1}: '
                                f'`{name}(` chamado antes de `local function {name}` (linha {decl_line+1})')
                    break

if errs:
    for e in errs: print('ERRO:', e)
    sys.exit(1)
print('OK: nenhuma funcao local chamada antes da declaracao')

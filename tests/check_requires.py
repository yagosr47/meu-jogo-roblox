"""Verifica que todo require() e' resolvivel na arvore do Rojo.

Uso:  python3 tests/check_requires.py

Pega erros que o compilador de sintaxe NAO pega: um `require(script.Parent.X)`
que aponta para um caminho que nao existe na arvore gerada pelo
default.project.json. Foi assim que um bug real passou uma vez: MapBuilder
fazia `script.Parent.Parent.shared.Config`, mas em ServerScriptService.Server
o avo e' ServerScriptService (sem `.shared`) — o servidor quebrava ao subir.

Este e' o bug que quase passou: MapBuilder fazia
`require(script.Parent.Parent.shared.Config)`, mas na arvore real ele vive em
ServerScriptService.Server -> script.Parent.Parent == ServerScriptService,
que nao tem .shared. Em jogo isso e' um erro na hora de subir o servidor.
"""
import json, os, re, sys

from pathlib import Path
root = str(Path(__file__).resolve().parent.parent)
proj = json.load(open(os.path.join(root, 'default.project.json')))

# 1. monta a arvore de instancias a partir do project.json
SYNC = [('.server.luau','Script'), ('.client.luau','LocalScript'),
        ('.luau','ModuleScript'), ('.lua','ModuleScript')]

def classify(fn):
    for suf, cls in SYNC:
        if fn.endswith(suf): return cls
    return None

def scan(rel):
    out = {}
    full = os.path.join(root, rel)
    for e in os.listdir(full):
        p = os.path.join(full, e)
        if os.path.isdir(p):
            out[e] = {'__class__': 'Folder', 'children': scan(os.path.join(rel, e))}
        else:
            cls = classify(e)
            if not cls: continue
            base = e
            for suf, _ in SYNC:
                if base.endswith(suf): base = base[:-len(suf)]; break
            out[base] = {'__class__': cls, 'file': os.path.join(rel, e), 'children': {}}
    return out

tree = {}
def build(node, dest):
    for key, child in node.items():
        if key.startswith('$'): continue
        if '$path' in child:
            dest[key] = {'__class__': 'Folder', 'children': scan(child['$path']), 'path': child['$path']}
        else:
            dest[key] = {'__class__': child.get('$className','Folder'), 'children': {}}
        build(child, dest[key]['children'])

build(proj['tree'], tree)

# 2. indice: arquivo -> caminho de instancia
index = {}
def index_tree(node, path):
    for key, child in node.items():
        here = path + [key]
        if 'file' in child:
            index[child['file']] = here
        index_tree(child['children'], here)
index_tree(tree, [])

def find(node, path):
    """responde se o caminho de instancias existe a partir da raiz"""
    cur = node
    for part in path:
        if part not in cur: return False
        cur = cur[part]['children']
    return True

errs = []
REQ = re.compile(r'require\(([^)]+)\)')

# Servicos do DataModel (raizes validas)
SERVICES = set(tree.keys())

# Aliases locais: `local shared = ReplicatedStorage:WaitForChild("Shared")`
# -> shared === ReplicatedStorage.Shared
ALIAS = re.compile(
    r'local\s+(\w+)\s*=\s*(?:(\w+)|game:GetService\("(\w+)"\))'
    r'(?::WaitForChild\("([\w]+)"\)|\[?"([\w]+)"\]?)'
)

for rel_file, inst_path in sorted(index.items()):
    src = open(os.path.join(root, rel_file), encoding='utf-8').read()

    aliases = {}
    for var, svc_var, svc_call, wc1, wc2 in ALIAS.findall(src):
        svc = svc_var or svc_call
        child = wc1 or wc2
        if svc in SERVICES and child:
            aliases[var] = [svc, child]

    for expr in REQ.findall(src):
        expr = expr.strip()

        # require(script.Parent.X) / require(script.Parent.Parent.shared.X)
        m = re.fullmatch(r'script((?:\.Parent)+)\.([\w.]+)', expr)
        if m:
            ups = m.group(1).count('.Parent')
            target = m.group(2).split('.')
            # o script esta' em inst_path; subir N niveis
            base = inst_path[:-ups] if ups <= len(inst_path) else None
            if base is None:
                errs.append(f'{rel_file}: {expr} -> sobe demais na arvore')
                continue
            if not find(tree, base + target):
                errs.append(
                    f'{rel_file}: {expr} -> {"/".join(base + target)} NAO EXISTE '
                    f'(script em {"/".join(inst_path)})')
            continue

        # require(ReplicatedStorage.Shared.X) / require(shared.X)
        m = re.fullmatch(r'(\w+)\.([\w.]+)', expr)
        if m:
            head, rest = m.group(1), m.group(2).split('.')
            if head in aliases:
                path = aliases[head] + rest
            else:
                path = [head] + rest
            if path[0] not in tree:
                errs.append(f'{rel_file}: servico {path[0]} nao existe na arvore ({expr})')
            elif not find(tree, path):
                errs.append(f'{rel_file}: {expr} -> {".".join(path)} NAO EXISTE')
            continue

        errs.append(f'{rel_file}: require nao reconhecido: {expr}')

if errs:
    for e in errs: print('ERRO:', e)
    sys.exit(1)
print(f'OK: todos os requires resolvem ({len(index)} scripts na arvore)')

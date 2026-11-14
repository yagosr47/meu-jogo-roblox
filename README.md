# meu-jogo-roblox

Projeto de Roblox estruturado com [Rojo](https://rojo.space).

## Estrutura

| Pasta no disco                | Onde aparece no Roblox Studio            |
| ----------------------------- | ---------------------------------------- |
| `src/ServerScriptService`     | `ServerScriptService`                    |
| `src/ReplicatedStorage`       | `ReplicatedStorage`                      |
| `src/StarterPlayerScripts`    | `StarterPlayer > StarterPlayerScripts`   |
| `src/StarterGui`              | `StarterGui`                             |

O mapeamento fica em `default.project.json`.

## Como usar

1. Instale o Rojo (uma das opções):
   - Com [Rokit](https://github.com/rojo-rbx/rokit) (recomendado, a versão já está fixada em `rokit.toml`):

     ```bash
     rokit install
     ```

   - Com [Aftman](https://github.com/LPGhatguy/aftman) ou baixando o binário na
     página de [releases do Rojo](https://github.com/rojo-rbx/rojo/releases).

2. Instale o plugin do Rojo no Roblox Studio
   (o próprio `rojo serve` mostra o link para instalar).

3. Suba o servidor do Rojo na raiz do projeto:

   ```bash
   rojo serve
   ```

4. No Studio, abra o plugin do Rojo e clique em **Connect**.

Ao conectar, o script `Init.server.luau` roda e o **Output** (View → Output)
mostra a mensagem:

```
Conexão Rojo + Arena AI funcionando!
```

## Alternativa: gerar um lugar `.rbxlx`

Em vez de sincronizar ao vivo, você pode gerar um arquivo de lugar já montado:

```bash
rojo build -o meu-jogo-roblox.rbxlx
```

Depois é só abrir o `meu-jogo-roblox.rbxlx` no Roblox Studio.

## Notas

- `Init.server.luau` (com **I** maiúsculo) gera um `Script` chamado `Init`
  dentro do serviço `ServerScriptService`. Isso é proposital: é o `print` que
  aparece no Output.
- O Rojo reserva o nome `init.server.luau` (minúsculo). Se você renomear o
  arquivo para minúsculo, a pasta `src/ServerScriptService` deixa de ser um
  `Folder` e a **própria pasta** vira o `Script`. Por isso, mantenha o `I`
  maiúsculo.
- Os arquivos `.gitkeep` existem só para o Git versionar as pastas vazias.
  O Rojo ignora esse nome.

### Se aparecer `ServerScriptService` como Script (Windows/macOS)

Windows e macOS usam sistema de arquivos que não diferencia maiúsculas de
minúsculas, então o Rojo pode interpretar `Init.server.luau` como o
`init.server.luau` reservado. Se no Explorer o `ServerScriptService` aparecer
como `Script` em vez de serviço, troque o nó no `default.project.json` por:

```json
"ServerScriptService": {
  "$className": "ServerScriptService",
  "Init": {
    "$path": "src/ServerScriptService/Init.server.luau"
  }
}
```

Assim o `Script` chamado `Init` fica dentro do `ServerScriptService` em
qualquer sistema operacional, e outros arquivos dentro de
`src/ServerScriptService` continuam entrando como filhos do `Init`.

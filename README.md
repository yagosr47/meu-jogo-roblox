# meu-jogo-roblox

Projeto de Roblox com [Rojo](https://rojo.space) e o sistema de **Checkpoint / Corrida**.

## O que o jogo faz

1. Ao entrar, o jogador nasce no **pad verde** ("StartPad").
2. Ficando no pad (ou apertando **F**), começa um countdown de 3 segundos.
3. Ao largar, o cronômetro começa. O jogador precisa passar por **5 checkpoints
   em ordem**; o último é a linha de chegada.
4. Quem chega tem o tempo registrado no ranking (top 10), que aparece no canto da
   tela e é salvo no **DataStore** quando possível.

## Estrutura

| Pasta no disco   | Onde aparece no Studio                        |
| ---------------- | --------------------------------------------- |
| `src/server`     | `ServerScriptService > Server`                |
| `src/client`     | `StarterPlayer > StarterPlayerScripts > Client` |
| `src/shared`     | `ReplicatedStorage > Shared`                  |

Regras de nome do Rojo:

- `*.server.luau` → `Script` (servidor)
- `*.client.luau` → `LocalScript` (cliente)
- `*.luau` → `ModuleScript`
- ~~`init.*.luau`~~ — **evitado de propósito** (veja "Notas")

### Arquivos

```
src/
├── server/
│   ├── RaceServer.server.luau   -- entrada do servidor (start + loops)
│   ├── RaceService.luau         -- estado por jogador + validação dos RemoteEvents
│   ├── RaceServerLogic.luau     -- regras de progressão (testável sem Roblox)
│   └── CourseBuilder.luau       -- cria pista, pad e checkpoints em runtime
├── client/
│   └── RaceClient.client.luau   -- HUD: cronômetro, progresso, ranking, avisos
└── shared/
    ├── Config.luau              -- constantes (checkpoints, limites, geometria)
    ├── RaceLogic.luau           -- regras puras + `evaluateClaim` (validação)
    ├── LeaderboardStore.luau    -- ranking top 10, com sanitização
    ├── Remotes.luau             -- criação/espera dos RemoteEvents
    └── Models/RaceRemotes.model.json
```

## Como rodar

```bash
rokit install   # instala o Rojo 7.7.1 fixado em rokit.toml
rojo serve
```

No Studio: plugin do Rojo → **Connect**. O jogo monta a pista sozinho.

Alternativa, sem live sync:

```bash
rojo build -o meu-jogo-roblox.rbxlx
```

> **DataStore:** `Config.USE_DATASTORE = true` por padrão. Em Studio sem
> "Enable Studio Access to API Services", o ranking funciona normalmente mas só
> em memória (é emitido um aviso no Output). Para desligar de vez, mude para
> `false`.

## Segurança: o que é validado no servidor

O cliente **nunca** é fonte de verdade. Ele só envia `RequestStart`,
`ClaimCheckpoint(n)` e `CancelRace`; todo o resto é decidido no servidor
(`RaceLogic.evaluateClaim`, coberto por testes):

| Verificação | Como |
| --- | --- |
| Corrida existe e está valendo | `phase == "Running"` |
| Jogador vivo e com personagem | `Humanoid.Health > 0` + `HumanoidRootPart` |
| Índice do checkpoint é válido | inteiro, não-NaN, dentro de `1..total` |
| Ordem dos checkpoints | `claimed == nextIndex` (pular etapa é recusado) |
| **Distância real** | calculada no servidor com a posição do personagem (o cliente não informa posição) |
| Tempo mínimo entre checkpoints | `MIN_SECONDS_PER_CHECKPOINT` |
| Rajada de requisições | `MAX_CLAIMS_PER_WINDOW` por `CLAIM_WINDOW_SECONDS` |
| Inundação de remotes | teto global por jogador (`MAX_REMOTE_CALLS_PER_SECOND`) |
| Corrida expirada | `RACE_TIME_LIMIT` |
| Largada no lugar certo | distância do pad medida no servidor |
| Dados do DataStore | `LeaderboardStore.sanitizeEntries` (descarta nome/time inválidos) |

Além disso: `onPlayerRemoving` limpa a sessão, e uma rede de segurança no loop
do servidor fecha a corrida de quem chega ao checkpoint final sem claim.

## Testes

As regras ficam em módulos puros (`RaceLogic`, `RaceServerLogic`,
`LeaderboardStore`), sem Instâncias, para rodarem fora do Roblox. A suíte cobre
73 casos: ordem, teleporte, índice forjado, NaN/string, rajada, expiração,
ranking cheio, dados corrompidos do DataStore e uma corrida completa.

## Notas

- **Por que não `init.server.luau`?** O Rojo reserva esse nome: a pasta que o
  contém passa a *ser* o script. Além disso, em Windows/macOS (case-insensitive)
  `Init.server.luau` pode ser confundido com o nome reservado. Por isso os
  entrypoints são `RaceServer.server.luau` e `RaceClient.client.luau`.
- **Checkpoints em runtime:** as partes da pista não ficam no
  `default.project.json`; o `CourseBuilder` as cria no `Workspace` ao iniciar.
  Assim os números de configuração ficam em um só lugar (`Config.luau`).
- **Baseplate:** o `default.project.json` inclui uma base abaixo da pista. Se você
  usar o template padrão do Studio (com o `Baseplate` dele), apenas remova o nó
  `Baseplate` do projeto para não duplicar.

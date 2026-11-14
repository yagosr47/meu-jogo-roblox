# meu-jogo-roblox

Jogo de terror em primeira pessoa feito em Luau + [Rojo](https://rojo.space).

## O que tem no jogo

**1. Atmosfera, iluminação e movimentação**
- `Lighting` escuro, neblina densa (objeto `Atmosphere` com `Density 0.42` e `Haze 3.2`, declarado no `default.project.json`).
- Câmera travada em primeira pessoa (`StarterPlayer.CameraMode = LockFirstPerson`).
- **View bobbing**: balanço vertical/horizontal + leve inclinação ao andar, mais abertura de FOV ao correr.
- **Sprint com Shift** + barra de estamina na tela.
- **Respiração ofegante** quando a estamina está baixa (som procedural, sem asset externo).

**2. Lanterna com bateria e pilhas**
- Tecla **F**. A bateria é do servidor e vai caindo enquanto a luz está ligada.
- Abaixo de **20%** a lanterna pisca; ao **zerar**, apaga e não liga mais.
- Pilhas coletáveis espalhadas pelo mapa (`Workspace.BatteryPickups`) com `ProximityPrompt`, reposição automática, validação de distância e de ritmo no servidor.

**3. IA do monstro**
- Patrulha por pontos com `PathfindingService`.
- Detecta por **linha de visão** (raycast com FOV) e por **som** (ouve quem está correndo de longe, quem anda só de perto).
- Inicia perseguição com **música de tensão** no cliente, e ao encostar aplica **jumpscare** (tela + morte).
- Toda detecção, movimento e dano rodam no servidor.

## Estrutura

| Disco | Studio |
| --- | --- |
| `src/server` | `ServerScriptService > Server` |
| `src/client` | `StarterPlayer > StarterPlayerScripts > Client` |
| `src/shared` | `ReplicatedStorage > Shared` |

```
src/
├── server/
│   ├── TerrorServer.server.luau   -- entrada: mapa, remotes, serviços, loop
│   ├── MapBuilder.luau            -- sala fechada, pilares, luzes, pontos
│   ├── PlayerState.luau           -- estado autoritativo por jogador
│   ├── FlashlightService.luau     -- lanterna + gerador de pilhas
│   └── MonsterService.luau        -- patrulha, percepção, perseguição, captura
├── client/
│   ├── Movement.client.luau       -- 1ª pessoa, bobbing, sprint, estamina, respiração
│   ├── Flashlight.client.luau     -- luz (SpotLight), HUD de bateria, piscada
│   ├── MonsterFx.client.luau      -- música de tensão, vinheta, jumpscare
│   └── HudKit.luau                -- helpers de UI (a HUD é montada em código)
└── shared/
    ├── Config.luau                -- TODOS os números do jogo
    ├── StaminaLogic.luau          -- regras de estamina (puro)
    ├── FlashlightLogic.luau       -- regras de bateria/piscada (puro)
    ├── MonsterAI.luau             -- percepção e decisão do monstro (puro)
    └── Remotes.luau               -- nomes e criação dos RemoteEvents
```

## Como rodar

```bash
rokit install   # Rojo 7.7.1 (fixado em rokit.toml)
rojo serve
```

No Studio: plugin do Rojo → **Connect**.

Alternativa sem live sync:

```bash
rojo build -o meu-jogo-roblox.rbxlx
```

### Controles
| Tecla | Ação |
| --- | --- |
| WASD | andar |
| Shift | correr (gasta estamina) |
| F | lanterna |
| E | pegar pilha (ProximityPrompt) |

## Como a segurança é feita

O cliente **nunca** é fonte de verdade. Ele só declara intenção; o servidor
decide. As regras ficam em módulos puros (`src/shared`) justamente para serem
testáveis sem Roblox.

| Risco | Defesa |
| --- | --- |
| Cliente diz "estou correndo" sem estamina | Servidor checa `canSprint` e aplica `WalkSpeed` ele mesmo |
| Cliente informa posição | Nunca usada: distância é medida com o `HumanoidRootPart` no servidor |
| Cliente pega pilha de longe | `ProximityPrompt` + raio máximo conferido no servidor |
| Farm de pilhas | Limite por minuto e reposição com atraso |
| Spam de RemoteEvents | Rate limit por jogador e cooldown de toggle |
| Cliente diz "o monstro não me viu" | Percepção (`raycast` + som) roda só no servidor |
| Cliente diz "peguei o monstro" | Captura por distância no servidor, com cooldown |
| Dados inválidos / NaN | Entradas normalizadas nas regras puras |
| Morrer e ficar travado | `Died` limpa o estado "pego"; respawn devolve velocidade |

O visual é decidido no servidor porque todas as funções de regra são
**determinísticas**: a mesma função `getLightState(state, now)` roda nos dois
lados, então o cliente desenha exatamente o que o servidor considera verdade.

## Testes

As regras (estamina, bateria, IA e geometria do mapa) rodam no Luau real, fora
do Roblox:

```bash
npm install @luau-rs/luau
node tests/bundle.mjs
node tests/run.mjs
```

**104 asserções**, cobrindo: drenagem/regeneração/cansaço, recarga limitada ao
espaço, piscada determinística, FOV/visão/audição do monstro, transições
patrulha↔perseguição, captura com cooldown, waypoints fora de pilares e uma
corrida completa de estamina.

> Os testes já pegaram três bugs reais durante o desenvolvimento: jogador preso
> em cansaço no limiar, waypoint dentro de um pilar, e a câmera "afundando"
> por compor o offset de bobbing a cada frame.

## Notas de implementação

- **A HUD é montada em código**, não em `StarterGui` no projeto: o Resolver do
  Rojo 7 só aceita números, strings, enums, `Vector3`/`Color3` e `CFrame` nas
  propriedades — `UDim2` e `NumberSequence` não são suportados.
- **O mapa é construído em runtime** (`MapBuilder`), o que mantém a geometria
  junto do `Config.luau` e permite validar waypoints nos testes.
- **Nada de `init.*.luau`**: esse nome faz a pasta virar o próprio Script no
  Rojo (e em Windows/macOS pode ser confundido com o nome reservado).
- **Sons procedurais**: os efeitos usam assets locais que acompanham o cliente
  do Roblox (`rbxasset://sounds/...`), então não é preciso publicar áudio. Se
  algum asset não existir na sua versão do cliente, o `pcall` ignora e o jogo
  segue sem som.
- **`Atmosphere` e névoa** estão declarados no projeto; o `MapBuilder` reforça
  os valores em runtime e cria um `Atmosphere` só se faltar.

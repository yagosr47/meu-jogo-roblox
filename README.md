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

**3. Objetivo principal: escapar**
- **5 fusíveis** são sorteados em pontos aleatórios do mapa a cada partida (nunca dentro de pilares, do gerador ou em cima do nascimento).
- Cada jogador carrega **só 1 fusível por vez** (vários jogadores podem carregar ao mesmo tempo).
- Instalar no **Gerador Central** leva **3 segundos** com barra de progresso; sair de perto, morrer ou desconectar cancela.
- Com os **5 instalados**, o **Portão de Saída** abre sozinho; cruzar a linha vence a partida.
- O progresso é compartilhado (co-op): o que um instalou conta para todos, mas a mão é de cada um.
- Tudo validado no servidor: distância, posse do fusível, tempo da barra e abertura do portão.

**4. IA do monstro**
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
│   ├── EscapeService.luau         -- fusíveis, gerador, portão, vitória
│   ├── EscapeBuilder.luau         -- geometria do gerador/portão/fusível
│   └── MonsterService.luau        -- patrulha, percepção, perseguição, captura
├── client/
│   ├── Movement.client.luau       -- 1ª pessoa, bobbing, sprint, estamina, respiração
│   ├── Flashlight.client.luau     -- luz (SpotLight), HUD de bateria, piscada
│   ├── EscapeHud.client.luau      -- contador de fusíveis, barra de 3s, avisos
│   ├── EscapeInteract.client.luau -- prompts de coleta/instalação
│   ├── MonsterFx.client.luau      -- música de tensão, vinheta, jumpscare
│   └── HudKit.luau                -- helpers de UI (a HUD é montada em código)
└── shared/
    ├── Config.luau                -- TODOS os números do jogo
    ├── StaminaLogic.luau          -- regras de estamina (puro)
    ├── FlashlightLogic.luau       -- regras de bateria/piscada (puro)
    ├── EscapeLogic.luau           -- regras da fuga (puro)
    ├── FuseSpawner.luau           -- sorteio dos pontos dos fusíveis (puro)
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
| E | pegar pilha / pegar fusível (ProximityPrompt) |
| E no gerador | instalar o fusível (3 s) |

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
| Cliente diz "peguei o fusível" | O cliente manda só o **id**; o servidor confere se aquele fusível existe, está no mapa e se o jogador está perto |
| Cliente carrega 2+ fusíveis | `canCollect` confere `holders[userId]`: 1 por jogador |
| Jogador instala o fusível de outro | `canStartInstall` exige `holders[userId]`, e o fim só vale para quem começou |
| Cliente diz "instalei" | O cliente só pede para **começar**; o fim é decidido pelo relógio do servidor (`installProgress >= 1`) e pela distância |
| Cliente abre o portão sozinho | O portão só abre em `completeInstall` com os 5 instalados, no servidor |
| Cliente finge ter vencido | Vitória exige `gateOpen` + estar dentro da boca do portão, medido no servidor |
| Jogador desconecta com fusível | O fusível **volta ao mapa** (não é perdido) e a instalação é cancelada |
| Cliente diz "o monstro não me viu" | Percepção (`raycast` + som) roda só no servidor |
| Cliente diz "peguei o monstro" | Captura por distância no servidor, com cooldown |
| Dados inválidos / NaN | Entradas normalizadas nas regras puras |
| Morrer e ficar travado | `Died` limpa o estado "pego"; respawn devolve velocidade |

O visual é decidido no servidor porque todas as funções de regra são
**determinísticas**: a mesma função `getLightState(state, now)` roda nos dois
lados, então o cliente desenha exatamente o que o servidor considera verdade.

## Testes

As regras (estamina, bateria, fuga, IA e geometria do mapa) rodam no Luau real,
fora do Roblox:

```bash
npm install @luau-rs/luau
node tests/bundle.mjs
node tests/run.mjs
```

**203 asserções**, cobrindo: drenagem/regeneração/cansaço, recarga limitada ao
espaço, piscada determinística, FOV/visão/audição do monstro, transições
patrulha↔perseguição, captura com cooldown, waypoints fora de pilares, uma
corrida completa de estamina e **todo o fluxo da fuga**: 5 fusíveis, limite de
1 na mão, barra de 3 s, cancelamento por distância, abertura do portão, vitória,
devolução de fusível e co-op.

Há ainda testes estruturais (Python, sem dependências) e um teste que executa
o `MapBuilder` de verdade:

```bash
python3 tests/check_requires.py     # todo require() aponta para um caminho real
python3 tests/check_scope.py        # nenhuma `local function` chamada antes de existir
python3 tests/check_method_calls.py # nenhum método chamado com '.' no lugar de ':'
node tests/test_mapbuilder.mjs      # carrega o MapBuilder contra um stub do Roblox
```

- **`check_requires`** confere cada `require` contra a árvore gerada pelo
  `default.project.json`.
- **`check_scope`** acha `local function` chamada antes da declaração — em Luau
  isso vira `nil` em tempo de execução e o compilador não avisa.
- **`check_method_calls`** acha método de instância chamado com `.` (`sound.Pause()`
  em vez de `sound:Pause()`). Isso é erro semântico: `lua_compile` aceita, e só
  estoura em runtime com `Expected ':' not '.' calling member function`.
- **`test_mapbuilder`** roda o módulo real contra um stub mínimo do Roblox
  (`tests/support/roblox_stub.luau`) em 7 cenários: tudo presente, `Shared`
  ausente, `Config` ausente dentro de `Shared`, Config incompleto, Config com
  valores inválidos, Workspace com lixo de sessão antiga e `build(nil)`.
  É o único tipo de teste que pega erro de **carregamento** de módulo — que foi
  justamente o que derrubou o servidor no Studio.

> Os testes já pegaram bugs reais: jogador preso em cansaço no limiar, waypoint
> dentro de um pilar, a câmera "afundando" por compor o offset de bobbing a cada
> frame, um fusível que ficava **perdido para sempre** quando o portador saía,
> um `require` de `Config` no `MapBuilder` que apontava para um caminho
> inexistente (derrubaria o servidor inteiro ao subir), e **dois** no
> `FlashlightService`: `collectPickup`/`spawnPickup` eram chamados antes de
> serem declarados, então pegar uma pilha derrubava o servidor com
> `attempt to call a nil value`, e — o mais sutil — `{ campo = nil }` não
> apaga uma chave em Lua, o que travava a **segunda** instalação de fusível com
> "já está instalando".
>
> O `test_mapbuilder` também pegou um erro que eu tinha acabado de introduzir
> ao escrever o fallback: `cfg()` era definida **antes** de `local Config`, então
> `Config` dentro dela era o global `nil` e o módulo estourava em `attempt to
> index nil`. Compilação e lint não acusam isso — só a execução.

## Notas de implementação

- **A HUD é montada em código**, não em `StarterGui` no projeto: o Resolver do
  Rojo 7 só aceita números, strings, enums, `Vector3`/`Color3` e `CFrame` nas
  propriedades — `UDim2` e `NumberSequence` não são suportados.
- **O mapa é construído em runtime** (`MapBuilder`), o que mantém a geometria
  junto do `Config.luau` e permite validar waypoints nos testes.
- **`MapBuilder` nunca derruba o servidor.** Se `ReplicatedStorage.Shared.Config`
  não existir (Rojo desconectado, projeto desatualizado), ele usa um Config
  embutido e segue com um `warn`; se uma pasta estiver faltando ou tiver a
  classe errada, `ensureFolder`/`ensureChild` criam ou substituem na hora. Um
  cenário feio é melhor do que um servidor que não sobe. `MapBuilder.reloadConfig()`
  reavalia tudo, então dá para reconectar o Rojo sem reiniciar.
- **Nada de `init.*.luau`**: esse nome faz a pasta virar o próprio Script no
  Rojo (e em Windows/macOS pode ser confundido com o nome reservado).
- **Os fusíveis nascem em runtime** e são sorteados com `FuseSpawner`, que
  recebe a geometria do `MapBuilder` (a lista de pilares é exportada por ele —
  não duplicada em outro módulo). Se o sorteio não couber nas regras, cai para
  uma grade determinística: o objetivo **nunca** fica impossível.
- **O fusível coletado é escondido, não destruído**, para poder voltar ao mapa
  se quem o carregava desconectar.
- **A vitória é medida por distância no tick do servidor**, não por `Touched`:
  uma parte sem colisão pode nunca disparar evento de física.
- **Sons procedurais**: os efeitos usam assets locais que acompanham o cliente
  do Roblox (`rbxasset://sounds/...`), então não é preciso publicar áudio. Se
  algum asset não existir na sua versão do cliente, o `pcall` ignora e o jogo
  segue sem som.
- **`Atmosphere` e névoa** estão declarados no projeto; o `MapBuilder` reforça
  os valores em runtime e cria um `Atmosphere` só se faltar.

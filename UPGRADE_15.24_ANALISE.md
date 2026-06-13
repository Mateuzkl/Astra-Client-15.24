# Análise do Upgrade para Protocolo 15.24 — AstraClient

> Documento gerado em 2026-06-02 durante a sessão de correção de boot/conexão.
> Servidor-alvo identificado: **crystalserver** (fork Canary/OTServBR) rodando em
> WSL, `CLIENT_VERSION = 1524` (`/home/joao/koliseuot/src/core.hpp:29`), login HTTP
> via Next.js na porta **3000**, ProtocolLogin TCP legado na **7171** e ProtocolGame
> na **7172**.

---

## 0. Handshake de rede 15.24 — cadeia de bugs (sessão de conexão)

O erro `got a network message with invalid checksum, size: 10` tinha uma cadeia de
**8 causas encadeadas**. Resolvidas em ordem:

1. **Porta/protocolo errados.** O default `LocalTestServ = 127.0.0.1:7171:1524` usava o
   **ProtocolLogin TCP** (porta 7171), que no crystalserver é só para clientes ≤11.00.
   Clientes 15.24 autenticam por **HTTP (3000)** e recebem o ProtocolGame (**7172**).
   → default trocado para `Koliseu = http://127.0.0.1:3000/api/login` ([init.lua](init.lua)).
2. **`g_http.post` headers.** [http.lua:47](modules/corelib/http.lua#L47) passava `true`
   onde o framework Boost 1.85+ espera `map<string,string> headers` → crash boolean→map.
   → passa `{ ["Content-Type"]="application/json" }` (o servidor Next.js exige esse header).
3. **`g_http.onPost/onGet` body.** [http.cpp](src/framework/http/http.cpp) passava o objeto
   `HttpResult` ao Lua, que esperava a **string** do corpo (`data:len()`).
   → converte `result->body` (vector<uint8_t>) para `std::string` antes do callback.
4. **`Services.status` como string** quebrava `client_topmenu.updateStatus` (`#status`).
   → é uma **lista** (`status = {}`).
5. **OS do cliente.** `Game::getOs()` enviava 20/21 (OTCLIENTV8). O servidor só ativa
   o framing moderno SEQUENCE quando OS ≤ 12 (OTCLIENT_*).
   → modern client envia **11** ([game.cpp `getOs()`](src/client/game.cpp#L1752)).
6. **Packet size scaling.** O crystalserver, **só para ProtocolGame**, transmite o size
   header como `(realSize-4)/8` e relê como `header*8+4`
   (`Connection::parseHeader`, `OutputMessage::writeMessageLength`).
   → `m_scaledPacketSize` no Protocol: lê `*8+4`, escreve `(size-4)/8`
   ([protocol.cpp](src/framework/net/protocol.cpp), [protocol.h](src/framework/net/protocol.h),
   [outputmessage.cpp](src/framework/net/outputmessage.cpp)); ativado no ProtocolGame moderno.
7. **Bytes-moldura do challenge.** O challenge `0x1F` vem com um byte de contagem `0x01`
   na frente e um `0x71` no fim (`sendLoginChallenge`, "Packet length & type").
   → consome o `0x01` no primeiro recv ([protocolgame.cpp](src/client/protocolgame.cpp))
   e o `0x71` residual em `parseChallenge` ([protocolgameparse.cpp](src/client/protocolgameparse.cpp)).
   Também: `GameMessageSizeCheck` desabilitado em ≥1200 (não há size interno).
8. **Auth do login packet.** O game protocol carrega a sessão como `email\npassword`
   quando `authType="password"` (default do crystalserver), mas o cliente mandava a
   session key opaca do HTTP (sem `\n`) → "You must enter your email".
   → [login.lua](modules/client_entergame/classes/login.lua) monta `account\npassword`
   quando a session key não tem `\n`.

**Estado atual (verificado por log instrumentado [HS]):** o cliente conecta na 7172,
lê o challenge `0x1F` com timestamp/random corretos, e **envia o login packet** já com
checksum + size-scaling + padding de 8 bytes, devolvendo o challenge correto.

### Layout do login packet — RESOLVIDO
O `sendLoginPacket` foi alinhado ao `onRecvFirstMessage` do crystalserver
([protocolgamesend.cpp](src/client/protocolgamesend.cpp), ramo `modernLogin`):
`ClientPendingGame` como **U16** (o protocol-id de 2 bytes que o servidor pula),
OS(U16), **getProtocolVersion()** (U16, era customProtocolVersion=0), clientVersion(U32),
versionString, **assetHash vazio** (string, ≥1334), previewState(U8), RSA block.
Verificado: o RSA block cai em **offset=19**, exatamente onde o servidor o espera, e o
servidor **aceita o login e responde** com o pacote de mundo (~4800 bytes, sequenced +
xtea + zlib). Também: padding de 8 bytes no login packet para o size-scaling fechar.

### Decode XTEA de pacote comprimido — RESOLVIDO (parte 1) + ÚLTIMO ELO (parte 2)

**Parte 1 (feito):** o servidor responde ao login com um pacote **sequenced + XTEA +
comprimido**. Dois bugs corrigidos em [protocol.cpp](src/framework/net/protocol.cpp):
  1. Detecção de compressão no sequence word: o bit é `1<<31` (`0x80000000 | seq`),
     não `>= 0xC0000000` (que perdia `0x80000001` = comprimido, seq 1).
  2. `xteaDecrypt(msg, compressed)`: o servidor `XTEA_encrypt` **não** prepende length
     no bloco comprimido (confirmado em `Protocol::XTEA_encrypt` do servidor — só padding
     + cifra). Então ler o 1º U16 como "message size" no caso comprimido produzia lixo
     (`decSize=60675`). Agora, quando `compressed`, o decrypt só decifra e retorna.
  Verificado: o XTEA decrypt agora **passa** (a chave bate; `key0` igual no envio e no
  decode).

**Parte 2 (PENDENTE):** após decifrar, o `inflate` (raw deflate, `inflateInit2(-15)`)
falha com **"failed to decompress message"**. Causa provável: `avail_in =
getUnreadSize()` inclui os **bytes de padding XTEA** (0–7) no fim do bloco, e o
`addZlibFooter()` (`00 00 FF FF`) é escrito **depois** desse padding — então o inflate vê
`[deflate stream][padding XTEA][00 00 FF FF]` e quebra no padding. O servidor comprime
com `libdeflate_deflate_compress` (raw, sem sync-flush footer) e depois adiciona o padding
XTEA; o cliente precisa descomprimir apenas o stream deflate real.

Próximo passo concreto: no ramo `decompress` de `internalRecvData`, alimentar o inflate
apenas com os bytes do stream deflate (sem o padding XTEA) — p.ex. confiar no inflate
parar no fim do bloco (Z_STREAM_END) ignorando o resto, ou rastrear o tamanho comprimido
real. Depois disso o map description deve parsear → entrar no jogo. Instrumentação `[HS]`
e `AUTO_LOGIN_DEBUG` (init.lua) seguem ligados; remover ao concluir.

**Descompressão zlib — RESOLVIDO.** A causa era o framing XTEA do crystalserver: o
`writePaddingAmount()` do servidor coloca um byte de **contagem de padding no INÍCIO** do
bloco cifrado (`[paddingAmount:1][payload][padding...]`), e o `XTEA_encrypt` **não**
prepende um size. O `xteaDecrypt` do cliente assumia o formato legado OTServ
(`[size:2][payload]`) e lia 2 bytes errados como tamanho, deixando o `next_in` do inflate
1 byte deslocado → `Z_DATA_ERROR`. Corrigido em
[protocol.cpp `xteaDecrypt`](src/framework/net/protocol.cpp): quando `m_scaledPacketSize`
(protocolo moderno), lê o `paddingAmount` (1 byte) e ajusta o tamanho para
`encryptedSize - 1 - paddingAmount`; o read-pos passa a apontar para o início real do
payload (stream deflate quando comprimido). Após isso o inflate descomprime e o map
description parseia — **sem mais `failed to decompress`**.

### CRASH ao entrar no jogo — RESOLVIDO (use-after-free)
Sintoma: o cliente travava ("abort/access violation") segundos após a lista de
personagens, ao conectar no game. Capturado com WinDbg/cdb (`run_cdb.cmd`):
`c0000005 Access violation` em `Protocol::disconnect()+0x44`, disparado por
`ProtocolGame::onError(code=10061 WSAECONNREFUSED, firstRecv=1)`.

Causa (use-after-free): `ProtocolGame::onError` chamava
`g_game.processConnectionError(err)` → `Game::processDisconnect()` que faz
`m_protocolGame->disconnect(); m_protocolGame = nullptr;` — resetando o **último**
`shared_ptr` do ProtocolGame e destruindo `this` **no meio** de `onError`. O
`disconnect()` seguinte (e o `error_code` por referência, propriedade da connection já
liberada) acessavam memória morta. Corrigido em
[protocolgame.cpp `onError`](src/client/protocolgame.cpp): segura um `static_self_cast`
local durante o handler, copia o `error_code` antes do teardown, e só chama `disconnect()`
se `!m_disconnected` (evita o disconnect duplo). O cliente agora fica **estável** (40s+
sem crash).

### Loop de reconexão — RESOLVIDO (decode de pacotes)
O loop era causado por dois bugs no decode dos pacotes sequenced/comprimidos
([protocol.cpp](src/framework/net/protocol.cpp)):
1. **Compressão por feature em vez de por pacote:** `if (decompress || m_compression)`
   forçava `inflate` em TODO pacote. Só os pacotes com o bit `1<<31` no sequence word são
   comprimidos (`decompress`); os pequenos (sequence words 2,3,4,…) não são. Corrigido
   para `if (decompress)` — os não-comprimidos pararam de dar `zlib -3`.
2. **Off-by-one no padding XTEA:** `xteaDecrypt` fazia `setMessageSize(... - 1 -
   paddingAmount)`, mas o `getU8()` do paddingAmount já recuara o read-pos em 1; o
   correto é `- paddingAmount`. O `-1` extra encurtava cada pacote em 1 byte → todo parse
   dava `eof reached`. Com o fix, os pacotes pequenos (GameServerTime, MoveCreature,
   Features, ResourceBalance, …) parseiam corretamente e o cliente **fica online sem
   reconectar** (1 ciclo de login, estável 30s+).

### Parse do map description 15.24 — RESOLVIDO ✅
O cliente agora **loga no servidor 15.24, parseia o mundo inteiro e fica online estável**
(0 parse exceptions, 0 reconexões, 30s+). Os parsers de opcode foram adaptados ao schema
do crystalserver, achados um a um instrumentando o `parseMessage` (opcode + bytes
consumidos) e comparando byte-a-byte com o `ProtocolGame::AddXxx` do servidor:

- **`GameServerResourceBalance` (0xEE):** valor é **U32** para CHARM 0x1E–0x21,
  BOUNTY_POINTS 0x56 e SOULSEALS_POINTS 0x57; **U64** para os demais. (Antes lia sempre
  U64 e desincronizava.) [protocolgameparse.cpp `parseResourceBalance`](src/client/protocolgameparse.cpp)
- **`GameServerPlayerData` (0xA0):** reescrito o caminho Tibia12 (levelPercent é U16, não
  U8; ordem exata de mana-shield etc.). [parsePlayerStats](src/client/protocolgameparse.cpp)
- **`GameServerLoginSuccess` (0x17):** caminho moderno sem o byte `canReportBugs` nem o
  botão de torneio (ambos legacy-only). [parseLogin](src/client/protocolgameparse.cpp)
- **Opcodes novos do crystalserver:** `0x1A` AllowBugReport, `0x61` BosstiaryData,
  `0x62` BosstiarySlots, `0xC1` Harmony/Serene/Virtue — handlers adicionados
  ([protocolcodes.h](src/client/protocolcodes.h) + parsers).
- **Tile (`0x64` FullMap):** o env-effects U16 só vem no oldProtocol — guard mantido.
- **`getItem` (AddItem):** reescrito para o schema 15.24 (count/container/podium/tier/
  decay/charges/wrapkit) — isOTCR=false (cliente anuncia "OTCv8"), então sem strings de
  shader. [getItem](src/client/protocolgameparse.cpp)
- **`getOutfit` (AddOutfit):** lookType U16 + cores + **mount U16 e, se mount≠0, 4 bytes
  de cor da montaria**; sem wings/aura/shader (OTCR-only). [getOutfit](src/client/protocolgameparse.cpp)
- **AppearancesLoader:** passou a carregar as flags de item 15.24
  (`expire/expirestop/clockexpire/wearout/wrapkit/upgradeclassification`) do
  appearances.dat para o `ThingType`, que `getItem` usa para saber quais bytes opcionais
  ler. [appearancesloader.cpp](src/client/appearancesloader.cpp), [thingtype.h](src/client/thingtype.h)

### Diagnóstico / qualidade de vida
- O `astraclient.log` agora **trunca a cada start** (`std::ios::trunc` em
  [logger.cpp](src/framework/core/logger.cpp)), então cada run tem um log limpo. O
  `g_logger.info` escreve nele com flush — mais confiável que o stdout redirecionado (a
  thread de rede faz buffering no stdout).
- Toda a instrumentação `[HS]`/`[OPC]` foi **removida**. O auto-login de dev é opt-in via
  `config.lua` (gitignored): `AUTO_LOGIN_DEBUG/EMAIL/PASS/HOST` + `AUTO_SELECT_CHAR`. Está
  **off por padrão** no init.lua e sem credenciais hardcoded.
- Utilitários mantidos na raiz: `test_login.ps1` (compila, roda ~22s, reporta parse
  errors + trilha de opcodes) e `run_cdb.cmd` (roda sob WinDbg/cdb e despeja a stack no
  crash).

### getCreature 15.24 + crash ao logar — RESOLVIDO ✅
Sintoma: o cliente **crashava** segundos após logar (intermitente, dependia das criaturas
no mapa). Causa: o `getCreature` legacy desincronizava no schema 15.24 — em especial o
bloco de **ícones de criatura**, que no crystalserver é uma LISTA (`count U8` seguido de
`count*(serialize U8, category U8, count U16)`), não um único byte. Ler 1 byte desalinhava
a criatura, produzia um `outfit`/thing lixo e acabava corrompendo memória → crash.

Correção: `getCreature` reescrito para o caminho moderno (Tibia12), espelhando o
`AddCreature` do servidor byte-a-byte (`0x61`=desconhecido lê removeId+id+type+[summon
master]+name; `0x62`=conhecido só id; `0x63`=turn). Inclui o bloco de ícones como lista, o
segundo `creatureType` (+ summon master / vocação de player), speech-bubble, mark,
inspection, helpers e walkthrough. [getCreature](src/client/protocolgameparse.cpp).
**Resultado: 0 crashes em 4 runs** (antes crashava intermitentemente).

### CRASH ao entrar no jogo (heap corruption) — RESOLVIDO ✅
Sintoma: o cliente entrava no jogo (carregava toda a UI), mas alguns segundos depois
**crashava** — `c0000374 STATUS_HEAP_CORRUPTION` (capturado com WinDbg, `ntdll!
RtlReportFatalFailure`), numa thread secundária, sem dialog do WER. Era intermitente e
disparado pelo desalinhamento ocasional do FullMap.

Causa raiz: **`InputMessage::addZlibFooter`** ([inputmessage.cpp](src/framework/net/inputmessage.cpp))
escrevia 4 bytes em `m_buffer[m_messageSize + m_headerPos ... +3]` mas o bounds check só
testava `m_messageSize + 4 > BUFFER_MAXSIZE` — **ignorando o `m_headerPos`** (até 8). Num
pacote grande/comprimido isso escrevia além do buffer e corrompia o heap; o `c0000374` só
estourava no free/alloc seguinte (daí a thread/momento aparentemente aleatórios).
Corrigido o check para `m_messageSize + m_headerPos + 4 > BUFFER_MAXSIZE`.

Hardening defensivo adicional (para um desync nunca mais virar crash):
- `ThingType::getSpriteIndex` clampa o índice fora de range (logando) em vez de `VALIDATE`
  → abort. [thingtype.cpp](src/client/thingtype.cpp)
- `getThing` rejeita item ids desconhecidos (`!isValidDatId`) antes de criar um item com o
  null ThingType. [protocolgameparse.cpp](src/client/protocolgameparse.cpp)
- Mod `game_cyclopedia` (sandboxed) guard em `g_things.getItemsPrice` ausente neste build.

Resultado: **0 crashes em vários runs, cliente VIVO e ESTÁVEL 75s+, 0 reconexões, 0 parse
errors** — loga, entra no jogo e permanece online.

### Pendente (não-fatal) — desalinhamento raro do FullMap (0x64)
Após corrigir `getCreature`/`getItem` e o crash, o desalinhamento do **FullMap** ficou
**raro** (não reproduziu em 6+ runs seguidos) e, quando ocorre, apenas reconecta (graças ao
hardening — não crasha). A suspeita remanescente é a **lógica de skip entre floors**
(`setMapDescription`/`setFloorDescription`) vs o `GetMapDescription` do servidor (skip
inicial -1 + `[skip][0xFF]` final), embora a aritmética de skip pareça bater. Se voltar a
incomodar: reativar logs `[TILE]`/`[ITEM]`/`[CR*]` (git history), comparar `unread` por tile,
ou capturar o pacote no servidor (`logpacotes.log`) para diff byte-a-byte.

### Próximos passos (opcional, não bloqueia o jogo)
Validar interações além do boot/mapa inicial (andar, falar, abrir containers, combate) —
podem existir outros opcodes 15.24 a adaptar, que aparecerão como `unhandled opcode N` no
`astraclient.log` e se resolvem com o mesmo método (comparar com `AddXxx` do servidor).

---

## 1. Configuração MANUAL da versão (o que o usuário seta)

A versão do cliente é controlada por **um único ponto**, em [init.lua](init.lua):

```lua
APP_VERSION = 1524           -- versão do app
CLIENT_VERSION = APP_VERSION -- ← SINGLE SOURCE OF TRUTH da versão do cliente
FORCE_CLIENT_VERSION = true  -- quando true, ignora seletor/host/config e usa CLIENT_VERSION
```

Para usar **outra versão**, o usuário edita `CLIENT_VERSION` (ex.: `CLIENT_VERSION = 1310`)
e coloca os assets em `data/things/<versão>/`. Se quiser voltar ao modo "a versão vem
do seletor/host/servidor", basta `FORCE_CLIENT_VERSION = false`.

### Quem respeita o CLIENT_VERSION (cadeia completa)

| Camada | Arquivo | Como respeita |
|---|---|---|
| Boot / assets | [modules/client_background/background.lua:31-40](modules/client_background/background.lua#L31) | `onRun()` usa `CLIENT_VERSION` quando `FORCE_CLIENT_VERSION` |
| GameInfo.version | [modules/corelib/globals.lua:178-195](modules/corelib/globals.lua#L178) | deriva de `CLIENT_VERSION` quando forçado |
| Login (todas as rotas) | [modules/client_entergame/entergame.lua:26-31](modules/client_entergame/entergame.lua#L26) | helper `resolveClientVersion()` neutraliza seletor, sufixo de host `ip:port:versão`, resposta do servidor HTTP |
| Seletor da UI | [entergame.lua:579-591](modules/client_entergame/entergame.lua#L579) | fixado em `CLIENT_VERSION` quando forçado |
| Assets por versão | [modules/game_things/things.lua](modules/game_things/things.lua) | monta `/things/<getClientVersion()>/` |
| Protocolo de rede | [modules/gamelib/game.lua:106](modules/gamelib/game.lua#L106) | `getClientProtocolVersion(1524)=1524` |
| Features | [modules/game_features/features.lua:9](modules/game_features/features.lua#L9) | `updateFeatures(version)` via `onClientVersionChange` |

> **Origem do bug "/things/860/Tibia.dat":** o placeholder de servidor em
> [init.lua](init.lua) era `LocalTestServ = "127.0.0.1:7171:860"`. O sufixo `:860`
> (formato `ip:port:versão`) sobrescrevia a versão em todo o fluxo. Hoje o
> placeholder deriva de `CLIENT_VERSION` e o `resolveClientVersion()` ignora o
> sufixo quando `FORCE_CLIENT_VERSION` está ligado.

---

## 2. Erro de conexão `invalid checksum, size: 10` (CORRIGIDO)

### Causa raiz (confirmada no código do servidor)

O crystalserver decide o **framing** dos pacotes de jogo em
`src/server/network/protocol/protocolgame.cpp:925-933`:

```cpp
version = msg.get<uint16_t>();                 // versão do protocolo
oldProtocol = OLD_PROTOCOL && version <= 1100; // false p/ 1524
if (oldProtocol)              setChecksumMethod(CHECKSUM_METHOD_ADLER32);
else if (os <= CLIENTOS_OTCLIENT_MAC /*12*/) setChecksumMethod(CHECKSUM_METHOD_SEQUENCE);
// senão: permanece CHECKSUM_METHOD_NONE
```

E a compressão zlib **só** é aplicada no caminho SEQUENCE
(`protocol.cpp:213-215`: `if (checksumMethod != CHECKSUM_METHOD_SEQUENCE) return false;`).

**O bug:** o AstraClient enviava `operatingSystem = 20/21` (`CLIENTOS_OTCLIENTV8_*`),
que é `> 12`. Logo o servidor **não** ativava SEQUENCE e ficava em `NONE`, enquanto
o cliente 1524 ligava `GameSequencedPackets` + `GameProtocolChecksum`. Framing
incompatível → `invalid checksum`.

### Handshake real (server-sends-first, com challenge)

1. Cliente conecta; como `GameChallengeOnLogin` está ON, **não** envia login no
   `onConnect`, só faz `recv()` ([protocolgame.cpp:58-61](src/client/protocolgame.cpp#L58)).
2. Servidor envia o **challenge `0x1F` com adler32 checksum explícito**
   (`protocolgame.cpp:1107-1123` no servidor; comentário *"To support 11.10-…"*).
   → O cliente PRECISA ler esse primeiro pacote com **checksum (adler) ON**.
3. Cliente parseia o challenge e chama `sendLoginPacket(timestamp, random)`
   ([protocolgameparse.cpp:1080-1085](src/client/protocolgameparse.cpp#L1080)),
   que liga `enabledSequencedPackets()` + `enableCompression()`.
4. Servidor recebe o login (pula o header de checksum nesse 1º pacote —
   `connection.cpp:298-305`), lê OS=11 → ativa **SEQUENCE**, e a partir daí todo o
   tráfego é sequenced + comprimido.
5. No cliente, `internalRecvData` testa `m_sequencedPackets` **antes** de
   `m_checksumEnabled` ([protocol.cpp:223-235](src/framework/net/protocol.cpp#L223)),
   então o sequencing assume automaticamente após o login. Por isso **NÃO** se
   desabilita o checksum — ele ainda é necessário para o challenge inicial.

### Correções aplicadas

1. **OS por versão** — [src/client/game.cpp `Game::getOs()`](src/client/game.cpp#L1752):
   para `isModernClient()` (`>= 1300`) retorna `10/11/12` (`CLIENTOS_OTCLIENT_*`)
   em vez de `20/21/22`. É isso que faz o servidor ativar SEQUENCE.
2. **Compressão** — [features.lua >= 1200](modules/game_features/features.lua#L225):
   habilita `GamePacketCompression` (o servidor comprime no caminho SEQUENCE).
   `GameProtocolChecksum` é mantido (necessário p/ o challenge).

> Os caminhos `setCustomOs(2)` e `setCustomOs(5)` (legados, só disparam se
> `GameExtendedOpcode` estiver OFF — não é o caso em >=860) também são `<= 12`,
> então continuam compatíveis com SEQUENCE. Apenas o range OTCv8 (20-25) quebrava.

### Validação pendente (precisa de login manual)

O boot foi validado (ver §4). A **conexão** só pode ser confirmada logando de fato
no servidor pela GUI — não foi possível automatizar (login HTTP com senha + RSA/XTEA).
Ao acordar: abrir o cliente, logar no `LocalTestServ`/Koliseu e confirmar que **não**
aparece `invalid checksum` e que o personagem entra no jogo.

---

## 3. Outros problemas corrigidos

### 3a. Assets carregados 2-3× no boot (CORRIGIDO)
- **Causa:** `setClientVersion()` no C++ emitia `onClientVersionChange`
  incondicionalmente → `updateFeatures` → `things.load()`, e o boot/login chamava
  `setClientVersion(1524)` várias vezes; havia ainda um `addEvent(load)` redundante
  em `background.lua`.
- **Fix 1:** early-out em [game.cpp `setClientVersion`](src/client/game.cpp#L1676)
  (`if (m_clientVersion == version) return;`), espelhando o `setProtocolVersion`.
- **Fix 2:** guard por versão carregada (`loadedVersion`) em
  [things.lua](modules/game_things/things.lua#L47).
- **Fix 3:** removido o `addEvent(... game_things.load())` redundante em
  [background.lua](modules/client_background/background.lua#L31).
- **Resultado:** assets carregam **1×** no boot.

### 3b. `invalid thing type client id 2594..2598 in category 1` (CORRIGIDO)
- **Causa:** `modules/game_offsets` rodava `loadOffsetsData()` via
  `scheduleEvent(..., 200)` (delay fixo) que disparava **antes** dos appearances
  carregarem; `getThingType(2594..2598, ThingCategoryCreature)` em tabela vazia
  logava o erro. (Category 1 = **Creature**, não Item; os IDs vêm de
  `data/json/offsets.json`.)
- **Fix:** [offsets.lua init()](modules/game_offsets/offsets.lua#L24) agora dispara
  `loadOffsetsData` via `connect(g_things, { onLoadDat = ... })` + executa uma vez
  se os assets já estiverem carregados, com guard `modules.game_things.isLoaded()`
  defensivo dentro de `loadOffsetsData`.
- **Resultado:** **zero** erros `invalid thing type` no boot.

---

## 4. Estado da build e do boot

- **Build Debug|x64:** OK (rebuild limpo passa; incremental ~46s após mudança em
  `game.cpp`). Não existe configuração Release na solução (`otclient.sln` só tem
  Debug x64/Win32) — `-Config Release` falha com MSB4126, é esperado.
- **Boot validado:** assets `/things/1524/` carregam 1×, sem `ERROR`, sem
  `invalid thing type`, sem `/things/860/`.
- Helper de build: [compile.ps1](compile.ps1) (`.\compile.ps1`, `-Clean`, `-NoKill`).

---

## 5. Pontos de atenção / dívida técnica (NÃO bloqueiam)

1. **Validar a conexão logando de verdade** (item §2). É o único teste que falta.
2. **Compressão do servidor:** confirmado que o servidor comprime apenas no caminho
   SEQUENCE; o cliente só **descomprime** no recv (não comprime o que envia). Bate
   com o servidor (que lê pacotes do cliente sem esperar compressão).
3. **`onTibia12HTTPResult`** ([entergame.lua:373-378](modules/client_entergame/entergame.lua#L373))
   resolve `G.clientVersion` mas **não** chama `setClientVersion`/`setProtocolVersion`
   localmente — depende do valor de boot. Com SSOT em 1524 isso é benigno hoje, mas
   convém alinhar se um dia múltiplas versões coexistirem.
4. **Override `1000→1100`** ([entergame.lua:814](modules/client_entergame/entergame.lua#L814))
   é morto quando `FORCE_CLIENT_VERSION` está ligado (nunca recebe 1000).
5. **`data/things/860.rar`** não-extraído na pasta de assets — pode ser removido se
   860 não for mais alvo.
6. Avisos cosméticos no boot: texturas > 512×512 e `pwsh.exe não reconhecido`
   (post-build do toolset, não quebra a build). Sem impacto funcional.

---

## 6. Arquivos modificados nesta sessão (resumo)

| Arquivo | Mudança |
|---|---|
| `init.lua` | `CLIENT_VERSION`/`FORCE_CLIENT_VERSION`; placeholder de server deriva da versão |
| `modules/client_entergame/entergame.lua` | `resolveClientVersion()` em todas as rotas de login + seletor |
| `modules/client_background/background.lua` | `onRun()` respeita SSOT; removido load redundante |
| `modules/corelib/globals.lua` | `GameInfo.version` deriva de `CLIENT_VERSION` |
| `modules/game_features/features.lua` | `GamePacketCompression` em >=1200 (+ comentário sobre checksum/sequence) |
| `modules/game_things/things.lua` | guard `loadedVersion` contra reload |
| `modules/game_offsets/offsets.lua` | dispara via `onLoadDat` + guard `isLoaded` |
| `src/client/game.cpp` | `getOs()` → OTCLIENT_* p/ modern; early-out em `setClientVersion` |

> As mudanças em `appearancesloader.cpp`, `spritemanager.*`, `thingtypemanager.cpp`,
> `resourcemanager.*`, `gamelib/game.lua` já estavam no working tree de trabalho
> anterior (porte do loader moderno) e não foram alteradas nesta sessão de conexão.

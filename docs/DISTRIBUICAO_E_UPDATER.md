# Distribuição, Updater e Split Test/Prod — Design + Estado

> Documento de trabalho. Estado atual do código + arquitetura proposta + decisões que
> dependem de você (infra/hosting). Implementação parcial nesta sessão marcada com ✅.

---

## 1. Estado atual (o que já existe no código)

### Build / artefatos
- `compile.ps1 -Config DirectX` → `AstraClient_dx_x64.exe` (~16 MB) na raiz.
- **4 DLLs** ao lado do exe (copiadas pelo PostBuildEvent): `libGLESv2.dll`, `libEGL.dll`,
  `d3dcompiler_47.dll`, `vulkan-1.dll` (ANGLE vendorado — `third_party/angle/`).
- **Dados**: a pasta `data/` (Lua + imagens + sprites). Hoje rodando do **filesystem** (dev).

### Como o client carrega dados (`resourcemanager.cpp`)
Ordem: (1) `data.zip` ao lado do exe → montado em memória; (2) filesystem (pasta `data/`);
(3) `loadDataFromSelf` (data embutido no exe). **O updater só funciona no modo data.zip**
(`isLoadedFromArchive`), porque `filesChecksums()` lê os CRCs do zip em memória.

### Updater (`modules/updater/`) — CLIENT JÁ COMPLETO (padrão OTCv8)
Fluxo: `Updater.check()` faz `HTTP.postJSON(Services.updater, {version, build, os, platform, args})`
→ recebe um **manifest** → compara com os checksums locais → baixa só o que mudou → aplica
(`g_resources.updateData`) → se o binário mudou, `updateExecutable` + `g_app.restart()`
(o `launchCorrect` no boot lança o exe novo do pref dir).

Gate de ativação (`init.lua:150`): só roda se `Services.updater` é string > 4 chars **E**
`isLoadedFromArchive` (data.zip) **E** o módulo `updater` existe.

### Contrato da API do updater (o que o backend DEVE responder)
Request (POST JSON):
```json
{ "version": "<APP_VERSION>", "build": "3.1", "os": "windows", "platform": "...", "args": {} }
```
Response (JSON):
```json
{
  "url": "https://updates.koliseuot.com/files/",   // base de download (obrigatório)
  "files": {                                        // arquivo -> checksum CRC32 hex
    "/init.lua": "a1b2c3d4",
    "/modules/game_skills/skills.lua": "deadbeef",
    "/data/things/appearances.dat": "12345678"
  },
  "binary": { "file": "AstraClient_dx_x64-<rev>.exe", "checksum": "..." }, // opcional
  "keepFiles": false,    // opcional: true = não apaga arquivos locais fora do manifest
  "error": ""            // opcional: string não-vazia = erro exibido ao player
}
```
- **Checksum = CRC32** do conteúdo do arquivo, em hex (igual ao CRC do zip entry — ver
  `ResourceManager::filesChecksums`). O gerador em `tools/gen_update_manifest.py` produz isso.
- O client baixa `url + file` para cada arquivo com checksum diferente, valida o CRC, e aplica.
- Binário: se o `selfChecksum()` difere do `binary.checksum`, baixa o exe novo → próximo boot
  o `launchCorrect` troca pro mais recente.

### Login services (já config-driven — ver `docs/` e memória)
`config.lua` define `Services` (status/createAccount/recoveryPassword/updater/...) e `Servers`.
`Services.updater` está **vazio** hoje.

---

## 2. Arquitetura de distribuição (proposta)

### 2.1 Packaging
1. Zipar `data/` → `data.zip` (raiz do release).
2. Release = `AstraClient.exe` (renomeado do dx_x64) + 4 DLLs + `data.zip`.
3. (Opcional) Criptografar com `--encrypt` (o client tem `WITH_ENCRYPTION`; `g_resources.encrypt`).
4. Gerar o **manifest** (`tools/gen_update_manifest.py`) e publicar no servidor de update.

### 2.2 Installer (Windows) — Inno Setup
Draft em `tools/installer/koliseuot.iss`. Instala exe + DLLs + data.zip, cria atalhos
(Menu Iniciar + Desktop), ícone já embutido. Primeiro run → updater verifica updates.
- Alvo recomendado: `%LOCALAPPDATA%\KoliseuOT\Client` (sem precisar de admin) — o updater
  precisa escrever o binário/dados, então evitar `Program Files` (UAC) facilita.

### 2.3 Servidor de update (backend — VOCÊ provê)
Endpoint que responde o contrato acima. Mais simples: um diretório estático servido por
nginx/CDN + um JSON `update.json` gerado pelo `gen_update_manifest.py` a cada release.
O client faz POST; um endpoint trivial (PHP/Node) lê o `update.json` e devolve.
(Pode até ser estático se aceitar GET — mas o client usa POST; um proxy de 5 linhas resolve.)

---

## 3. Split Test/Prod (proposta + ✅ plumbing implementado)

### 3.1 Modelo recomendado: **dois exes, um launcher**
- **Prod**: `AstraClient.exe` → servidor Koliseu prod. Canal de update = manifest prod.
- **Teste**: `AstraClient_test.exe` → servidor de teste. **Build separado** (pode ter features
  novas/protocolo diferente). Canal de update = manifest teste.
- No **seletor de servidor** do client prod: opções `Koliseu` e `Teste Server`. Ao escolher
  `Teste Server` e logar, o client **lança o `AstraClient_test.exe`** e fecha (se não existir,
  o updater de teste baixa). O client de teste, ao abrir, conecta direto no server de teste
  (config próprio).

Por que dois exes: você disse que o teste pode ter features novas que exigem um client de
teste — manter binários separados evita que uma mudança de protocolo do teste quebre o prod.

### 3.2 Implementação client (✅ nesta sessão)
- **C++** `Application::launchBinary(name)` — spawn de um exe arbitrário ao lado do atual +
  `quick_exit` (fecha o atual). Bind Lua `g_app:launchBinary(name)`. (Reusa o `spawnAndDetach`
  da Fase 2.)
- **`config.lua` `Servers`**: entrada `Teste Server` com marcador `launchBinary = "AstraClient_test_x64.exe"`.
- **`entergame.lua`**: ao logar com um server que tem `launchBinary`, chama `g_app:launchBinary`
  em vez de conectar.

### 3.3 Alternativa (mais simples, 1 exe)
Mesmo exe + flag `--server=test` (relaunch via `restartArgs`, já existe). Só serve se o client
de teste NÃO precisar de binário diferente. Como você quer features novas no teste, fica como
fallback, não recomendado.

---

## 4. Decisões que dependem de você (infra/produto)

| Tema | Pergunta |
|---|---|
| Update server | URL do endpoint (prod e teste). Hosting dos arquivos (nginx/CDN/S3)? |
| Installer | Alvo: `%LOCALAPPDATA%` (sem admin, recomendado) ou `Program Files`? |
| data.zip | Criptografar (`--encrypt`)? |
| Test client | Confirma "dois exes" (recomendado) vs "mesmo exe + flag"? Nome do exe de teste? |
| Test server | URL de login do servidor de teste (hoje placeholder). |
| Versionamento | Esquema de versão/rev pro manifest (git rev count? semver?). |

---

## 5. Implementado nesta sessão (autônomo)
- ✅ Este design doc.
- ✅ `tools/gen_update_manifest.py` — gera o manifest do updater (CRC32) a partir de uma pasta.
- ✅ `tools/installer/koliseuot.iss` — draft de installer Inno Setup.
- ✅ Split test/prod (plumbing): `Application::launchBinary` + bind + config + entergame.
- (Pendente, depende de decisão/infra: URLs, hosting, build do client de teste, encryption.)

Ver o relatório no fim da sessão (`docs/RELATORIO_SESSAO_DISTRIBUICAO.md`).

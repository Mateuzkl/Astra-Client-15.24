-- CONFIG
APP_NAME = "AstraClient"
APP_VERSION = 1524
DEFAULT_LAYOUT = ""

-- F8 P1: developer flag — modules opt into noisy diagnostics when true
-- (e.g. modules/game_protocol unhandled-opcode reporter). Override locally
-- in config.lua by setting `DEVELOPERMODE = true` before modules load.
DEVELOPERMODE = false

-- ---------------------------------------------------------------------------
-- Server endpoint configuration
-- ---------------------------------------------------------------------------
-- Open-source clients ship with a placeholder example.com endpoint set. Copy
-- config.example.lua → config.lua and edit the URLs for your own server, or
-- set the env-variable CLIENT_ENV=dev to use the local development defaults
-- (Koliseu at http://127.0.0.1:3000 for HTTP login).
--
-- Servers entry forms:
--   "ip:port:version"               legacy TCP ProtocolLogin (8.60/10.x)
--   "http(s)://host/path"           Tibia 12+ HTTP login (modern Koliseu)
--   "ws(s)://host/path"             WebSocket login (USE_NEW_ENERGAME=true)

local CLIENT_ENV = (os.getenv and os.getenv("CLIENT_ENV")) or "prod"

local function loadConfig()
  -- 1. user-provided config.lua takes precedence
  local ok, userConfig = pcall(dofile, "config.lua")
  if ok and type(userConfig) == "table" and userConfig.Services and userConfig.Servers then
    return userConfig.Services, userConfig.Servers
  end

  -- 2. env-specific defaults
  if CLIENT_ENV == "dev" then
    return {
      website       = "",
      updater       = "",
      stats         = "",
      crash         = "",
      feedback      = "",
      status        = "http://127.0.0.1:3000/api/status",
      createAccount = "http://127.0.0.1:3000/account/register",
      getCoinsUrl   = "http://127.0.0.1:3000/donate",
    }, {
      Koliseu = "http://127.0.0.1:3000/api/login",
    }
  end

  -- 3. open-source placeholder
  return {
    website  = "",
    updater  = "",
    stats    = "",
    crash    = "",
    feedback = "",
    status   = "",
  }, {
    LocalTestServ = "127.0.0.1:7171:860",
  }
end

Services, Servers = loadConfig()

ALLOW_CUSTOM_SERVERS = true

g_app.setName(APP_NAME)
-- CONFIG END

g_logger.info(os.date("== application started at %b %d %Y %X"))
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' .. g_app.getBuildCommit() .. ') made by ' .. g_app.getAuthor() .. ' built on ' .. g_app.getBuildDate() .. ' for arch ' .. g_app.getBuildArch())

if not g_resources.directoryExists("/data") then
  g_logger.fatal("Data dir doesn't exist.")
end

if not g_resources.directoryExists("/modules") then
  g_logger.fatal("Modules dir doesn't exist.")
end

-- settings
g_configs.loadSettings("/config.otml")

-- set layout
local settings = g_configs.getSettings()
local layout = DEFAULT_LAYOUT
if g_app.isMobile() then
  layout = "mobile"
elseif settings:exists('layout') then
  layout = settings:getValue('layout')
end
if layout:len() > 0 and not g_resources.directoryExists('/layouts/' .. layout) then
  layout = ""
end
g_resources.setLayout(layout)

-- load mods
g_modules.discoverModules()
g_modules.ensureModuleLoaded("corelib")

local function loadModules()
  -- libraries modules 0-99
  g_modules.autoLoadModules(99)
  g_modules.ensureModuleLoaded("gamelib")

  -- client modules 100-499
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded("client")

  -- game modules 500-999
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded("game_interface")

  -- mods 1000-9999
  g_modules.autoLoadModules(9999)
end

-- report crash
if type(Services.crash) == 'string' and Services.crash:len() > 4 and g_modules.getModule("crash_reporter") then
  g_modules.ensureModuleLoaded("crash_reporter")
end

-- run updater, must use data.zip
if type(Services.updater) == 'string' and Services.updater:len() > 4
  and g_resources.isLoadedFromArchive() and g_modules.getModule("updater") then
  g_modules.ensureModuleLoaded("updater")
  return Updater.init(loadModules)
end
loadModules()

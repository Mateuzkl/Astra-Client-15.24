filename = nil
loaded = false
loading = false

function setFileName(name)
  filename = name
end

function isLoaded()
  return loaded
end

function isLoading()
  return loading
end

local function getVersionFromPath(datPath)
  local version = tostring(datPath):match('[\\/]things[\\/](%d+)[\\/]')
  return tonumber(version)
end

local function hasModernAssetFeatures(datPath)
  local otfiPath = datPath .. '.otfi'
  if not g_resources.fileExists(otfiPath) then
    return false
  end

  local otfi = g_resources.readFileContents(otfiPath)
  if not otfi then
    return false
  end

  return otfi:find('frame%-groups:%s*true') ~= nil or otfi:find('sprite%-data%-size:%s*4096') ~= nil
end

local function enableModernAssetFeatures()
  g_game.enableFeature(GameSpritesU32)
  g_game.enableFeature(GameIdleAnimations)
  g_game.enableFeature(GameEnhancedAnimations)
end

function load()
  if loading then
    return
  end

  loading = true
  local version = g_game.getClientVersion()
  local things = g_settings.getNode('things')

  local datPath, sprPath
  if things and things["data"] ~= nil and things["sprites"] ~= nil then
    datPath = resolvepath('/things/' .. things["data"])
    sprPath = resolvepath('/things/' .. things["sprites"])
  else
    if filename then
      datPath = resolvepath('/things/' .. filename)
      sprPath = resolvepath('/things/' .. filename)
    else
      -- Force loading the 8.60 asset pack used by this server.
      datPath = resolvepath('/things/860/Tibia')
      sprPath = resolvepath('/things/860/Tibia')
    end
  end

  local protocolVersion = g_game.getProtocolVersion()
  local assetVersion = getVersionFromPath(datPath) or version
  if hasModernAssetFeatures(datPath) then
    enableModernAssetFeatures()
  end

  if assetVersion ~= version then
    g_logger.info(string.format("Loading assets from %s as client version %d while keeping protocol %d.", datPath, assetVersion, protocolVersion))
    g_game.setClientVersion(assetVersion)
  end

  -- Phase 0 #9: cheap modern-assets probe.
  -- If data/things/<assetVersion>/catalog-content.json exists, we take the
  -- protobuf path via g_things.loadAppearances; otherwise fall through to
  -- the legacy loadDat/loadSpr branch unchanged. The probe is a single
  -- fileExists call — no directory scan — and only runs when the modern
  -- loader binding is present in this build.
  -- Knob: `force-legacy-assets = true` in default-config.otml pins the old
  -- loader for debugging even when modern assets are on disk.
  local forceLegacy = g_settings.getBoolean('force-legacy-assets')
  local assetsDir = resolvepath('/things/' .. tostring(assetVersion))
  local modernCatalog = assetsDir .. '/catalog-content.json'
  local useModernAssets = (not forceLegacy)
                          and g_things.loadAppearances ~= nil
                          and g_resources.fileExists(modernCatalog)

  local errorMessage = ''
  if useModernAssets then
    -- Modern protobuf path (Tibia 12+). Mirrors koliseu-otcv8 things.lua:
    -- sprite-sheet catalog FIRST (loader needs cell sizes), then
    -- appearances.dat resolved through getAppearancesPath if available.
    local appearancesFile = assetsDir
    if g_things.getAppearancesPath ~= nil then
      local resolved = g_things.getAppearancesPath(assetsDir)
      if resolved and resolved ~= '' then
        appearancesFile = resolved
      end
    end
    if g_sprites.loadSpr and not g_sprites.loadSpr(assetsDir) then
      errorMessage = errorMessage .. tr("Unable to load sprite sheets from '%s'", assetsDir) .. '\n'
    end
    if errorMessage:len() == 0 and not g_things.loadAppearances(appearancesFile) then
      errorMessage = errorMessage .. tr("Unable to load appearances.dat at '%s'", appearancesFile) .. '\n'
    end
  else
    -- Legacy .dat / .spr path. Byte-identical to pre-P0.9 behaviour for the
    -- 8.60 default boot: forceLegacy=false, no catalog file at
    -- data/things/860/catalog-content.json, probe misses, we end up here.
    if not g_things.loadDat(datPath) then
      if not g_game.getFeature(GameSpritesU32) then
        g_game.enableFeature(GameSpritesU32)
        if not g_things.loadDat(datPath) then
          errorMessage = errorMessage .. tr("Unable to load dat file, please place a valid dat in '%s'", datPath) .. '\n'
        end
      else
        errorMessage = errorMessage .. tr("Unable to load dat file, please place a valid dat in '%s'", datPath) .. '\n'
      end
    end
    if not g_sprites.loadSpr(sprPath) then
      errorMessage = errorMessage .. tr("Unable to load spr file, please place a valid spr in '%s'", sprPath)
    end
  end

  if assetVersion ~= version then
    g_game.setClientVersion(version)
    g_game.setProtocolVersion(protocolVersion)
  end

  loaded = (errorMessage:len() == 0)
  loading = false

  if errorMessage:len() > 0 then
    local loadError = errorMessage:gsub('%s+$', '')
    g_logger.error(loadError)

    g_game.setClientVersion(0)
    g_game.setProtocolVersion(0)
  end
end

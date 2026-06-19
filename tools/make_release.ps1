# make_release.ps1 — assembles a distributable KoliseuOT client release.
# Replaces the obsolete tools/make_snapshot.sh (edubart mingw/win32).
#
# Output: a release/ folder with:
#   KoliseuClient.exe + libGLESv2.dll + libEGL.dll + d3dcompiler_47.dll + vulkan-1.dll
#   data.zip   (init.lua + modules/ + mods/ + data/  -> the client VFS, needed by the updater)
#   config.lua (ONLY if you provide config.prod.lua -- the dev config.lua is NEVER shipped)
#
# Usage:
#   .\tools\make_release.ps1                       # build + assemble release/
#   .\tools\make_release.ps1 -SkipBuild            # assemble from the current exe
#   .\tools\make_release.ps1 -Url https://cdn/files/ -Rev 123   # + generate update.json
#
# IMPORTANT (see docs/DISTRIBUICAO_E_UPDATER.md):
#  - The dev config.lua (localhost + AUTO_LOGIN password) is EXCLUDED. Provide a prod config
#    as config.prod.lua (real Koliseu URLs, no AUTO_LOGIN) and it ships as config.lua.
#  - The updater only activates in data.zip mode (isLoadedFromArchive) + Services.updater set.

[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [string]$Url = "",          # if set, also generate update.json (needs Python)
  [string]$Rev = "",          # revision tag appended to the published binary name
  [string]$ReleaseDir = "release"
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$exe = "KoliseuClient.exe"
$dlls = @('libGLESv2.dll', 'libEGL.dll', 'd3dcompiler_47.dll', 'vulkan-1.dll')

if (-not $SkipBuild) {
  Write-Host "Building DirectX..." -ForegroundColor Cyan
  & "$repo\compile.ps1" -Config DirectX
  if ($LASTEXITCODE -ne 0) { throw "build failed" }
}

# --- clean release dir ---
$rel = Join-Path $repo $ReleaseDir
if (Test-Path $rel) { Remove-Item -Recurse -Force $rel }
New-Item -ItemType Directory -Force -Path $rel | Out-Null

# --- exe + DLLs ---
foreach ($f in @($exe) + $dlls) {
  if (-not (Test-Path (Join-Path $repo $f))) { throw "missing artifact: $f (build first?)" }
  Copy-Item (Join-Path $repo $f) -Destination $rel -Force
}

# --- data.zip (the client VFS) ---
$dataZip = Join-Path $rel "data.zip"
$items = @('init.lua', 'modules', 'mods', 'data') | ForEach-Object { Join-Path $repo $_ }
Write-Host "Zipping data.zip (init.lua + modules + mods + data)..." -ForegroundColor Cyan
Compress-Archive -Path $items -DestinationPath $dataZip -CompressionLevel Optimal -Force
Write-Host ("  data.zip: {0:N1} MB" -f ((Get-Item $dataZip).Length / 1MB))

# --- prod config (optional, NEVER ship the dev config.lua) ---
$prodCfg = Join-Path $repo "config.prod.lua"
if (Test-Path $prodCfg) {
  Copy-Item $prodCfg -Destination (Join-Path $rel "config.lua") -Force
  Write-Host "  shipped config.prod.lua as config.lua" -ForegroundColor Green
} else {
  Write-Host "  WARNING: no config.prod.lua found -> release ships NO config.lua." -ForegroundColor Yellow
  Write-Host "           Provide config.prod.lua with real Koliseu URLs (Services.updater etc.)." -ForegroundColor Yellow
}

# --- optional: update manifest ---
if ($Url -ne "") {
  $py = (Get-Command python -ErrorAction SilentlyContinue).Source
  if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
  if ($py) {
    $binName = if ($Rev -ne "") { "KoliseuClient-$Rev.exe" } else { $exe }
    & $py "$repo\tools\gen_update_manifest.py" $dataZip --url $Url `
        --binary (Join-Path $rel $exe) --binary-name $binName -o (Join-Path $rel "update.json")
    Write-Host "  generated update.json (url=$Url, binary=$binName)" -ForegroundColor Green
  } else {
    Write-Host "  python not found -> skipped update.json" -ForegroundColor Yellow
  }
}

Write-Host "`nRelease ready: $rel" -ForegroundColor Green
Get-ChildItem $rel | ForEach-Object { "  {0,-26} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB) }

# compile.ps1 — Build helper for AstraClient (15.24 upgrade fork).
#
# Usage:
#   .\compile.ps1                       # Debug|x64, incremental
#   .\compile.ps1 -Config Release       # Release|x64
#   .\compile.ps1 -Clean                # full Rebuild target
#   .\compile.ps1 -NoKill               # don't kill running AstraClient_*.exe
#
# Why this script exists:
#   - MSBuild lives at an annoyingly-versioned path; we resolve it via vswhere.
#   - The Debug build pins PlatformToolset=v145 because the machine has
#     Visual Studio 2026 (VS 18) installed, not VS 2022 (v143).
#   - When the client is still running, LINK fails with LNK1104 'cannot open
#     AstraClient_debug_x64.exe' — Stop-Process handles that up front.

[CmdletBinding()]
param(
    # Debug = unoptimized dev build. OpenGL/DirectX = the optimized "release" builds
    # (MaxSpeed, NDEBUG, LTCG) — use these for performance testing. The bare "Release"
    # config exists in the vcxproj but is NOT mapped in the .sln, so it won't build.
    [ValidateSet('Debug', 'OpenGL', 'DirectX')]
    [string]$Config = 'Debug',

    [ValidateSet('x64', 'Win32')]
    [string]$Platform = 'x64',

    [string]$Toolset = 'v145',

    [switch]$Clean,
    [switch]$NoKill
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSCommandPath
$solutionPath = Join-Path $repoRoot 'vc17\otclient.sln'

if (-not (Test-Path $solutionPath)) {
    throw "Could not find solution at $solutionPath. Run this script from the AstraClient repo root."
}

# --- Locate MSBuild via vswhere -----------------------------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere. Install Visual Studio 2022+."
}

$msbuild = & $vswhere -latest -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild -or -not (Test-Path $msbuild)) {
    throw "Could not locate MSBuild.exe via vswhere."
}
Write-Host "MSBuild: $msbuild" -ForegroundColor DarkGray

# --- Kill running client so LINK can overwrite the .exe ----------------------
if (-not $NoKill) {
    $running = Get-Process -Name 'AstraClient_*' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Stopping $($running.Count) running AstraClient process(es)..." -ForegroundColor Yellow
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

# --- Build --------------------------------------------------------------------
$targetArg = if ($Clean) { '/t:Rebuild' } else { '/t:Build' }

$args = @(
    $solutionPath,
    "/p:Configuration=$Config",
    "/p:Platform=$Platform",
    "/p:PlatformToolset=$Toolset",
    '/m',
    '/v:minimal',
    '/nologo',
    $targetArg
)

Write-Host "Building $Config|$Platform (toolset $Toolset)..." -ForegroundColor Cyan
$startTime = Get-Date

& $msbuild @args
$exitCode = $LASTEXITCODE

$elapsed = (Get-Date) - $startTime

if ($exitCode -eq 0) {
    $exeSuffix = switch ($Config) {
        'Debug'   { 'debug_x64' }
        'OpenGL'  { 'gl_x64' }
        'DirectX' { 'dx_x64' }
        default   { 'debug_x64' }
    }
    $exePath = Join-Path $repoRoot "AstraClient_$exeSuffix.exe"
    Write-Host ""
    Write-Host "Build OK in $([int]$elapsed.TotalSeconds)s" -ForegroundColor Green
    if (Test-Path $exePath) {
        $size = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
        Write-Host "Output: $exePath ($size MB)" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Build FAILED (exit $exitCode) after $([int]$elapsed.TotalSeconds)s" -ForegroundColor Red
    exit $exitCode
}

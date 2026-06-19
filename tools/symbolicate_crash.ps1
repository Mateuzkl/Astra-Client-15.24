# symbolicate_crash.ps1 — turn a crash minidump into a source-level backtrace.
#
# The release client is shipped STRIPPED (no PDB), so crash dumps uploaded to the
# koliseu-aac crash dashboard arrive as raw addresses. Symbolize them here, on the
# Windows dev box, against the PDB you archived for that exact build.
#
# Usage:
#   .\tools\symbolicate_crash.ps1 -Dump C:\path\to\<id>.dmp -Symbols C:\symbol-vault
#   .\tools\symbolicate_crash.ps1 -Dump x.dmp -Symbols C:\vault -Out analysis.txt
#
# -Symbols is a folder holding the PDB(s) for released builds (your symbol vault).
# cdb auto-matches the correct PDB via the GUID/age recorded inside the minidump,
# so just point it at the vault. Add Microsoft's public server for OS frames with
# -PublicSymbols.
#
# cdb comes with the Windows SDK "Debugging Tools for Windows" (or the Store app).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Dump,
  [Parameter(Mandatory = $true)] [string]$Symbols,
  [string]$Cdb = "",
  [string]$Out = "",
  [switch]$PublicSymbols
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Dump))    { throw "dump not found: $Dump" }
if (-not (Test-Path $Symbols)) { throw "symbols dir not found: $Symbols" }

# --- locate cdb.exe ----------------------------------------------------------
function Find-Cdb {
  param([string]$Hint)
  if ($Hint -and (Test-Path $Hint)) { return $Hint }
  $cmd = Get-Command cdb.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $roots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
    "${env:ProgramFiles}\Windows Kits\10\Debuggers\x64\cdb.exe"
  )
  foreach ($r in $roots) { if (Test-Path $r) { return $r } }
  # WindowsApps (Store "WinDbg") shim
  $store = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps\cdb.exe" -ErrorAction SilentlyContinue
  if ($store) { return $store.FullName }
  throw "cdb.exe not found. Install 'Debugging Tools for Windows' (Windows SDK) or pass -Cdb <path>."
}

$cdbExe = Find-Cdb -Hint $Cdb
Write-Host "cdb: $cdbExe" -ForegroundColor DarkGray

# --- symbol path -------------------------------------------------------------
$symPath = (Resolve-Path $Symbols).Path
if ($PublicSymbols) {
  $cache = Join-Path $env:TEMP "symcache"
  $symPath = "$symPath;srv*$cache*https://msdl.microsoft.com/download/symbols"
}

# --- run ---------------------------------------------------------------------
# .lines      -> source line numbers
# !analyze -v -> root-cause guess + faulting frame
# kv          -> verbose stack
$commands = ".lines -e; !analyze -v; kv; q"

Write-Host "Symbolizing $Dump ..." -ForegroundColor Cyan
$output = & $cdbExe -z $Dump -y "$symPath" -c $commands 2>&1 | Out-String

if ($Out) {
  $output | Out-File -FilePath $Out -Encoding utf8
  Write-Host "Wrote $Out" -ForegroundColor Green
} else {
  Write-Output $output
}

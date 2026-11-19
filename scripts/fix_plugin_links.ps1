# Fix Windows plugin links WITHOUT Developer Mode or admin rights.
#
# Why: Flutter creates SYMLINKS for plugins on Windows, which requires
# Developer Mode or elevation. Directory JUNCTIONS do not, and are
# transparent to Flutter/CMake.
#
# Usage (from project root):
#   powershell -ExecutionPolicy Bypass -File scripts\fix_plugin_links.ps1

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $PSScriptRoot
$depsFile = Join-Path $root '.flutter-plugins-dependencies'
$linkDir  = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'

if (-not (Test-Path $depsFile)) {
    Write-Host 'ERROR: .flutter-plugins-dependencies not found. Run "flutter pub get" first.'
    exit 1
}

New-Item -ItemType Directory -Force -Path $linkDir | Out-Null

$deps    = Get-Content $depsFile -Raw | ConvertFrom-Json
$plugins = $deps.plugins.windows

if (-not $plugins -or $plugins.Count -eq 0) {
    Write-Host 'No Windows plugins found. Nothing to do.'
    exit 0
}

$created = 0
$skipped = 0

foreach ($p in $plugins) {
    $name   = $p.name
    $target = $p.path.TrimEnd('\')
    $link   = Join-Path $linkDir $name

    if (-not (Test-Path $target)) {
        Write-Host ('  SKIP ' + $name + ' (target missing: ' + $target + ')')
        $skipped++
        continue
    }

    if (Test-Path $link) {
        Write-Host ('  OK   ' + $name + ' (already linked)')
        $skipped++
        continue
    }

    try {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        Write-Host ('  NEW  ' + $name + ' -> ' + $target)
        $created++
    } catch {
        Write-Host ('  FAIL ' + $name + ': ' + $_.Exception.Message)
        $skipped++
    }
}

Write-Host ''
Write-Host ('Done. created=' + $created + ' skipped=' + $skipped)
Write-Host 'You can now run: flutter build windows'

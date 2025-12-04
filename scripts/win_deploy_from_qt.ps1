<#
Copies required Qt runtime DLLs and plugins from a local Qt installation to the folder with Cetus.exe.

Usage (PowerShell):
  # specify path to Qt root (folder that contains subfolders like '5.15.2') and app folder
  .\win_deploy_from_qt.ps1 -QtRoot 'C:\Qt' -AppDir 'C:\path\to\Cetus\build'

The script will try to find a Qt 5.x MinGW kit under the given Qt root (e.g. 'C:\Qt\5.15.2\mingw81_64').
It copies:
 - Qt DLLs from the kit's `bin` folder
 - plugins (including `platforms\qwindows.dll`) from the kit's `plugins` folder
 - QML modules if present
 - common MinGW runtime DLLs (libgcc, libstdc++, libwinpthread) from the kit or nearby MinGW toolchain

This is a helper if `windeployqt` is not available. Prefer using `windeployqt` when possible.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$QtRoot,

    [Parameter(Mandatory=$true)]
    [string]$AppDir,

    [string]$QmlDir = "$PSScriptRoot\..\Cetus\qml"
)

Write-Host "Qt root: $QtRoot"
Write-Host "App dir: $AppDir"
Write-Host "QML dir (suggested): $QmlDir"

if (-not (Test-Path $QtRoot)) { throw "Qt root not found: $QtRoot" }
if (-not (Test-Path $AppDir)) { throw "App dir not found: $AppDir" }

# Find a Qt 5.x MinGW kit under QtRoot
$kit = Get-ChildItem -Path $QtRoot -Directory -Recurse -Depth 3 | Where-Object {
    $_.FullName -match '\\5\.' -and $_.FullName -match 'mingw' -and (Test-Path (Join-Path $_.FullName 'bin'))
} | Select-Object -First 1

if (-not $kit) {
    Write-Warning "Couldn't automatically find a Qt5 MinGW kit under $QtRoot. Please specify correct Qt root (e.g. C:\\Qt)."
    Write-Host "You can run windeployqt from your Qt kit instead — recommended."
    exit 1
}

$kitPath = $kit.FullName
Write-Host "Using Qt kit: $kitPath"

# Prepare target directories
$deploy = Join-Path $AppDir 'deploy_tmp'
Remove-Item -Recurse -Force $deploy -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $deploy | Out-Null

# Copy Qt DLLs from kit bin
$bin = Join-Path $kitPath 'bin'
if (Test-Path $bin) {
    Write-Host "Copying DLLs from $bin"
    Copy-Item -Path (Join-Path $bin '*.dll') -Destination $deploy -Force -ErrorAction SilentlyContinue
}

# Copy plugins (including platforms)
$plugins = Join-Path $kitPath 'plugins'
if (Test-Path $plugins) {
    Write-Host "Copying plugins from $plugins"
    Copy-Item -Path $plugins -Destination $deploy -Recurse -Force -ErrorAction SilentlyContinue
}

# Copy qml modules if present
$qmlsrc = Join-Path $kitPath 'qml'
if (Test-Path $qmlsrc) {
    Write-Host "Copying QML modules from $qmlsrc"
    Copy-Item -Path $qmlsrc -Destination $deploy -Recurse -Force -ErrorAction SilentlyContinue
}

# Try to copy common MinGW runtime DLLs (look near kit path)
$possibleMingw = Get-ChildItem -Path $QtRoot -Directory -Recurse -Depth 4 | Where-Object { $_.Name -match 'mingw' -and (Test-Path (Join-Path $_.FullName 'bin')) } | Select-Object -First 1
if ($possibleMingw) {
    $mingwBin = Join-Path $possibleMingw.FullName 'bin'
    Write-Host "Searching MinGW runtime DLLs in $mingwBin"
    $mingwFiles = @('libgcc_s_seh-1.dll','libstdc++-6.dll','libwinpthread-1.dll')
    foreach ($f in $mingwFiles) {
        $src = Join-Path $mingwBin $f
        if (Test-Path $src) { Copy-Item -Path $src -Destination $deploy -Force }
    }
}

Write-Host "Deploy files prepared in: $deploy"
Write-Host "Contents:"; Get-ChildItem -Recurse $deploy | Select-Object FullName,Length | Format-Table -AutoSize

Write-Host "Now move the contents of $deploy into the folder with Cetus.exe (overwrite existing files)."
Write-Host "If you want zip, run: Compress-Archive -Path $deploy\* -DestinationPath $AppDir\deploy.zip"

Write-Host "Done. If the app still fails to start, run Cetus.exe from cmd.exe and collect output, or set environment variable QT_DEBUG_PLUGINS=1 before running to see plugin load errors."

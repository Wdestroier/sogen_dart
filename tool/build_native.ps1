$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'bootstrap_native.ps1')
$sourceDirectory = Join-Path $root 'build/deps/sogen'
$buildDirectory = Join-Path $root 'build/native'

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) {
    $cmake = $cmake.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'CMake was not found on PATH and Visual Studio Installer is unavailable.'
    }
    $installations = @(& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json |
        ConvertFrom-Json)
    $installation = $installations[0]
    if (-not $installation) {
        throw 'Visual Studio with the MSVC x64 tools was not found.'
    }
    $cmake = Join-Path $installation.installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
    if (-not (Test-Path -LiteralPath $cmake)) {
        throw "Visual Studio CMake was not found at $cmake."
    }
}

& $cmake -S (Join-Path $root 'native') -B $buildDirectory `
    "-DSOGEN_SOURCE_DIR=$sourceDirectory" `
    -DSOGEN_BUILD_TOOLS=OFF `
    -DSOGEN_ENABLE_PYTHON_BINDINGS=OFF `
    -DSOGEN_ENABLE_LTO=OFF
& $cmake --build $buildDirectory --config Release --target sogen_dart --parallel

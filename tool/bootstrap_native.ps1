$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$lockPath = Join-Path $root 'sogen.lock'
$dependencyRoot = Join-Path $root 'build/deps'
$sourceDirectory = Join-Path $dependencyRoot 'sogen'

$lock = @{}
Get-Content -LiteralPath $lockPath | ForEach-Object {
    $key, $value = $_ -split ': ', 2
    $lock[$key] = $value
}

if (Test-Path -LiteralPath $sourceDirectory) {
    $actual = git -C $sourceDirectory rev-parse HEAD
    if ($actual -ne $lock.commit) {
        throw "Existing Sogen checkout is $actual; expected $($lock.commit). Remove build/deps/sogen and retry."
    }
    git -C $sourceDirectory submodule update --init --recursive
    exit 0
}

New-Item -ItemType Directory -Force -Path $dependencyRoot | Out-Null
git clone --no-checkout $lock.repository $sourceDirectory
git -C $sourceDirectory checkout --detach $lock.commit
git -C $sourceDirectory submodule update --init --recursive

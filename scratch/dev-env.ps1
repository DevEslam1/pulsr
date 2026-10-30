# Local dev-shell environment repair for the AutoClaw exec sandbox.
# The sandbox inherits a stripped environment; Flutter/Dart/Android tooling
# needs these Windows shell variables to resolve the pub cache and SDK paths.
# Dot-source it before invoking flutter:  . .\scratch\dev-env.ps1

$user = 'C:\Users\Eslam'
$local = Join-Path $user 'AppData\Local'

$env:LOCALAPPDATA = $local
$env:APPDATA = Join-Path $user 'AppData\Roaming'
$env:TEMP = Join-Path $local 'Temp'
$env:TMP = $env:TEMP
$env:PUB_CACHE = Join-Path $local 'Pub\Cache'
$env:ProgramData = 'C:\ProgramData'
[Environment]::SetEnvironmentVariable('ProgramFiles(x86)', 'C:\Program Files (x86)')
$env:ANDROID_HOME = Join-Path $local 'Android\Sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

Write-Verbose "dev-env: LOCALAPPDATA=$env:LOCALAPPDATA PUB_CACHE=$env:PUB_CACHE"

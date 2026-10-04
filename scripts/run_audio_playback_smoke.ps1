param(
    [Parameter(Mandatory = $true)][string]$SdkRoot,
    [Parameter(Mandatory = $true)][string]$AudioFile,
    [string]$ApkPath,
    [string]$Serial = 'emulator-5554',
    [string]$Package = 'com.pulsr.music.ytm',
    [int]$AdbPort = 5037
)
$ErrorActionPreference = 'Stop'
$playbackAdb = Join-Path $SdkRoot 'platform-tools/adb.exe'

function Invoke-PlaybackAdb([string[]]$DeviceArgs) {
    $deviceOutput = & $playbackAdb -P $AdbPort -s $Serial @DeviceArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($deviceOutput -join "`n") }
    return ($deviceOutput -join "`n")
}

function Get-PlaybackState {
    $sessionDump = Invoke-PlaybackAdb @('shell', 'dumpsys', 'media_session')
    $inPackage = $false
    foreach ($sessionLine in $sessionDump.Split("`n")) {
        if ($sessionLine.TrimStart().StartsWith('package=')) {
            $inPackage = $sessionLine.Trim() -eq "package=$Package"
        }
        if ($inPackage -and $sessionLine -match 'state=PlaybackState \{state=(\w+)\(\d+\), position=(\d+)') {
            return @{ State = $Matches[1]; Position = [long]$Matches[2] }
        }
    }
    return @{ State = 'ABSENT'; Position = 0 }
}

function Wait-PlaybackState([string]$ExpectedState) {
    $stateDeadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $observedState = Get-PlaybackState
        if ($observedState.State -eq $ExpectedState) { return $observedState }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $stateDeadline)
    throw "Expected $ExpectedState, got $($observedState.State). Inspect Android playback logs."
}

# Use a test device and a WAV longer than ten seconds. Installing is optional;
# existing app preferences and its music database are preserved.
if ($ApkPath) { Invoke-PlaybackAdb @('install', '-r', $ApkPath) | Out-Null }
Invoke-PlaybackAdb @('push', $AudioFile, '/sdcard/Music/pulsr-playback-smoke.wav') | Out-Null
$androidApi = [int](Invoke-PlaybackAdb @('shell', 'getprop', 'ro.build.version.sdk'))
$audioPermission = if ($androidApi -ge 33) { 'android.permission.READ_MEDIA_AUDIO' } else { 'android.permission.READ_EXTERNAL_STORAGE' }
$permissionDump = Invoke-PlaybackAdb @('shell', 'dumpsys', 'package', $Package)
if ($permissionDump -notmatch ([regex]::Escape($audioPermission) + ': granted=true')) {
    Invoke-PlaybackAdb @('shell', 'pm', 'grant', $Package, $audioPermission) | Out-Null
}
Invoke-PlaybackAdb @('shell', 'am', 'force-stop', $Package) | Out-Null
Invoke-PlaybackAdb @('shell', 'am', 'start', '-n', "$Package/com.pulsr.music.MainActivity",
    '-a', 'android.intent.action.VIEW', '-d', 'file:///sdcard/Music/pulsr-playback-smoke.wav', '-t', 'audio/wav') | Out-Null
Wait-PlaybackState 'PLAYING' | Out-Null
Start-Sleep -Seconds 5
Invoke-PlaybackAdb @('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE') | Out-Null
$pausedPlayback = Wait-PlaybackState 'PAUSED'
if ($pausedPlayback.Position -lt 1000) { throw 'Playback did not advance by at least one second.' }
Invoke-PlaybackAdb @('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PLAY') | Out-Null
Wait-PlaybackState 'PLAYING' | Out-Null
Invoke-PlaybackAdb @('shell', 'input', 'keyevent', 'KEYCODE_MEDIA_PAUSE') | Out-Null
Write-Output "PASS: Android cold-start source loading, playback progress ($($pausedPlayback.Position)ms), pause and resume."

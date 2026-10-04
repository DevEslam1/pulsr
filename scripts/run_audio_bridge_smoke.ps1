param(
    [Parameter(Mandatory = $true)][string]$SdkRoot,
    [Parameter(Mandatory = $true)][string]$JdkRoot,
    [Parameter(Mandatory = $true)][string]$NativeLibrary,
    [string]$Serial = 'emulator-5554',
    [string]$BuildToolsVersion = '36.0.0',
    [string]$NdkVersion = '28.2.13676358'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$out = Join-Path $repo 'build/audioBridgeSmoke'
$classes = Join-Path $out 'classes'
$dex = Join-Path $out 'dex'
$headers = Join-Path $out 'headers'
New-Item -ItemType Directory -Force $classes, $dex, $headers | Out-Null

function Invoke-AuditTool([string]$exe, [string[]]$toolArgs) {
    & $exe @toolArgs
    if ($LASTEXITCODE -ne 0) { throw "$exe failed with exit code $LASTEXITCODE" }
}

$cacheFiles = @(rg --files (Join-Path $env:USERPROFILE '.gradle/caches'))
$commonJar = $cacheFiles | Where-Object { $_ -match 'media3-common-1\.4\.1[\\/]jars[\\/]classes\.jar$' } | Select-Object -First 1
$exoplayerJar = $cacheFiles | Where-Object { $_ -match 'media3-exoplayer-1\.4\.1[\\/]jars[\\/]classes\.jar$' } | Select-Object -First 1
$guavaJar = $cacheFiles | Where-Object { $_ -match 'guava-.*android\.jar$' } | Select-Object -First 1
if (!$commonJar) { throw 'Run the Android Gradle build first to cache Media3 1.4.1.' }
$androidJar = Join-Path $SdkRoot 'platforms/android-35/android.jar'
$javaSources = @(
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AaudioNativeBridge.java'),
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/AAudioAudioSink.java'),
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/FloatDspAudioSink.java'),
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/NativeDspAudioProcessor.java'),
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/Pcm16Quantizer.java'),
    (Join-Path $repo 'android/app/src/test/java/com/ryanheise/just_audio/AaudioBridgeSmoke.java'),
    (Join-Path $PSScriptRoot 'audio_bridge_smoke/AudioEffectsPlugin.java'),
    (Join-Path $PSScriptRoot 'audio_bridge_smoke/NativeDspSmoke.java'),
    (Join-Path $PSScriptRoot 'audio_bridge_smoke/AaudioSinkSmoke.java'),
    (Join-Path $PSScriptRoot 'audio_bridge_smoke/FloatSinkSmoke.java'),
    (Join-Path $PSScriptRoot 'audio_bridge_smoke/OutputRoutingSmoke.java'),
    (Join-Path $repo 'third_party/just_audio/android/src/main/java/com/ryanheise/just_audio/PulsrOutputRouting.java')
)
Invoke-AuditTool (Join-Path $JdkRoot 'bin/javac.exe') (@('--release', '17', '-cp', "$commonJar;$exoplayerJar;$androidJar", '-h', $headers, '-d', $classes) + $javaSources)

$llvmBin = Join-Path $SdkRoot "ndk/$NdkVersion/toolchains/llvm/prebuilt/windows-x86_64/bin"
$exports = & (Join-Path $llvmBin 'llvm-nm.exe') -D $NativeLibrary
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect native library.' }
$header = Get-Content (Join-Path $headers 'com_ryanheise_just_audio_AaudioNativeBridge.h') -Raw
foreach ($match in [regex]::Matches($header, 'Java_[A-Za-z0-9_]+')) {
    if (!($exports -match "\b$($match.Value)$")) { throw "JNI export missing: $($match.Value)" }
}

$classFiles = @(Get-ChildItem -LiteralPath $classes -Recurse -Filter '*.class' | ForEach-Object FullName)
$dexInputs = @($commonJar, $exoplayerJar) + $classFiles
if ($guavaJar) { $dexInputs += $guavaJar }
Invoke-AuditTool (Join-Path $SdkRoot "build-tools/$BuildToolsVersion/d8.bat") (@('--min-api', '28', '--lib', $androidJar, '--output', $dex) + $dexInputs)

$adb = Join-Path $SdkRoot 'platform-tools/adb.exe'
$remote = '/data/local/tmp/pulsr_audio_audit'
Invoke-AuditTool $adb @('-s', $Serial, 'shell', 'mkdir', '-p', $remote)
Invoke-AuditTool $adb @('-s', $Serial, 'push', (Join-Path $dex 'classes.dex'), "$remote/classes.dex")
Invoke-AuditTool $adb @('-s', $Serial, 'push', $NativeLibrary, "$remote/libpulsr_dsp.so")
$deviceAbi = (& $adb -s $Serial shell getprop ro.product.cpu.abi).Trim()
$runtimeTriple = switch ($deviceAbi) {
    'arm64-v8a' { 'aarch64-linux-android' }
    'armeabi-v7a' { 'arm-linux-androideabi' }
    'x86_64' { 'x86_64-linux-android' }
    'x86' { 'i686-linux-android' }
    default { throw "Unsupported device ABI: $deviceAbi" }
}
$runtime = Join-Path $SdkRoot "ndk/$NdkVersion/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/$runtimeTriple/libc++_shared.so"
Invoke-AuditTool $adb @('-s', $Serial, 'push', $runtime, "$remote/libc++_shared.so")
foreach ($main in @('AaudioBridgeSmoke', 'NativeDspSmoke', 'AaudioSinkSmoke', 'FloatSinkSmoke', 'OutputRoutingSmoke')) {
    Invoke-AuditTool $adb @('-s', $Serial, 'shell', "CLASSPATH=$remote/classes.dex LD_LIBRARY_PATH=$remote app_process /system/bin com.ryanheise.just_audio.$main")
}

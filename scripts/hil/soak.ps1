<#
.SYNOPSIS
  PowerShell wrapper for scripts/hil/soak.py (PS 5.1 compatible).

.EXAMPLE
  powershell -NoProfile -File scripts/hil/soak.ps1 -DryRun -Out scratch/hil/soak_ps.json
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Out,
    [switch]$Gate,
    [string]$Adb = 'auto',
    [string]$Serial,
    [string]$DriverCmd,
    [double]$Hours = 8,
    [double]$SampleInterval = 10,
    [int]$MaxSamples = 0,
    [double]$MaxDriftPpm = 100,
    [int]$MaxUnderruns = 0,
    [int]$MaxOverruns = 0,
    [int]$Timeout = 120,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'soak.py'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    [Console]::Error.WriteLine("error: missing $scriptPath")
    exit 3
}

$python = Get-Command -Name python -ErrorAction SilentlyContinue
if (-not $python) {
    [Console]::Error.WriteLine('error: python not found on PATH')
    exit 127
}

$arguments = @($scriptPath)
if ($DryRun) { $arguments += '--dry-run' }
if ($Gate) { $arguments += '--gate' }
if ($Out) { $arguments += @('--out', $Out) }
if ($Adb) { $arguments += @('--adb', $Adb) }
if ($Serial) { $arguments += @('--serial', $Serial) }
if ($DriverCmd) { $arguments += @('--driver-cmd', $DriverCmd) }
if ($Hours -gt 0) { $arguments += @('--hours', [string]$Hours) }
if ($SampleInterval -gt 0) { $arguments += @('--sample-interval', [string]$SampleInterval) }
if ($MaxSamples -gt 0) { $arguments += @('--max-samples', [string]$MaxSamples) }
if ($MaxDriftPpm -gt 0) { $arguments += @('--max-drift-ppm', [string]$MaxDriftPpm) }
$arguments += @('--max-underruns', [string]$MaxUnderruns)
$arguments += @('--max-overruns', [string]$MaxOverruns)
if ($Timeout -gt 0) { $arguments += @('--timeout', [string]$Timeout) }
if ($Rest) { $arguments += $Rest }

& $python.Source @arguments
exit $LASTEXITCODE

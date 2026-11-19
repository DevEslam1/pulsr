<#
.SYNOPSIS
  PowerShell wrapper for scripts/hil/smoke.py (PS 5.1 compatible).

.EXAMPLE
  powershell -NoProfile -File scripts/hil/smoke.ps1 -DryRun -Out scratch/hil/smoke_ps.json
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Out,
    [switch]$Gate,
    [string]$Adb = 'auto',
    [string]$Serial,
    [string]$DriverCmd,
    [double]$Duration = 60,
    [double]$Interval = 5,
    [int]$Timeout = 120,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'smoke.py'
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
if ($Duration -gt 0) { $arguments += @('--duration', [string]$Duration) }
if ($Interval -gt 0) { $arguments += @('--interval', [string]$Interval) }
if ($Timeout -gt 0) { $arguments += @('--timeout', [string]$Timeout) }
if ($Rest) { $arguments += $Rest }

& $python.Source @arguments
exit $LASTEXITCODE

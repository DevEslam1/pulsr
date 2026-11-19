<#
.SYNOPSIS
  PowerShell wrapper for scripts/hil/unplug_replug.py (PS 5.1 compatible).

.EXAMPLE
  powershell -NoProfile -File scripts/hil/unplug_replug.ps1 -DryRun -Out scratch/hil/unplug_ps.json
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Out,
    [switch]$Gate,
    [string]$Adb = 'auto',
    [string]$Serial,
    [string]$DriverCmd,
    [string]$RelayCmd,
    [int]$Cycles = 500,
    [double]$MaxRecoveryMs = 2000,
    [double]$Settle = 1,
    [int]$Timeout = 60,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'unplug_replug.py'
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
if ($RelayCmd) { $arguments += @('--relay-cmd', $RelayCmd) }
if ($Cycles -gt 0) { $arguments += @('--cycles', [string]$Cycles) }
if ($MaxRecoveryMs -gt 0) { $arguments += @('--max-recovery-ms', [string]$MaxRecoveryMs) }
if ($Settle -ge 0) { $arguments += @('--settle', [string]$Settle) }
if ($Timeout -gt 0) { $arguments += @('--timeout', [string]$Timeout) }
if ($Rest) { $arguments += $Rest }

& $python.Source @arguments
exit $LASTEXITCODE

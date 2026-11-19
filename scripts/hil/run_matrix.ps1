<#
.SYNOPSIS
  PowerShell wrapper for scripts/hil/run_matrix.py (PS 5.1 compatible).

.DESCRIPTION
  Forwards named switches plus any extra arguments to the Python gate and
  returns its exit code unchanged:
    0 pass or blocked (dry-run), 2 blocked with -Gate, 1 failing case, 3 error.

.EXAMPLE
  powershell -NoProfile -File scripts/hil/run_matrix.ps1 -DryRun -Out scratch/hil/matrix_ps.json
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Out,
    [switch]$Gate,
    [ValidateSet('A', 'B', 'all')][string]$Tier = 'all',
    [int]$Timeout = 300,
    [string]$Adb = 'auto',
    [string]$Serial,
    [string]$PlayCmd,
    [switch]$List,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'run_matrix.py'
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
if ($Tier) { $arguments += @('--tier', $Tier) }
if ($Timeout -gt 0) { $arguments += @('--timeout', [string]$Timeout) }
if ($Adb) { $arguments += @('--adb', $Adb) }
if ($Serial) { $arguments += @('--serial', $Serial) }
if ($PlayCmd) { $arguments += @('--play-cmd', $PlayCmd) }
if ($List) { $arguments += '--list' }
if ($Rest) { $arguments += $Rest }

& $python.Source @arguments
exit $LASTEXITCODE

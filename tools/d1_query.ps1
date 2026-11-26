# Runs a read-only SELECT against live D1 and prints the rows.
# Usage: powershell -File tools/d1_query.ps1 -Sql "SELECT ..."
# NOTE: Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList, so the
# command line is assembled as one string. SQL must use single quotes only.
param(
  [Parameter(Mandatory = $true)][string]$Sql
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wrangler = Join-Path $root 'workers\node_modules\wrangler\bin\wrangler.js'
if (-not (Test-Path $wrangler)) { throw "wrangler not found at $wrangler" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'node'
$psi.WorkingDirectory = (Join-Path $root 'workers')
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = '"' + $wrangler + '" d1 execute dropoff-db --remote --yes --command "' + ($Sql -replace '"', '\"') + '"'

$p = [System.Diagnostics.Process]::Start($psi)
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
$p.WaitForExit()
Write-Output $out
if ($err) { Write-Output $err }
exit $p.ExitCode

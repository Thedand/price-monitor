[CmdletBinding()]
param([string]$DataPath = (Join-Path $PSScriptRoot 'data\latest.csv'))

$ErrorActionPreference = 'Stop'
$dashboard = Join-Path $PSScriptRoot 'dashboard'
$rows = Import-Csv -LiteralPath $DataPath
if (-not $rows) { throw "No dashboard data in $DataPath" }
$json = $rows | ConvertTo-Json -Depth 4 -Compress
$payload = "window.PRICE_DATA = $json;"
[IO.File]::WriteAllText((Join-Path $dashboard 'data.js'), $payload, [Text.UTF8Encoding]::new($false))
Write-Host "Dashboard data: $(Join-Path $dashboard 'data.js')"

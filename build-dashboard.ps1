[CmdletBinding()]
param(
    [string]$DataPath = (Join-Path $PSScriptRoot 'data\latest.csv'),
    [string]$HistoryPath = (Join-Path $PSScriptRoot 'data\history.csv'),
    [int]$HistorySnapshots = 12
)

$ErrorActionPreference = 'Stop'
$dashboard = Join-Path $PSScriptRoot 'dashboard'
$rows = @(Import-Csv -LiteralPath $DataPath)
if (-not $rows) { throw "No dashboard data in $DataPath" }

$historyRows = if (Test-Path -LiteralPath $HistoryPath) {
    @(Import-Csv -LiteralPath $HistoryPath)
} else {
    $rows
}

# Several development runs may exist on the same date. Keep only the latest
# complete snapshot for each date, then bound the browser payload.
$snapshots = @($historyRows |
    Group-Object { ([DateTimeOffset]::Parse($_.collected_at)).ToString('yyyy-MM-dd') } |
    ForEach-Object {
        $snapshotTime = @($_.Group.collected_at | Sort-Object {
            [DateTimeOffset]::Parse($_)
        } -Descending | Select-Object -First 1)[0]
        $_.Group | Where-Object collected_at -eq $snapshotTime
    } |
    Group-Object collected_at |
    Sort-Object { [DateTimeOffset]::Parse($_.Name) } -Descending |
    Select-Object -First $HistorySnapshots |
    Sort-Object { [DateTimeOffset]::Parse($_.Name) } |
    ForEach-Object { $_.Group })

$history = @($snapshots | Select-Object collected_at, segment, color_normalized,
    package_group, offer_key, store, brand, package_kg, analysis_price,
    unit_price_per_kg)

$priceJson = ConvertTo-Json -InputObject $rows -Depth 4 -Compress
$historyJson = ConvertTo-Json -InputObject $history -Depth 4 -Compress
$payload = "window.PRICE_DATA = $priceJson;`nwindow.PRICE_HISTORY = $historyJson;"
[IO.File]::WriteAllText((Join-Path $dashboard 'data.js'), $payload, [Text.UTF8Encoding]::new($false))
Write-Host "Dashboard data: $(Join-Path $dashboard 'data.js')"
Write-Host "Dashboard history: $((@($history.collected_at | Sort-Object -Unique)).Count) snapshots"

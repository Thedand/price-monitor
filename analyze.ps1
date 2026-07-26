[CmdletBinding()]
param([string]$DataPath = (Join-Path $PSScriptRoot 'data\latest.csv'))

$ErrorActionPreference = 'Stop'
$rows = Import-Csv -LiteralPath $DataPath
if (-not $rows) { throw "No rows in $DataPath" }

function Read-Decimal([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    [decimal]::Parse(($Value -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
}

$offerKeys = @($rows.offer_key | Sort-Object -Unique)
$comparison = foreach ($group in ($rows | Group-Object product_key, segment, color_normalized, package_group)) {
    $offers = @($group.Group | Sort-Object { Read-Decimal $_.unit_price_per_kg })
    $best = $offers[0]
    $highest = $offers[-1]
    $record = [ordered]@{
        product_key=$best.product_key; segment=$best.segment; color=$best.color_normalized
        package_group=$best.package_group; offers_available=$offers.Count
    }
    foreach ($key in $offerKeys) {
        $item = $offers | Where-Object offer_key -eq $key | Select-Object -First 1
        foreach ($field in @('brand','store','package_kg','regular_price','unit_price_per_kg','in_stock')) {
            $record[($key + '_' + $field)] = if ($item) { $item.$field } else { '' }
        }
    }
    $record.best_offer=$best.offer_key
    $record.best_store=$best.store
    $record.best_brand=$best.brand
    $record.best_package_kg=$best.package_kg
    $record.best_price=Read-Decimal $best.analysis_price
    $record.best_unit_price_per_kg=Read-Decimal $best.unit_price_per_kg
    $record.max_unit_saving=if($offers.Count-gt1){(Read-Decimal $highest.unit_price_per_kg)-(Read-Decimal $best.unit_price_per_kg)}else{$null}
    $record.max_unit_saving_percent=if($offers.Count-gt1){[math]::Round(($record.max_unit_saving/(Read-Decimal $highest.unit_price_per_kg))*100,2)}else{$null}
    [pscustomobject]$record
}

$ranking = foreach ($group in ($rows | Group-Object product_key, segment, color_normalized, package_group)) {
    $rank=0
    foreach ($item in ($group.Group | Sort-Object { Read-Decimal $_.unit_price_per_kg })) {
        $rank++
        [pscustomobject][ordered]@{
            product_key=$item.product_key; segment=$item.segment; color=$item.color_normalized
            package_group=$item.package_group; rank=$rank; offer_key=$item.offer_key
            store=$item.store; brand=$item.brand; package_kg=$item.package_kg
            regular_price=Read-Decimal $item.analysis_price; promo_price=Read-Decimal $item.promo_price
            unit_price_per_kg=Read-Decimal $item.unit_price_per_kg; in_stock=$item.in_stock; url=$item.url
        }
    }
}

$reportDirectory=Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$comparisonPath=Join-Path $reportDirectory 'comparison.csv'
$rankingPath=Join-Path $reportDirectory 'ranking.csv'
$comparison|Sort-Object segment,package_group,color|Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $comparisonPath
$ranking|Sort-Object segment,package_group,color,rank|Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $rankingPath
$comparison|Group-Object segment|ForEach-Object{Write-Host "$($_.Name): $($_.Count) comparison groups"}
Write-Host "Comparison: $comparisonPath"
Write-Host "Ranking:    $rankingPath"

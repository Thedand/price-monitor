[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config\products.json'),
    [string]$DataDirectory = (Join-Path $PSScriptRoot 'data'),
    [int]$CacheHours = 6,
    [int]$MaxVariantDrop = 2,
    [decimal]$MaxVariantDropPercent = 5,
    [ValidateRange(0, 60000)][int]$RequestDelayMilliseconds = 2000,
    [ValidateRange(0, 10)][int]$MaxHttpRetries = 4,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Headers = @{
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/136.0 Safari/537.36'
    'Accept' = 'text/html,application/xhtml+xml'
}
$ColorAliases = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'config\color-aliases.json') | ConvertFrom-Json -AsHashtable
$Config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'lib\ProductTitleParser.ps1')
$CollectedAt = [DateTimeOffset]::Now.ToString('o')
$Script:SitemapCache = @{}
$CacheDirectory = Join-Path $PSScriptRoot 'cache'
$BaselinePath = Join-Path $DataDirectory 'latest.csv'
$BaselineRows = if (Test-Path -LiteralPath $BaselinePath) {
    @(Import-Csv -LiteralPath $BaselinePath)
} else {
    @()
}
New-Item -ItemType Directory -Force -Path $CacheDirectory | Out-Null

function Get-PageContent([string]$Url, [int]$TimeoutSec = 30) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Url))).ToLowerInvariant()
    } finally { $sha.Dispose() }
    $cachePath = Join-Path $CacheDirectory ($hash + '.html')
    if (-not $Refresh -and (Test-Path -LiteralPath $cachePath)) {
        $age = [DateTime]::UtcNow - (Get-Item -LiteralPath $cachePath).LastWriteTimeUtc
        if ($age.TotalHours -lt $CacheHours) { return Get-Content -Raw -LiteralPath $cachePath }
    }
    for ($attempt = 0; $attempt -le $MaxHttpRetries; $attempt++) {
        try {
            $content = (Invoke-WebRequest -Uri $Url -Headers $Headers -MaximumRedirection 5 -TimeoutSec $TimeoutSec).Content
            [IO.File]::WriteAllText($cachePath, $content, [Text.UTF8Encoding]::new($false))
            return $content
        } catch {
            $response = $_.Exception.Response
            $statusCode = if ($response -and $response.StatusCode) { [int]$response.StatusCode } else { 0 }
            $retryable = $statusCode -in @(408, 425, 429, 500, 502, 503, 504)
            if (-not $retryable -or $attempt -eq $MaxHttpRetries) {
                throw "Request failed after $($attempt + 1) attempt(s), HTTP $statusCode`: $Url. $($_.Exception.Message)"
            }

            $delaySeconds = [math]::Min(40, 5 * [math]::Pow(2, $attempt))
            if ($response.Headers -and $response.Headers.RetryAfter -and $response.Headers.RetryAfter.Delta) {
                $delaySeconds = [math]::Min(45, [math]::Max(
                    $delaySeconds,
                    [math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds)
                ))
            }
            Write-Warning "HTTP $statusCode for $Url; retry $($attempt + 1)/$MaxHttpRetries in $delaySeconds seconds."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Convert-Price([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    [decimal]::Parse(($Value.Trim() -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
}

function Normalize-Color([string]$Value) {
    $key = [System.Net.WebUtility]::HtmlDecode($Value).Trim().ToLowerInvariant()
    $key = $key -replace '[–—−]', '-' -replace '\s+', ' '
    if ($ColorAliases.ContainsKey($key)) { return $ColorAliases[$key] }
    (Get-Culture).TextInfo.ToTitleCase($key)
}

function Get-PackageInfo([string]$Package) {
    $normalized = $Package -replace ',', '.'
    $weight = [decimal]::Parse($normalized, [Globalization.CultureInfo]::InvariantCulture)
    $group = if ($weight -ge 0.7 -and $weight -le 1.0) { 'small' }
             elseif ($weight -ge 2.2 -and $weight -le 3.0) { 'large' }
             else { 'other' }
    [pscustomobject]@{ Value = $normalized; Weight = $weight; Group = $group }
}

function New-Row($Product, [string]$OfferKey, [string]$Brand, [string]$Store,
                 [string]$Package, [string]$ColorRaw, $RegularPrice, $PromoPrice,
                 [bool]$InStock, [string]$Sku, [string]$Article,
                 [string]$VariantId, [string]$Url) {
    $packageInfo = Get-PackageInfo $Package
    [pscustomobject][ordered]@{
        collected_at       = $CollectedAt
        product_key        = $Product.key
        segment            = $Product.segment
        offer_key          = $OfferKey
        store              = $Store
        brand              = $Brand
        product            = $Product.product
        color_raw          = $ColorRaw
        color_normalized   = Normalize-Color $ColorRaw
        package_kg         = $packageInfo.Value
        package_group      = $packageInfo.Group
        regular_price      = $RegularPrice
        promo_price        = $PromoPrice
        analysis_price     = $RegularPrice
        unit_price_per_kg  = [math]::Round(([decimal]$RegularPrice / $packageInfo.Weight), 4)
        currency            = 'PRB'
        in_stock            = $InStock
        sku                 = $Sku
        article             = $Article
        variant_id          = $VariantId
        url                 = $Url
    }
}

function Get-MirRemontaRows($Product, [string]$OfferKey, $Source) {
    $html = Get-PageContent $Source.url 30
    if ($html -notmatch '<main id="product"') { throw "Unexpected mirremonta page: $($Source.url)" }
    $pattern = "<a[^>]+data-id='(?<id>[^']+)'[^>]+data-group_1='(?<package>[^']+)'[^>]+data-group_2='[^']*'[^>]+data-code='(?<code>[^']+)'[^>]+data-article='(?<article>[^']*)'[^>]+data-price='(?<price>[^']+)'[^>]+data-price_b2b='[^']*'[^>]+data-img='[^']*'[^>]+data-cont='[^']*'[^>]+data-balance='(?<stock>[^']*)'[^>]*>(?<color>[^<]+)</a>"
    foreach ($match in [regex]::Matches($html, $pattern, 'IgnoreCase')) {
        New-Row $Product $OfferKey $Source.brand $Source.store $match.Groups['package'].Value $match.Groups['color'].Value `
            (Convert-Price $match.Groups['price'].Value) $null `
            ([decimal]$match.Groups['stock'].Value -gt 0) $match.Groups['code'].Value `
            $match.Groups['article'].Value $match.Groups['id'].Value $Source.url
    }
}

function Get-SitemapUrls([string]$Url) {
    if (-not $Script:SitemapCache.ContainsKey($Url)) {
        $xml = Get-PageContent $Url 90
        $Script:SitemapCache[$Url] = @([regex]::Matches($xml, '<loc>(?<value>[^<]+)</loc>') | ForEach-Object {
            [System.Net.WebUtility]::HtmlDecode($_.Groups['value'].Value)
        })
    }
    $Script:SitemapCache[$Url]
}

function Get-FarbaSitemapRows($Product, [string]$OfferKey, $Source) {
    $urls = @(Get-SitemapUrls $Source.sitemapUrl | Where-Object { $_ -match $Source.urlPattern })
    foreach ($url in $urls) {
        $html = Get-PageContent $url 30
        $title = [System.Net.WebUtility]::HtmlDecode([regex]::Match($html, '<h1[^>]*class="[^"]*title_mod[^"]*"[^>]*>(?<value>.*?)</h1>', 'IgnoreCase').Groups['value'].Value)
        $old = [regex]::Match($html, 'class="productOldPrice"[^>]*>\s*(?<value>[0-9]+,[0-9]+)', 'IgnoreCase').Groups['value'].Value
        $current = [regex]::Match($html, 'class="productPrice"[^>]*>\s*(?<value>[0-9]+,[0-9]+)', 'IgnoreCase').Groups['value'].Value
        $sku = [regex]::Match($html, 'Код:&nbsp;(?<value>[^<]+)', 'IgnoreCase').Groups['value'].Value
        $id = [regex]::Match($html, 'data-pid="(?<value>\d+)"', 'IgnoreCase').Groups['value'].Value
        try {
            $attributes = Resolve-ProductTitleAttributes -Title $title -ProductName $Product.product `
                -Brand $Source.brand -BrandRegex $Source.brandRegex -LegacyTitleRegex $Source.titleRegex `
                -ColorAliases $ColorAliases -AllowedPackages $Source.allowedPackages `
                -Sku $sku -AttributeOverrides $Source.attributeOverrides
        } catch {
            throw "$($_.Exception.Message) ($url)"
        }
        $regular = if ($old) { Convert-Price $old } else { Convert-Price $current }
        $promo = if ($old) { Convert-Price $current } else { $null }
        $inStock = $html -notmatch 'Нет в наличии|Закончился'
        New-Row $Product $OfferKey $attributes.Brand $Source.store $attributes.Package `
            $attributes.Color $regular $promo $inStock $sku '' $id $url
        if ($RequestDelayMilliseconds) { Start-Sleep -Milliseconds $RequestDelayMilliseconds }
    }
}

function Get-LursanCategoryRows($Product, [string]$OfferKey, $Source) {
    for ($page = 1; $page -le $Source.maxPages; $page++) {
        $url = if ($page -eq 1) { $Source.url } else { "$($Source.url)&page=$page" }
        $html = Get-PageContent $url 90
        if ($html -notmatch 'product-thumb uni-item') { throw "Unexpected lursan category page: $url" }
        foreach ($block in ($html -split '<div class="product-thumb uni-item">' | Select-Object -Skip 1)) {
            $match = [regex]::Match($block, '<a class="product-thumb__name" href="(?<url>[^"]+)">(?<title>[^<]+)</a>[\s\S]*?<div class="product-thumb__price price" data-price="(?<price>[^"]+)" data-special="(?<special>[^"]*)"', 'IgnoreCase')
            if (-not $match.Success) { continue }
            $title = [System.Net.WebUtility]::HtmlDecode($match.Groups['title'].Value)
            try {
                $attributes = Resolve-ProductTitleAttributes -Title $title -ProductName $Product.product `
                    -Brand $Source.brand -BrandRegex $Source.brandRegex -LegacyTitleRegex $Source.titleRegex `
                    -ColorAliases $ColorAliases -AllowedPackages $Source.allowedPackages `
                    -AttributeOverrides $Source.attributeOverrides
            } catch {
                Write-Warning "$($_.Exception.Message) ($($match.Groups['url'].Value))"
                continue
            }
            $regular = Convert-Price $match.Groups['price'].Value
            $special = Convert-Price $match.Groups['special'].Value
            $promo = if ($special -and $special -gt 0) { $special } else { $null }
            $productUrl = [System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)
            $id = [regex]::Match($productUrl, 'product_id=(?<value>\d+)').Groups['value'].Value
            $inStock = $block -notmatch 'Закончился|Скоро в наличии'
            New-Row $Product $OfferKey $attributes.Brand $Source.store $attributes.Package `
                $attributes.Color $regular $promo $inStock '' '' $id $productUrl
        }
        if ($page -lt $Source.maxPages -and $RequestDelayMilliseconds) {
            Start-Sleep -Milliseconds $RequestDelayMilliseconds
        }
    }
}

$Rows = @()
foreach ($product in $Config.products) {
    foreach ($sourceProperty in $product.sources.PSObject.Properties) {
        $offerKey = $sourceProperty.Name
        $source = $sourceProperty.Value
        $sourceRows = switch ($source.collector) {
            'mirremonta'      { @(Get-MirRemontaRows $product $offerKey $source) }
            'farba_sitemap'   { @(Get-FarbaSitemapRows $product $offerKey $source) }
            'lursan_category' { @(Get-LursanCategoryRows $product $offerKey $source) }
            default           { throw "Unknown collector: $($source.collector)" }
        }
        $baselineSourceRows = @($BaselineRows | Where-Object {
            $_.product_key -eq $product.key -and $_.offer_key -eq $offerKey
        })
        if ($baselineSourceRows.Count) {
            $allowedDrop = [math]::Max(
                $MaxVariantDrop,
                [math]::Ceiling($baselineSourceRows.Count * $MaxVariantDropPercent / 100)
            )
            $drop = $baselineSourceRows.Count - $sourceRows.Count
            if ($drop -gt $allowedDrop) {
                throw "$offerKey/$($product.key): previous snapshot had $($baselineSourceRows.Count) variants, found $($sourceRows.Count); maximum allowed drop is $allowedDrop. No data was saved."
            }

            $previousUrls = @($baselineSourceRows.url | Where-Object { $_ })
            $currentUrls = @($sourceRows.url | Where-Object { $_ })
            $missingUrls = @(Compare-Object $previousUrls $currentUrls |
                Where-Object SideIndicator -eq '<=' |
                ForEach-Object { $_.InputObject })
            $addedUrls = @(Compare-Object $previousUrls $currentUrls |
                Where-Object SideIndicator -eq '=>' |
                ForEach-Object { $_.InputObject })
            if ($missingUrls.Count -or $addedUrls.Count) {
                Write-Warning "$offerKey/$($product.key): assortment changed; missing $($missingUrls.Count), added $($addedUrls.Count)."
                $missingUrls | ForEach-Object { Write-Warning "Missing: $_" }
                $addedUrls | ForEach-Object { Write-Warning "Added: $_" }
            }
        } elseif ($sourceRows.Count -ne $source.expectedVariants) {
            throw "$offerKey/$($product.key): initial snapshot expected $($source.expectedVariants) variants, found $($sourceRows.Count). No data was saved."
        }
        $Rows += $sourceRows
    }
}

$duplicates = $Rows | Group-Object product_key, offer_key, color_normalized, package_kg | Where-Object Count -gt 1
if ($duplicates) { throw "Duplicate normalized variants found. No data was saved." }
if ($Rows | Where-Object { $null -eq $_.analysis_price -or $_.analysis_price -le 0 }) {
    throw "Missing or invalid analysis prices found. No data was saved."
}

New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$latestPath = Join-Path $DataDirectory 'latest.csv'
$historyPath = Join-Path $DataDirectory 'history.csv'
$Rows | Sort-Object segment, product_key, offer_key, package_group, color_normalized | Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $latestPath

if (Test-Path -LiteralPath $historyPath) {
    $existing = @(Import-Csv -LiteralPath $historyPath)
    if ($existing.Count -and -not ($existing[0].PSObject.Properties.Name -contains 'segment')) {
        $migrated = foreach ($row in $existing) {
            $info = Get-PackageInfo $row.package_kg
            [pscustomobject][ordered]@{
                collected_at=$row.collected_at; product_key='pf115_economy'; segment='economy'
                offer_key=($row.store.Split('.')[0] + '_' + ($row.brand -replace '\s+','_').ToLowerInvariant())
                store=$row.store; brand=$row.brand; product=$row.product; color_raw=$row.color_raw
                color_normalized=$row.color_normalized; package_kg=$info.Value; package_group=$info.Group
                regular_price=$row.regular_price; promo_price=$row.promo_price; analysis_price=$row.analysis_price
                unit_price_per_kg=[math]::Round((Convert-Price $row.analysis_price)/$info.Weight,4)
                currency=$row.currency; in_stock=$row.in_stock; sku=$row.sku; article=$row.article
                variant_id=$row.variant_id; url=$row.url
            }
        }
        $migrated | Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $historyPath
    }
    $Rows | Export-Csv -NoTypeInformation -Encoding utf8 -Append -LiteralPath $historyPath
} else {
    $Rows | Export-Csv -NoTypeInformation -Encoding utf8 -LiteralPath $historyPath
}

Write-Host "Collected $($Rows.Count) variants at $CollectedAt"
Write-Host "Latest:  $latestPath"
Write-Host "History: $historyPath"

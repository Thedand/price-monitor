function Resolve-ProductTitleAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$ProductName,
        [Parameter(Mandatory)][string]$Brand,
        [string]$BrandRegex,
        [string]$LegacyTitleRegex,
        [Parameter(Mandatory)][hashtable]$ColorAliases,
        [string[]]$AllowedPackages,
        [string]$Sku,
        $AttributeOverrides
    )

    $text = [System.Net.WebUtility]::HtmlDecode($Title)
    $text = [regex]::Replace($text, '<[^>]+>', ' ')
    $text = ($text -replace '[–—−]', '-' -replace '\s+', ' ').Trim()

    $productCodeMatch = [regex]::Match($ProductName, '(?i)ПФ\s*-\s*\d+')
    if (-not $productCodeMatch.Success) {
        throw "Product configuration has no recognizable product type: $ProductName"
    }
    $productCode = $productCodeMatch.Value -replace '\s+', ''
    $productCodeRegex = '(?i)(?<![\p{L}\p{N}])' +
        ([regex]::Escape($productCode) -replace '\\-', '\s*-\s*') +
        '(?![\p{L}\p{N}])'

    if ([string]::IsNullOrWhiteSpace($BrandRegex)) {
        $BrandRegex = '(?i)(?<!\p{L})' +
            (([regex]::Escape($Brand)) -replace '\\ ', '\s+') +
            '(?!\p{L})'
    }

    $missing = [Collections.Generic.List[string]]::new()
    if ($text -notmatch $productCodeRegex) { $missing.Add("product type '$productCode'") }
    if ($text -notmatch $BrandRegex) { $missing.Add("brand '$Brand'") }

    $override = $null
    if ($AttributeOverrides -and -not [string]::IsNullOrWhiteSpace($Sku)) {
        $overrideProperty = $AttributeOverrides.PSObject.Properties[$Sku]
        if ($overrideProperty) { $override = $overrideProperty.Value }
    }

    $package = if ($override -and $override.package) { [string]$override.package } else { '' }
    $color = if ($override -and $override.color) { [string]$override.color } else { '' }

    if (-not $package) {
        $packageMatch = [regex]::Match($text, '(?i)(?<!\d)(?<package>\d{1,2}[.,]\d{1,2})\s*(?:кг)?(?!\d)')
        if ($packageMatch.Success) { $package = $packageMatch.Groups['package'].Value }
    }

    if (-not $color) {
        foreach ($alias in @($ColorAliases.Keys | Sort-Object Length -Descending)) {
            $aliasRegex = '(?i)(?<!\p{L})' +
                (([regex]::Escape($alias)) -replace '\\ ', '\s+' -replace '\\-', '[-–—−]') +
                '(?!\p{L})'
            $aliasMatch = [regex]::Match($text, $aliasRegex)
            if ($aliasMatch.Success) {
                $color = $aliasMatch.Value
                break
            }
        }
    }

    if ((!$package -or !$color) -and -not [string]::IsNullOrWhiteSpace($LegacyTitleRegex)) {
        $legacyMatch = [regex]::Match($text, $LegacyTitleRegex)
        if ($legacyMatch.Success) {
            if (-not $package) { $package = $legacyMatch.Groups['package'].Value }
            if (-not $color) { $color = $legacyMatch.Groups['color'].Value }
        }
    }

    if (-not $color) {
        $remainder = $text
        $remainder = [regex]::Replace($remainder, $BrandRegex, ' ')
        $remainder = [regex]::Replace($remainder, $productCodeRegex, ' ')
        if ($package) {
            $remainder = [regex]::Replace(
                $remainder,
                '(?i)(?<!\d)' + [regex]::Escape($package) + '\s*(?:кг)?(?!\d)',
                ' '
            )
        }
        $remainder = $remainder -replace '\([^)]*\)', ' '
        $remainder = $remainder -replace '(?i)(?<!\p{L})(?:э?маль|глянцевая|глянцевый|универсальная|универсальный|серия|тм|кг)(?!\p{L})', ' '
        $remainder = ($remainder -replace '[^\p{L}\p{M}-]+', ' ' -replace '\s+', ' ').Trim(' ', '-', ',')
        if ($remainder) { $color = $remainder }
    }

    if (-not $color) { $missing.Add('color') }
    if (-not $package) { $missing.Add('package weight') }
    if ($package -and $AllowedPackages.Count) {
        $normalizedPackage = $package -replace ',', '.'
        $normalizedAllowedPackages = @($AllowedPackages | ForEach-Object { $_ -replace ',', '.' })
        if ($normalizedPackage -notin $normalizedAllowedPackages) {
            $missing.Add("allowed package weight (found '$normalizedPackage'; allowed: $($normalizedAllowedPackages -join ', '))")
        }
    }
    if ($missing.Count) {
        throw "Cannot resolve required attributes ($($missing -join ', ')) from title '$text'"
    }

    [pscustomobject]@{
        ProductType = $productCode
        Brand       = $Brand
        Color       = $color
        Package     = $package -replace ',', '.'
    }
}

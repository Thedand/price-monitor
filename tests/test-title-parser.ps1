$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\ProductTitleParser.ps1')

$aliases = @{
    'бежевая' = 'Бежевый'
    'белая' = 'Белый'
    'желтая' = 'Желтый'
    'синяя' = 'Синий'
    'серая' = 'Серый'
}

$cases = @(
    @{ Title='DekArt Эмаль ПФ-115 бежевая глянцевая /0,9 (уп.6шт)'; Brand='DekArt'; Color='бежевая'; Package='0.9' },
    @{ Title='маль ПФ-115 DekArt бежевая 0,9 кг'; Brand='DekArt'; Color='бежевая'; Package='0.9' },
    @{ Title='ПФ-115 DekArt бежевая 0,9'; Brand='DekArt'; Color='бежевая'; Package='0.9' },
    @{ Title='Farbex Эмаль ПФ-115 желтая глянцевая /0,9'; Brand='Farbex'; Color='желтая'; Package='0.9' },
    @{ Title='Белая эмаль ПФ-115, Fazenda, 0,9 кг'; Brand='Fazenda'; Color='Белая'; Package='0.9' },
    @{ Title='Эмаль ПФ-115 синяя универсальная 0,8кг Zebra серия Master'; Brand='Zebra Master'; BrandRegex='(?i)(?<!\p{L})Zebra(?:\s+серия)?\s+Master(?!\p{L})'; Color='синяя'; Package='0.8' },
    @{ Title='Серая эмаль ПФ-115 ТМ Корабельная, 2,8 кг'; Brand='Корабельная'; Color='Серая'; Package='2.8' }
)

foreach ($case in $cases) {
    $params = @{
        Title = $case.Title
        ProductName = 'Эмаль ПФ-115'
        Brand = $case.Brand
        BrandRegex = $case.BrandRegex
        ColorAliases = $aliases
    }
    $actual = Resolve-ProductTitleAttributes @params
    if ($actual.ProductType -ne 'ПФ-115' -or $actual.Brand -ne $case.Brand -or
        $actual.Color -ne $case.Color -or $actual.Package -ne $case.Package) {
        throw "Unexpected parse result for '$($case.Title)': $($actual | ConvertTo-Json -Compress)"
    }
}

$invalidFailed = $false
try {
    Resolve-ProductTitleAttributes -Title 'Краска неизвестная бежевая 0,9 кг' `
        -ProductName 'Эмаль ПФ-115' -Brand 'DekArt' -ColorAliases $aliases
} catch {
    $invalidFailed = $_.Exception.Message -match 'product type' -and $_.Exception.Message -match 'brand'
}
if (-not $invalidFailed) { throw 'A title without product type and brand was not rejected.' }

$packageFailed = $false
try {
    Resolve-ProductTitleAttributes -Title 'ПФ-115 DekArt бежевая 1,9 кг' `
        -ProductName 'Эмаль ПФ-115' -Brand 'DekArt' -ColorAliases $aliases `
        -AllowedPackages @('0.9', '2.8')
} catch {
    $packageFailed = $_.Exception.Message -match 'allowed package weight'
}
if (-not $packageFailed) { throw 'A title with a disallowed package weight was not rejected.' }

Write-Host "Product title parser: $($cases.Count) valid cases and 2 rejections passed."

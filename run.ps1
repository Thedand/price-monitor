$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'collect.ps1')
& (Join-Path $PSScriptRoot 'analyze.ps1')
& (Join-Path $PSScriptRoot 'build-dashboard.ps1')

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\local.psd1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Materials Project config file does not exist: $ConfigPath"
}

$resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
$apiKey = [string]$config.MaterialsProjectApiKey

if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -eq '<replace-locally>') {
    throw "MaterialsProjectApiKey is missing or still uses the placeholder in: $resolvedConfigPath"
}

$env:MP_API_KEY = $apiKey
Write-Output "MP_API_KEY loaded from local config: $resolvedConfigPath"

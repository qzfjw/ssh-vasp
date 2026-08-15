Set-StrictMode -Version Latest

function Copy-VaspRuleValue {
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[$key] = Copy-VaspRuleValue -Value $Value[$key]
        }
        return $copy
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Copy-VaspRuleValue -Value $_ })
    }
    return $Value
}

function Merge-VaspRuleMap {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Override
    )

    $merged = Copy-VaspRuleValue -Value $Base
    foreach ($key in $Override.Keys) {
        if (
            $merged.Contains($key) -and
            $merged[$key] -is [System.Collections.IDictionary] -and
            $Override[$key] -is [System.Collections.IDictionary]
        ) {
            $merged[$key] = Merge-VaspRuleMap -Base $merged[$key] -Override $Override[$key]
        } else {
            $merged[$key] = Copy-VaspRuleValue -Value $Override[$key]
        }
    }
    return $merged
}

function Import-VaspRuleSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [string]$OverridePath = '',
        [int]$ExpectedSchemaVersion = 1,
        [string[]]$RequiredKeys = @()
    )

    if (-not (Test-Path -LiteralPath $BasePath -PathType Leaf)) {
        throw "Rule file does not exist: $BasePath"
    }
    $resolvedBasePath = (Resolve-Path -LiteralPath $BasePath).Path
    $rules = Import-PowerShellDataFile -LiteralPath $resolvedBasePath
    if ([int]$rules.SchemaVersion -ne $ExpectedSchemaVersion) {
        throw "Unsupported rule schema in $resolvedBasePath. Expected $ExpectedSchemaVersion, found $($rules.SchemaVersion)."
    }

    if (-not [string]::IsNullOrWhiteSpace($OverridePath)) {
        if (-not (Test-Path -LiteralPath $OverridePath -PathType Leaf)) {
            throw "Rule override file does not exist: $OverridePath"
        }
        $resolvedOverridePath = (Resolve-Path -LiteralPath $OverridePath).Path
        $override = Import-PowerShellDataFile -LiteralPath $resolvedOverridePath
        if ($override.Contains('SchemaVersion') -and [int]$override.SchemaVersion -ne $ExpectedSchemaVersion) {
            throw "Unsupported override schema in $resolvedOverridePath. Expected $ExpectedSchemaVersion, found $($override.SchemaVersion)."
        }
        $rules = Merge-VaspRuleMap -Base $rules -Override $override
    }

    foreach ($key in $RequiredKeys) {
        if (-not $rules.Contains($key) -or $null -eq $rules[$key]) {
            throw "Required rule section '$key' is missing from $resolvedBasePath."
        }
    }
    return $rules
}

Export-ModuleMember -Function Import-VaspRuleSet, Merge-VaspRuleMap

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-ServerSettings {
    param([object]$Value)

    $copy = @{}
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $copy[[string]$key] = $Value[$key]
        }
    }
    return $copy
}

function Import-VaspServerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [string]$LocalPath = ''
    )

    if (-not (Test-Path -LiteralPath $BasePath -PathType Leaf)) {
        throw "Server config file does not exist: $BasePath"
    }

    $resolvedBasePath = (Resolve-Path -LiteralPath $BasePath).Path
    $base = Import-PowerShellDataFile -LiteralPath $resolvedBasePath
    if (-not $base.Servers -or $base.Servers.Count -eq 0) {
        throw "No servers are defined in: $resolvedBasePath"
    }

    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        $LocalPath = Join-Path (Split-Path -Parent $resolvedBasePath) 'servers.local.psd1'
    }

    $effective = @{
        Common  = @{}
        Servers = @{}
    }

    if ($base.Common) {
        foreach ($key in $base.Common.Keys) {
            $effective.Common[[string]$key] = $base.Common[$key]
        }
    }

    foreach ($serverKey in $base.Servers.Keys) {
        $server = $base.Servers[$serverKey]
        $serverCopy = @{}
        foreach ($key in $server.Keys) {
            if ([string]$key -eq 'Settings') {
                $serverCopy.Settings = Copy-ServerSettings $server.Settings
            } else {
                $serverCopy[[string]$key] = $server[$key]
            }
        }
        $effective.Servers[[string]$serverKey] = $serverCopy
    }

    if (Test-Path -LiteralPath $LocalPath -PathType Leaf) {
        $resolvedLocalPath = (Resolve-Path -LiteralPath $LocalPath).Path
        $local = Import-PowerShellDataFile -LiteralPath $resolvedLocalPath

        if ($local.Common) {
            foreach ($key in $local.Common.Keys) {
                $keyText = [string]$key
                if (-not $base.Common.ContainsKey($keyText)) {
                    throw "Local Common override contains unknown setting '$keyText': $resolvedLocalPath"
                }
                $effective.Common[$keyText] = $local.Common[$key]
            }
        }

        if ($local.Servers) {
            foreach ($serverKey in $local.Servers.Keys) {
                $keyText = [string]$serverKey
                if (-not $effective.Servers.ContainsKey($keyText)) {
                    throw "Local server config contains unknown server '$keyText': $resolvedLocalPath"
                }

                $serverOverlay = $local.Servers[$serverKey]
                if (-not ($serverOverlay -is [System.Collections.IDictionary])) {
                    throw "Local server override for '$keyText' must be a hashtable: $resolvedLocalPath"
                }

                $target = $effective.Servers[$keyText]
                foreach ($key in $serverOverlay.Keys) {
                    if ([string]$key -eq 'Settings') {
                        if (-not $target.Settings) {
                            $target.Settings = @{}
                        }
                        foreach ($settingKey in $serverOverlay.Settings.Keys) {
                            $settingText = [string]$settingKey
                            if (-not $base.Servers[$serverKey].Settings.ContainsKey($settingText)) {
                                throw "Local Settings override contains unknown setting '$settingText' for server '$keyText': $resolvedLocalPath"
                            }
                            $target.Settings[$settingText] = $serverOverlay.Settings[$settingKey]
                        }
                    } else {
                        $keyText = [string]$key
                        if (-not $base.Servers[$serverKey].ContainsKey($keyText)) {
                            throw "Local server override contains unknown field '$keyText' for server '$keyText': $resolvedLocalPath"
                        }
                        $target[$keyText] = $serverOverlay[$key]
                    }
                }
            }
        }
    }

    return $effective
}

Export-ModuleMember -Function Import-VaspServerConfig

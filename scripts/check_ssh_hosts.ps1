[CmdletBinding()]
param(
    [string]$Server = 'all',

    [string]$ServerConfigPath = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\config\servers.local.psd1')) { Join-Path $PSScriptRoot '..\config\servers.local.psd1' } else { Join-Path $PSScriptRoot '..\config\servers.psd1' }),

    [switch]$SkipConnectionTest
)

$ErrorActionPreference = 'Stop'

function Resolve-IdentityPath {
    param([Parameter(Mandatory)][string]$Path)

    $expanded = $Path.Trim()
    if ($expanded -eq '~') {
        $expanded = $HOME
    } elseif ($expanded.StartsWith('~/') -or $expanded.StartsWith('~\')) {
        $expanded = Join-Path $HOME $expanded.Substring(2)
    }
    $expanded = $expanded.Replace('%d', $HOME).Replace('%u', $env:USERNAME)
    if ($expanded.Contains('%')) {
        return $null
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expanded)
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client ssh.exe was not found.'
}
if (-not (Test-Path -LiteralPath $ServerConfigPath -PathType Leaf)) {
    throw "Server config file does not exist: $ServerConfigPath"
}

$config = Import-PowerShellDataFile -LiteralPath $ServerConfigPath
$serverKeys = if ($Server -ieq 'all') {
    @($config.Servers.Keys | Sort-Object)
} else {
    @(
        $config.Servers.Keys | Where-Object {
            $_ -ieq $Server -or [string]$config.Servers[$_].SshAlias -ieq $Server
        }
    )
}

if ($serverKeys.Count -eq 0) {
    $available = @(
        $config.Servers.Keys | Sort-Object | ForEach-Object {
            "$_ ($($config.Servers[$_].SshAlias))"
        }
    ) -join ', '
    throw "Unknown server '$Server'. Available servers: all, $available"
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($serverKey in $serverKeys) {
    $serverConfig = $config.Servers[$serverKey]
    $sshAlias = [string]$serverConfig.SshAlias
    $expectedHost = [string]$serverConfig.HostName
    $messages = [System.Collections.Generic.List[string]]::new()

    $resolvedOutput = & ssh -G $sshAlias 2>$null
    $configResolved = $LASTEXITCODE -eq 0
    $resolvedUser = ''
    $resolvedHost = ''
    $resolvedPort = ''
    $identityPaths = @()

    if ($configResolved) {
        $userLine = ($resolvedOutput | Select-String '^user ' | Select-Object -First 1).Line
        $hostLine = ($resolvedOutput | Select-String '^hostname ' | Select-Object -First 1).Line
        $portLine = ($resolvedOutput | Select-String '^port ' | Select-Object -First 1).Line
        $resolvedUser = if ($userLine) { ($userLine -split ' ', 2)[1] } else { '' }
        $resolvedHost = if ($hostLine) { ($hostLine -split ' ', 2)[1] } else { '' }
        $resolvedPort = if ($portLine) { ($portLine -split ' ', 2)[1] } else { '' }
        $identityPaths = @(
            $resolvedOutput | Select-String '^identityfile ' | ForEach-Object {
                Resolve-IdentityPath (($_.Line -split ' ', 2)[1])
            } | Where-Object { $_ }
        )
    } else {
        $messages.Add('ssh -G could not resolve this alias.')
    }

    $hostMatches = $configResolved -and $resolvedHost -ieq $expectedHost
    if ($configResolved -and -not $hostMatches) {
        $messages.Add("Resolved host '$resolvedHost' does not match expected host '$expectedHost'.")
    }
    if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
        $messages.Add('No remote username was resolved.')
    }

    $existingIdentity = $identityPaths | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
    $identityExists = -not [string]::IsNullOrWhiteSpace([string]$existingIdentity)
    if (-not $identityExists) {
        $messages.Add('No resolved private key file exists locally.')
    }

    $batchLogin = $null
    if (-not $SkipConnectionTest -and $configResolved -and $hostMatches -and $identityExists) {
        $batchOutput = & ssh -o BatchMode=yes -o ConnectTimeout=10 $sshAlias 'printf CODEX_SSH_READY' 2>&1
        $batchLogin = $LASTEXITCODE -eq 0 -and (($batchOutput -join '') -match 'CODEX_SSH_READY')
        if (-not $batchLogin) {
            $messages.Add('Batch-mode login failed. Check authorized_keys, key passphrase, or ssh-agent.')
        }
    }

    $status = if (
        $configResolved -and
        $hostMatches -and
        -not [string]::IsNullOrWhiteSpace($resolvedUser) -and
        $identityExists -and
        ($SkipConnectionTest -or $batchLogin)
    ) { 'PASS' } else { 'FAIL' }

    $results.Add([pscustomobject]@{
        Server       = [string]$serverKey
        SshAlias     = $sshAlias
        HostName     = $resolvedHost
        RemoteUser   = $resolvedUser
        Port         = $resolvedPort
        IdentityFile = [string]$existingIdentity
        BatchLogin   = $batchLogin
        Status       = $status
        Message      = ($messages -join ' ')
    })
}

$results

if (@($results | Where-Object Status -ne 'PASS').Count -gt 0) {
    throw 'One or more SSH host checks failed. Run setup_ssh_hosts.ps1 for the affected server.'
}

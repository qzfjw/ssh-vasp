[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [string]$RemoteUser,

    [string]$IdentityFile,

    [string]$SshConfigPath = (Join-Path $HOME '.ssh\config'),

    [string]$ServerConfigPath = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\config\servers.local.psd1')) { Join-Path $PSScriptRoot '..\config\servers.local.psd1' } else { Join-Path $PSScriptRoot '..\config\servers.psd1' }),

    [switch]$GenerateKey,

    [switch]$NoPassphrase,

    [switch]$SkipKeyInstall,

    [switch]$SkipConnectionTest,

    [switch]$ForceAdoptExisting,

    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

function Read-YesNo {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [bool]$DefaultYes = $true
    )

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Prompt $suffix").Trim()
        if (-not $answer) {
            return $DefaultYes
        }
        if ($answer -match '^(?i:y|yes)$') {
            return $true
        }
        if ($answer -match '^(?i:n|no)$') {
            return $false
        }
    }
}

function Resolve-UserPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -eq '~') {
        $Path = $HOME
    } elseif ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $Path = Join-Path $HOME $Path.Substring(2)
    }
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function ConvertTo-SshPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $homePath = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\')
    if ($fullPath.StartsWith($homePath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '~/' + $fullPath.Substring($homePath.Length + 1).Replace('\', '/')
    }
    return $fullPath.Replace('\', '/')
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client ssh.exe was not found.'
}
if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw 'OpenSSH client ssh-keygen.exe was not found.'
}
if (-not (Test-Path -LiteralPath $ServerConfigPath -PathType Leaf)) {
    throw "Server config file does not exist: $ServerConfigPath"
}

$serverConfigData = Import-PowerShellDataFile -LiteralPath $ServerConfigPath
$matchingKeys = @(
    $serverConfigData.Servers.Keys | Where-Object {
        $_ -ieq $Server -or [string]$serverConfigData.Servers[$_].SshAlias -ieq $Server
    }
)
if ($matchingKeys.Count -ne 1) {
    $available = @(
        $serverConfigData.Servers.Keys | Sort-Object | ForEach-Object {
            "$_ ($($serverConfigData.Servers[$_].SshAlias))"
        }
    ) -join ', '
    throw "Unknown server '$Server'. Available servers: $available"
}

$serverKey = [string]$matchingKeys[0]
$serverConfig = $serverConfigData.Servers[$serverKey]
$sshAlias = [string]$serverConfig.SshAlias
$hostName = [string]$serverConfig.HostName
$port = [int]$serverConfig.Port

if ([string]::IsNullOrWhiteSpace($hostName) -or $port -le 0) {
    throw "HostName or Port is missing for server '$serverKey'."
}

if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
    if ($NonInteractive) {
        throw 'RemoteUser is required in non-interactive mode.'
    }
    $RemoteUser = (Read-Host "Remote username for $($serverConfig.DisplayName) ($sshAlias)").Trim()
}
if ([string]::IsNullOrWhiteSpace($RemoteUser) -or $RemoteUser -match '[\s\r\n]') {
    throw 'RemoteUser must not be empty or contain whitespace.'
}

$sshDirectory = Split-Path -Parent (Resolve-UserPath $SshConfigPath)
if (-not (Test-Path -LiteralPath $sshDirectory)) {
    New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($IdentityFile)) {
    $IdentityFile = Join-Path $sshDirectory "id_ed25519_$serverKey"
}
$identityFullPath = Resolve-UserPath $IdentityFile
$publicKeyPath = "$identityFullPath.pub"

if (-not (Test-Path -LiteralPath $identityFullPath -PathType Leaf)) {
    $shouldGenerate = $GenerateKey
    if (-not $GenerateKey -and -not $NonInteractive) {
        $shouldGenerate = Read-YesNo -Prompt "SSH key does not exist at $identityFullPath. Generate an ED25519 key?"
    }
    if (-not $shouldGenerate) {
        if ($NonInteractive) {
            throw "SSH private key does not exist: $identityFullPath"
        }
        $identityFullPath = Resolve-UserPath (Read-Host 'Path to an existing SSH private key')
        $publicKeyPath = "$identityFullPath.pub"
        if (-not (Test-Path -LiteralPath $identityFullPath -PathType Leaf)) {
            throw "SSH private key does not exist: $identityFullPath"
        }
    } else {
        $identityDirectory = Split-Path -Parent $identityFullPath
        if (-not (Test-Path -LiteralPath $identityDirectory)) {
            New-Item -ItemType Directory -Path $identityDirectory -Force | Out-Null
        }
        $keyArguments = @('-t', 'ed25519', '-f', $identityFullPath, '-C', "codex-vasp-$serverKey@$env:USERNAME")
        if ($NoPassphrase) {
            $keyArguments += @('-N', '')
        }
        & ssh-keygen @keyArguments
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $identityFullPath)) {
            throw "ssh-keygen failed for: $identityFullPath"
        }
    }
}

if (-not (Test-Path -LiteralPath $publicKeyPath -PathType Leaf)) {
    $publicKey = & ssh-keygen -y -f $identityFullPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($publicKey -join ''))) {
        throw "Unable to derive public key from: $identityFullPath"
    }
    [System.IO.File]::WriteAllText(
        $publicKeyPath,
        (($publicKey -join '').Trim() + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

$publicKeyLine = ([System.IO.File]::ReadAllText($publicKeyPath, [System.Text.Encoding]::UTF8)).Trim()
if ($publicKeyLine -notmatch '^(ssh-|ecdsa-)') {
    throw "Public key file does not contain a recognized OpenSSH public key: $publicKeyPath"
}

if (-not $SkipKeyInstall) {
    $shouldInstall = $true
    if (-not $NonInteractive) {
        $shouldInstall = Read-YesNo -Prompt "Install this public key on $RemoteUser@$hostName now?"
    }
    if ($shouldInstall) {
        $remoteCommand = 'umask 077; mkdir -p "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; IFS= read -r key; grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$key" >> "$HOME/.ssh/authorized_keys"; chmod 700 "$HOME/.ssh"; chmod 600 "$HOME/.ssh/authorized_keys"'
        $publicKeyLine | & ssh -o ConnectTimeout=10 -p $port "$RemoteUser@$hostName" $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Public key installation failed for $RemoteUser@$hostName."
        }
    }
}

$resolvedSshConfigPath = Resolve-UserPath $SshConfigPath
$existingConfig = if (Test-Path -LiteralPath $resolvedSshConfigPath) {
    [System.IO.File]::ReadAllText($resolvedSshConfigPath, [System.Text.Encoding]::UTF8)
} else {
    ''
}
$normalizedConfig = $existingConfig.Replace("`r`n", "`n").Replace("`r", "`n")

$beginMarker = "# BEGIN CODEX VASP: $sshAlias"
$endMarker = "# END CODEX VASP: $sshAlias"
$managedPattern = '(?ms)^' + [regex]::Escape($beginMarker) + '$.*?^' + [regex]::Escape($endMarker) + '$\n?'
$normalizedConfig = [regex]::Replace($normalizedConfig, $managedPattern, '')

$unmanagedPattern = '(?ms)^[ \t]*Host[ \t]+' + [regex]::Escape($sshAlias) + '[ \t]*$.*?(?=^[ \t]*(?:Host|Match)\b|\z)'
$unmanagedMatch = [regex]::Match($normalizedConfig, $unmanagedPattern)
if ($unmanagedMatch.Success) {
    $adoptExisting = $ForceAdoptExisting
    if (-not $ForceAdoptExisting -and -not $NonInteractive) {
        $adoptExisting = Read-YesNo -Prompt "An unmanaged 'Host $sshAlias' block already exists. Replace it with a managed block?"
    }
    if (-not $adoptExisting) {
        throw "Existing unmanaged Host block was not changed: $sshAlias"
    }
    $normalizedConfig = $normalizedConfig.Remove($unmanagedMatch.Index, $unmanagedMatch.Length)
}

$identitySshPath = ConvertTo-SshPath $identityFullPath
$managedBlock = @"
$beginMarker
Host $sshAlias
    HostName $hostName
    User $RemoteUser
    Port $port
    IdentityFile $identitySshPath
    IdentitiesOnly yes
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3
$endMarker
"@

if (Test-Path -LiteralPath $resolvedSshConfigPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $backupPath = "$resolvedSshConfigPath.codex-backup-$timestamp"
    Copy-Item -LiteralPath $resolvedSshConfigPath -Destination $backupPath -Force
    Write-Output "SSH config backup: $backupPath"
}

$newConfig = $normalizedConfig.Trim() + "`n`n" + $managedBlock.Trim() + "`n"
[System.IO.File]::WriteAllText(
    $resolvedSshConfigPath,
    $newConfig,
    [System.Text.UTF8Encoding]::new($false)
)

$resolvedOutput = & ssh -F $resolvedSshConfigPath -G $sshAlias 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "ssh -G failed for alias: $sshAlias"
}

$resolvedUser = (($resolvedOutput | Select-String '^user ' | Select-Object -First 1).Line -split ' ', 2)[1]
$resolvedHost = (($resolvedOutput | Select-String '^hostname ' | Select-Object -First 1).Line -split ' ', 2)[1]
if ($resolvedUser -ne $RemoteUser -or $resolvedHost -ne $hostName) {
    throw "SSH config resolution mismatch for ${sshAlias}: user=$resolvedUser host=$resolvedHost"
}

$batchLogin = $null
if (-not $SkipConnectionTest) {
    $batchOutput = & ssh -F $resolvedSshConfigPath -o BatchMode=yes -o ConnectTimeout=10 $sshAlias 'printf CODEX_SSH_READY' 2>&1
    $batchLogin = $LASTEXITCODE -eq 0 -and (($batchOutput -join '') -match 'CODEX_SSH_READY')
    if (-not $batchLogin) {
        throw "Batch-mode login failed for $sshAlias. If the key has a passphrase, add it to ssh-agent, or verify authorized_keys."
    }
}

[pscustomobject]@{
    Server        = $serverKey
    SshAlias      = $sshAlias
    HostName      = $hostName
    RemoteUser    = $RemoteUser
    IdentityFile  = $identityFullPath
    SshConfigPath = $resolvedSshConfigPath
    BatchLogin    = $batchLogin
}

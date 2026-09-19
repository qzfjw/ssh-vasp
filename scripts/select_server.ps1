[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\servers.psd1'),

    [string]$LocalConfigPath = (Join-Path $PSScriptRoot '..\config\servers.local.psd1')
)

$ErrorActionPreference = 'Stop'

$serverConfigModule = Join-Path $PSScriptRoot 'lib\ServerConfig.psm1'
Import-Module $serverConfigModule -Force
$config = Import-VaspServerConfig -BasePath $ConfigPath -LocalPath $LocalConfigPath

$matchingKeys = @(
    $config.Servers.Keys | Where-Object {
        $_ -ieq $Server -or [string]$config.Servers[$_].SshAlias -ieq $Server
    }
)

if ($matchingKeys.Count -ne 1) {
    $available = @(
        $config.Servers.Keys | Sort-Object | ForEach-Object {
            "$_ ($($config.Servers[$_].SshAlias))"
        }
    ) -join ', '
    throw "Unknown server '$Server'. Available servers: $available"
}

$serverKey = [string]$matchingKeys[0]
$serverConfig = $config.Servers[$serverKey]

if ([string]::IsNullOrWhiteSpace([string]$serverConfig.SshAlias)) {
    throw "SshAlias is missing for server '$serverKey'."
}

$effectiveSettings = @{}
foreach ($key in $config.Common.Keys) {
    $effectiveSettings[$key] = $config.Common[$key]
}
if ($serverConfig.Settings) {
    foreach ($key in $serverConfig.Settings.Keys) {
        $effectiveSettings[$key] = $serverConfig.Settings[$key]
    }
}

$requiredSettings = @(
    'WorkRoot',
    'SlurmBin',
    'VaspBin',
    'OneApiSetup',
    'Partition',
    'MpiLauncher',
    'PawPotentialRoot',
    'VaspExecutable'
)
foreach ($settingName in $requiredSettings) {
    if ([string]::IsNullOrWhiteSpace([string]$effectiveSettings[$settingName])) {
        throw "Setting '$settingName' is missing for server '$serverKey'."
    }
}

if ([string]$effectiveSettings.WorkRoot -notmatch '^[A-Za-z0-9._/-]+$' -or
    [string]$effectiveSettings.WorkRoot -match '(^|/)\.\.(/|$)' -or
    [string]$effectiveSettings.WorkRoot -match '^/') {
    throw "WorkRoot must be a safe relative path without parent-directory components."
}

foreach ($settingName in @('SlurmBin', 'VaspBin', 'OneApiSetup', 'MpiLauncher', 'PawPotentialRoot')) {
    if ([string]$effectiveSettings[$settingName] -notmatch '^[A-Za-z0-9._/@:+-]+$') {
        throw "Setting '$settingName' contains characters unsafe for shell templates."
    }
}

if ([string]$effectiveSettings.Partition -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Partition contains characters unsafe for SLURM submission: $($effectiveSettings.Partition)"
}

if ([string]$effectiveSettings.VaspExecutable -notmatch '^(vasp_std|vasp_gam|vasp_ncl)$') {
    throw "VaspExecutable must be vasp_std, vasp_gam, or vasp_ncl."
}

$env:VASP_SERVER_KEY = $serverKey
$env:VASP_SERVER_NAME = [string]$serverConfig.DisplayName
$env:VASP_SSH_ALIAS = [string]$serverConfig.SshAlias
$env:VASP_WORK_ROOT = [string]$effectiveSettings.WorkRoot
$env:VASP_SLURM_BIN = [string]$effectiveSettings.SlurmBin
$env:VASP_VASP_BIN = [string]$effectiveSettings.VaspBin
$env:VASP_ONEAPI_SETUP = [string]$effectiveSettings.OneApiSetup
$env:VASP_PARTITION = [string]$effectiveSettings.Partition
$env:VASP_MPI_LAUNCHER = [string]$effectiveSettings.MpiLauncher
$env:VASP_PAW_POTENTIAL_ROOT = [string]$effectiveSettings.PawPotentialRoot
$env:VASP_EXECUTABLE = [string]$effectiveSettings.VaspExecutable
$env:VASP_MEMORY_PER_CPU = [string]$effectiveSettings.MemoryPerCpu

[pscustomobject]@{
    ServerKey  = $env:VASP_SERVER_KEY
    ServerName = $env:VASP_SERVER_NAME
    SshAlias   = $env:VASP_SSH_ALIAS
    WorkRoot   = "~/$($env:VASP_WORK_ROOT)"
    SlurmBin   = $env:VASP_SLURM_BIN
    VaspBin    = $env:VASP_VASP_BIN
    OneApi     = $env:VASP_ONEAPI_SETUP
    Partition  = $env:VASP_PARTITION
    MpiLauncher = $env:VASP_MPI_LAUNCHER
    PawPotentialRoot = $env:VASP_PAW_POTENTIAL_ROOT
    Executable = $env:VASP_EXECUTABLE
    MemoryPerCpu = $env:VASP_MEMORY_PER_CPU
}

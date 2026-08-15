[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [string[]]$JobName,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [string]$RulesPath = (Join-Path $PSScriptRoot '..\config\rules\artifact-rules.psd1'),

    [string]$RulesOverridePath = '',

    [switch]$IncludeLargeFiles,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force
$artifactRules = Import-VaspRuleSet -BasePath $RulesPath -OverridePath $RulesOverridePath -RequiredKeys @('Download')
$essentialNames = @($artifactRules.Download.EssentialFiles | ForEach-Object { [string]$_ })
$additionalNameRegex = [string]$artifactRules.Download.AdditionalNameRegex
if ([string]::IsNullOrWhiteSpace($additionalNameRegex)) {
    throw 'Artifact rules must define Download.AdditionalNameRegex.'
}

function Invoke-RemoteBash {
    param([string]$SshAlias, [string]$Script)
    $normalized = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $output = @(& ssh -o BatchMode=yes $SshAlias "echo $encoded | base64 -d | bash" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Remote result query failed on ${SshAlias}:`n$($output -join "`n")"
    }
    return $output
}

foreach ($name in $JobName) {
    if ($name -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid job name: $name"
    }
}

$selectServer = Join-Path $PSScriptRoot 'select_server.ps1'
$checkSsh = Join-Path $PSScriptRoot 'check_ssh_hosts.ps1'
& $selectServer -Server $Server | Out-Host
& $checkSsh -Server $env:VASP_SERVER_KEY | Out-Host

$quotedNames = $JobName | ForEach-Object { "'$_'" }
$queryScript = @'
set -euo pipefail
work_root="$HOME/__WORK_ROOT__"
for name in __JOB_NAMES__; do
    dir="$work_root/$name"
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: remote job directory does not exist: $dir" >&2
        exit 4
    fi
    echo "BEGIN_JOB=$name"
    find "$dir" -maxdepth 1 -type f -printf '%f|%s\n' | sort
    echo "END_JOB=$name"
done
'@.Replace('__WORK_ROOT__', $env:VASP_WORK_ROOT).Replace('__JOB_NAMES__', ($quotedNames -join ' '))
$listing = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $queryScript

$remoteFiles = @{}
$currentJob = $null
foreach ($line in $listing) {
    if ($line -match '^BEGIN_JOB=(.+)$') {
        $currentJob = $matches[1]
        $remoteFiles[$currentJob] = @()
        continue
    }
    if ($line -match '^END_JOB=') {
        $currentJob = $null
        continue
    }
    if ($currentJob -and $line -match '^(?<name>[^|]+)\|(?<size>\d+)$') {
        $remoteFiles[$currentJob] += [pscustomobject]@{
            Name = $matches.name
            Size = [int64]$matches.size
        }
    }
}

$selection = @{}
foreach ($name in $JobName) {
    $files = @($remoteFiles[$name])
    if ($files.Count -eq 0) {
        throw "No remote files were listed for job: $name"
    }
    if ($IncludeLargeFiles) {
        $selected = $files
    } else {
        $selected = @($files | Where-Object {
            $_.Name -in $essentialNames -or $_.Name -match $additionalNameRegex
        })
    }
    $selection[$name] = $selected
}

foreach ($name in $JobName) {
    $totalBytes = ($selection[$name] | Measure-Object -Property Size -Sum).Sum
    [pscustomobject]@{
        JobName = $name
        FileCount = $selection[$name].Count
        SizeMB = [math]::Round($totalBytes / 1MB, 2)
        IncludeLargeFiles = [bool]$IncludeLargeFiles
    } | Out-Host
}

if ($DryRun) {
    Write-Output 'Dry run: remote files were inspected; nothing was downloaded.'
    return
}

$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if (Test-Path -LiteralPath $outputPath) {
    throw "Output directory already exists: $outputPath"
}
New-Item -ItemType Directory -Path $outputPath | Out-Null

$downloaded = @()
foreach ($name in $JobName) {
    $jobOutput = Join-Path $outputPath $name
    New-Item -ItemType Directory -Path $jobOutput | Out-Null
    foreach ($file in $selection[$name]) {
        $remoteSource = "$($env:VASP_SSH_ALIAS):~/$($env:VASP_WORK_ROOT)/$name/$($file.Name)"
        & scp -q $remoteSource $jobOutput
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download $name/$($file.Name). Existing downloaded files were preserved."
        }
        $downloaded += Join-Path $jobOutput $file.Name
    }
}

[pscustomobject]@{
    Server = $env:VASP_SERVER_KEY
    SshAlias = $env:VASP_SSH_ALIAS
    OutputDirectory = $outputPath
    DownloadedFileCount = $downloaded.Count
}

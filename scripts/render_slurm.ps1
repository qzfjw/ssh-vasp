[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$JobName,

    [Parameter(Mandatory)]
    [ValidateRange(1, 4096)]
    [int]$Cores,

    [Parameter(Mandatory)]
    [string]$Walltime,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Partition = 'cluster',

    [string]$SlurmBin = '/opt/slurm/bin',

    [string]$VaspBin = '/home/public/vasp.6.5.1/bin',

    [string]$OneApiSetup = '/home/public/oneapi/setvars.sh',

    [string]$MpiLauncher = '/home/public/oneapi/mpi/2021.12/bin/mpiexec',

    [ValidateSet('vasp_std', 'vasp_gam', 'vasp_ncl')]
    [string]$VaspExecutable = 'vasp_std',

    [AllowEmptyString()]
    [string]$MemoryPerCpu = '',

    [string]$OutputPath = 'run_vasp.slurm',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($JobName -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'JobName may contain only letters, digits, dot, underscore, and hyphen.'
}

if ($Walltime -notmatch '^(?:\d+-)?\d{1,3}:[0-5]\d:[0-5]\d$') {
    throw 'Walltime must use SLURM format HH:MM:SS or D-HH:MM:SS.'
}

foreach ($pathSetting in @{
    SlurmBin = $SlurmBin
    VaspBin = $VaspBin
    OneApiSetup = $OneApiSetup
    MpiLauncher = $MpiLauncher
}.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$pathSetting.Value)) {
        throw "$($pathSetting.Key) must not be empty."
    }
    if ([string]$pathSetting.Value -match '[\r\n"]') {
        throw "$($pathSetting.Key) contains unsupported characters."
    }
}

if ($MemoryPerCpu -and $MemoryPerCpu -notmatch '^\d+(?:\.\d+)?[KMGTP]?$') {
    throw 'MemoryPerCpu must be empty or use a SLURM value such as 7G or 8000M.'
}

$templatePath = Join-Path $PSScriptRoot '..\assets\run_vasp.slurm.tmpl'
$resolvedTemplatePath = (Resolve-Path -LiteralPath $templatePath).Path
$outputFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

if ((Test-Path -LiteralPath $outputFullPath) -and -not $Force) {
    throw "Output file already exists: $outputFullPath. Use -Force to replace it."
}

$outputDirectory = Split-Path -Parent $outputFullPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$content = [System.IO.File]::ReadAllText($resolvedTemplatePath)
$replacements = [ordered]@{
    '{{JOB_NAME}}'        = $JobName
    '{{CORES}}'           = [string]$Cores
    '{{PARTITION}}'       = $Partition
    '{{WALLTIME}}'        = $Walltime
    '{{SLURM_BIN}}'       = $SlurmBin
    '{{VASP_BIN}}'        = $VaspBin
    '{{ONEAPI_SETUP}}'    = $OneApiSetup
    '{{MPI_LAUNCHER}}'    = $MpiLauncher
    '{{VASP_EXECUTABLE}}' = $VaspExecutable
    '{{MEMORY_DIRECTIVE}}' = if ($MemoryPerCpu) { "#SBATCH --mem-per-cpu=$MemoryPerCpu" } else { '' }
}

foreach ($entry in $replacements.GetEnumerator()) {
    $content = $content.Replace($entry.Key, $entry.Value)
}

if ($content -match '\{\{[A-Z_]+\}\}') {
    throw 'The rendered SLURM script still contains unresolved template variables.'
}

$content = $content.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputFullPath, $content, $utf8WithoutBom)

Get-Item -LiteralPath $outputFullPath | Select-Object FullName, Length, LastWriteTime

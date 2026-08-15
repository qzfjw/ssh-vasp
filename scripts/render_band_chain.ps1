[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RootDirectory,

    [Parameter(Mandatory)]
    [string]$RelaxJobName,

    [Parameter(Mandatory)]
    [string]$ScfJobName,

    [Parameter(Mandatory)]
    [string]$BandJobName,

    [string]$WorkflowRulesPath = (Join-Path $PSScriptRoot '..\config\rules\workflow-rules.psd1'),

    [string]$WorkflowRulesOverridePath = '',

    [string]$InputRulesPath = (Join-Path $PSScriptRoot '..\config\rules\input-rules.psd1'),

    [string]$InputRulesOverridePath = '',

    [ValidateRange(0, 4096)]
    [int]$Cores = 0,

    [string]$RelaxWalltime = '',

    [string]$ScfWalltime = '',

    [string]$BandWalltime = '',

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Partition = 'cluster',

    [string]$WorkRoot = 'vasp_codex',

    [string]$SlurmBin = '/opt/slurm/bin',

    [string]$VaspBin = '/home/public/vasp.6.5.1/bin',

    [string]$OneApiSetup = '/home/public/oneapi/setvars.sh',

    [string]$MpiLauncher = '/home/public/oneapi/mpi/2021.12/bin/mpiexec',

    [ValidateSet('vasp_std', 'vasp_gam', 'vasp_ncl')]
    [string]$VaspExecutable = 'vasp_std',

    [AllowEmptyString()]
    [string]$MemoryPerCpu = '',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force
$workflowRules = Import-VaspRuleSet -BasePath $WorkflowRulesPath -OverridePath $WorkflowRulesOverridePath -RequiredKeys @('Defaults', 'Stages', 'PreparationGates', 'Submission')

function Assert-SafeGateText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value, [Parameter(Mandatory)][string]$Label)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Label must not be empty."
    }
    if ($Value -match "['\r\n]") {
        throw "$Label contains unsupported quote or newline characters."
    }
}

function New-PreparationScript {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Gate,
        [Parameter(Mandatory)][string]$SourceJobName,
        [Parameter(Mandatory)][string]$WorkRoot
    )

    $requiredConditions = foreach ($fileName in @($Gate.RequiredNonEmptyFiles)) {
        Assert-SafeGateText -Value ([string]$fileName) -Label 'Required gate file'
        '[[ ! -s "$source_dir/__FILE__" ]]'.Replace('__FILE__', [string]$fileName)
    }
    Assert-SafeGateText -Value ([string]$Gate.MissingFilesMessage) -Label 'Missing-files message'

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('#!/bin/bash')
    $lines.Add('set -euo pipefail')
    $lines.Add('')
    $lines.Add(('source_dir="$HOME/__WORK_ROOT__/__SOURCE_JOB__"').Replace('__WORK_ROOT__', $WorkRoot).Replace('__SOURCE_JOB__', $SourceJobName))
    $lines.Add(('if __CONDITIONS__; then').Replace('__CONDITIONS__', ($requiredConditions -join ' || ')))
    $lines.Add(('    echo "ERROR: __MESSAGE__" >&2').Replace('__MESSAGE__', [string]$Gate.MissingFilesMessage))
    $lines.Add('    exit 3')
    $lines.Add('fi')

    $requiredTextChecks = if ($Gate.Contains('RequiredTextChecks')) { @($Gate.RequiredTextChecks) } else { @() }
    foreach ($check in $requiredTextChecks) {
        Assert-SafeGateText -Value ([string]$check.Pattern) -Label 'Required gate pattern'
        Assert-SafeGateText -Value ([string]$check.File) -Label 'Required gate file'
        Assert-SafeGateText -Value ([string]$check.Message) -Label 'Required gate message'
        $grepOption = if ([string]$check.MatchMode -eq 'Regex') { '-Eq' } else { '-Fq' }
        $lines.Add(('if ! grep __OPTION__ ''__PATTERN__'' "$source_dir/__FILE__"; then').Replace('__OPTION__', $grepOption).Replace('__PATTERN__', [string]$check.Pattern).Replace('__FILE__', [string]$check.File))
        $lines.Add(('    echo "ERROR: __MESSAGE__" >&2').Replace('__MESSAGE__', [string]$check.Message))
        $lines.Add('    exit 3')
        $lines.Add('fi')
    }

    $forbiddenRegexChecks = if ($Gate.Contains('ForbiddenRegexChecks')) { @($Gate.ForbiddenRegexChecks) } else { @() }
    foreach ($check in $forbiddenRegexChecks) {
        Assert-SafeGateText -Value ([string]$check.Pattern) -Label 'Forbidden gate pattern'
        Assert-SafeGateText -Value ([string]$check.Message) -Label 'Forbidden gate message'
        $fileArguments = foreach ($fileName in @($check.Files)) {
            Assert-SafeGateText -Value ([string]$fileName) -Label 'Forbidden gate file'
            if ([string]$fileName -match '[*?]') {
                '"$source_dir"/__FILE__'.Replace('__FILE__', [string]$fileName)
            } else {
                '"$source_dir/__FILE__"'.Replace('__FILE__', [string]$fileName)
            }
        }
        $lines.Add(('if grep -Eqi ''__PATTERN__'' __FILES__ 2>/dev/null; then').Replace('__PATTERN__', [string]$check.Pattern).Replace('__FILES__', ($fileArguments -join ' ')))
        $lines.Add(('    echo "ERROR: __MESSAGE__" >&2').Replace('__MESSAGE__', [string]$check.Message))
        $lines.Add('    exit 3')
        $lines.Add('fi')
    }

    $copyFiles = if ($Gate.Contains('CopyFiles')) { @($Gate.CopyFiles) } else { @() }
    foreach ($copyRule in $copyFiles) {
        Assert-SafeGateText -Value ([string]$copyRule.Source) -Label 'Gate copy source'
        Assert-SafeGateText -Value ([string]$copyRule.Destination) -Label 'Gate copy destination'
        $lines.Add(('cp "$source_dir/__SOURCE__" ''__DESTINATION__''').Replace('__SOURCE__', [string]$copyRule.Source).Replace('__DESTINATION__', [string]$copyRule.Destination))
    }

    return ($lines -join [string][char]10) + [string][char]10
}

if ($Cores -eq 0) {
    $Cores = [int]$workflowRules.Defaults.Cores
}

foreach ($jobName in @($RelaxJobName, $ScfJobName, $BandJobName)) {
    if ($jobName -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid job name: $jobName"
    }
}

if ($WorkRoot -notmatch '^[A-Za-z0-9._/-]+$' -or $WorkRoot -match '(^|/)\.\.(/|$)' -or $WorkRoot.StartsWith('/')) {
    throw 'WorkRoot must be a safe relative path without parent-directory components.'
}

$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RootDirectory)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Root directory does not exist: $root"
}

$jobNames = @{ relax=$RelaxJobName; scf=$ScfJobName; band=$BandJobName }
$walltimes = @{ relax=$RelaxWalltime; scf=$ScfWalltime; band=$BandWalltime }
$stageDefinitions = foreach ($stageRule in @($workflowRules.Stages)) {
    $stageName = [string]$stageRule.Name
    if (-not $jobNames.ContainsKey($stageName)) {
        throw "Unsupported workflow stage in rules: $stageName"
    }
    $walltime = [string]$walltimes[$stageName]
    if ([string]::IsNullOrWhiteSpace($walltime)) {
        $walltime = [string]$stageRule.DefaultWalltime
    }
    [ordered]@{
        Name = $stageName
        JobName = [string]$jobNames[$stageName]
        Walltime = $walltime
        CalculationType = [string]$stageRule.CalculationType
        DependsOn = [string]$stageRule.DependsOn
    }
}

foreach ($stage in $stageDefinitions) {
    $stage.Directory = Join-Path $root $stage.Name
    if (-not (Test-Path -LiteralPath $stage.Directory -PathType Container)) {
        throw "Stage directory does not exist: $($stage.Directory)"
    }
    foreach ($fileName in @($workflowRules.Defaults.RequiredInputFiles)) {
        $filePath = Join-Path $stage.Directory $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf) -or (Get-Item -LiteralPath $filePath).Length -eq 0) {
            throw "Missing or empty $fileName in stage directory: $($stage.Directory)"
        }
    }
}

$renderSlurm = Join-Path $PSScriptRoot 'render_slurm.ps1'
$preflight = Join-Path $PSScriptRoot 'preflight_job.ps1'

foreach ($stage in $stageDefinitions) {
    $outputPath = Join-Path $stage.Directory 'run_vasp.slurm'
    & $renderSlurm `
        -JobName $stage.JobName `
        -Cores $Cores `
        -Walltime $stage.Walltime `
        -Partition $Partition `
        -SlurmBin $SlurmBin `
        -VaspBin $VaspBin `
        -OneApiSetup $OneApiSetup `
        -MpiLauncher $MpiLauncher `
        -VaspExecutable $VaspExecutable `
        -MemoryPerCpu $MemoryPerCpu `
        -OutputPath $outputPath `
        -Force:$Force | Out-Null
}

$stageMap = @{}
foreach ($stage in $stageDefinitions) { $stageMap[$stage.Name] = $stage }
$prepareScripts = @{}
foreach ($targetStageName in $workflowRules.PreparationGates.Keys) {
    if (-not $stageMap.ContainsKey([string]$targetStageName)) {
        throw "Preparation gate targets unknown stage: $targetStageName"
    }
    $gate = $workflowRules.PreparationGates[$targetStageName]
    $sourceStageName = [string]$gate.SourceStage
    if (-not $stageMap.ContainsKey($sourceStageName)) {
        throw "Preparation gate references unknown source stage: $sourceStageName"
    }
    $preparePath = Join-Path $stageMap[[string]$targetStageName].Directory 'prepare_stage.sh'
    if ((Test-Path -LiteralPath $preparePath) -and -not $Force) {
        throw "Preparation script already exists: $preparePath. Use -Force to replace it."
    }
    $prepareScripts[$preparePath] = New-PreparationScript -Gate $gate -SourceJobName $stageMap[$sourceStageName].JobName -WorkRoot $WorkRoot
}

foreach ($preparePath in $prepareScripts.Keys) {
    [System.IO.File]::WriteAllText([string]$preparePath, [string]$prepareScripts[$preparePath], $utf8WithoutBom)
}

foreach ($stage in $stageDefinitions) {
    & $preflight `
        -InputDirectory $stage.Directory `
        -JobName $stage.JobName `
        -CalculationType $stage.CalculationType `
        -RulesPath $InputRulesPath `
        -RulesOverridePath $InputRulesOverridePath | Out-Host
}

$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
    RootDirectory = $root
    WorkRoot = $WorkRoot
    Rules = [ordered]@{
        Workflow = $WorkflowRulesPath
        WorkflowOverride = $WorkflowRulesOverridePath
        Input = $InputRulesPath
        InputOverride = $InputRulesOverridePath
    }
    Resources = [ordered]@{
        Cores = $Cores
        Partition = $Partition
        SlurmBin = $SlurmBin
        VaspBin = $VaspBin
        OneApiSetup = $OneApiSetup
        MpiLauncher = $MpiLauncher
        VaspExecutable = $VaspExecutable
        MemoryPerCpu = $MemoryPerCpu
    }
    Stages = @(
        foreach ($stage in $stageDefinitions) {
            $manifestStage = [ordered]@{
                Name = $stage.Name
                JobName = $stage.JobName
                Walltime = $stage.Walltime
                Directory = $stage.Directory
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$stage.DependsOn)) {
                $manifestStage.DependsOn = $stageMap[[string]$stage.DependsOn].JobName
            }
            $manifestStage
        }
    )
}

$manifestPath = Join-Path $root 'chain-manifest.json'
if ((Test-Path -LiteralPath $manifestPath) -and -not $Force) {
    throw "Manifest already exists: $manifestPath. Use -Force to replace it."
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifestPath, $manifestJson + "`n", $utf8WithoutBom)

[pscustomobject]@{
    RootDirectory = $root
    ManifestPath = $manifestPath
    RelaxJobName = $RelaxJobName
    ScfJobName = $ScfJobName
    BandJobName = $BandJobName
}

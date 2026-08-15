[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Server,

    [Parameter(Mandatory)]
    [string]$RootDirectory,

    [string]$WorkflowRulesPath = (Join-Path $PSScriptRoot '..\config\rules\workflow-rules.psd1'),

    [string]$WorkflowRulesOverridePath = '',

    [string]$InputRulesPath = (Join-Path $PSScriptRoot '..\config\rules\input-rules.psd1'),

    [string]$InputRulesOverridePath = '',

    [ValidateRange(0, 120)]
    [int]$SmokeCheckSeconds = 8,

    [switch]$StagedSubmit,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force
$workflowRules = Import-VaspRuleSet -BasePath $WorkflowRulesPath -OverridePath $WorkflowRulesOverridePath -RequiredKeys @('Defaults', 'Stages', 'PreparationGates', 'Submission')
$requiredStages = @($workflowRules.Submission.RequiredStages | ForEach-Object { [string]$_ })
$requiredRemoteFiles = @($workflowRules.Defaults.RequiredRemoteFiles | ForEach-Object { [string]$_ })
$requiredRemoteFileWords = $requiredRemoteFiles -join ' '
$smokeRules = $workflowRules.Submission.Smoke
$allowedInitialSmokeStatuses = @($smokeRules.AllowedInitialStatuses | ForEach-Object { [string]$_ })
$dependencyType = [string]$workflowRules.Submission.DependencyType
$killDependencyProbe = [string]$workflowRules.Submission.KillOnInvalidDependencyProbe
$killDependencyOption = [string]$workflowRules.Submission.KillOnInvalidDependencyOption
foreach ($ruleText in @($smokeRules.FatalLaunchRegex, $smokeRules.StructureWarningRegex, $smokeRules.CompletionPattern, $dependencyType, $killDependencyProbe, $killDependencyOption)) {
    if ([string]::IsNullOrWhiteSpace([string]$ruleText) -or [string]$ruleText -match "['\r\n]") {
        throw 'Workflow submission rules contain an empty or unsafe value.'
    }
}
foreach ($fileName in $requiredRemoteFiles) {
    if ($fileName -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Required remote file name contains unsupported characters: $fileName"
    }
}

function Invoke-RemoteBash {
    param(
        [Parameter(Mandatory)][string]$SshAlias,
        [Parameter(Mandatory)][string]$Script
    )

    $normalized = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $output = @(& ssh -o BatchMode=yes $SshAlias "echo $encoded | base64 -d | bash" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed on ${SshAlias}:`n$($output -join "`n")"
    }
    return $output
}

function Assert-SafeName {
    param([string]$Value, [string]$Label)
    if ($Value -notmatch '^[A-Za-z0-9._-]+$') {
        throw "$Label contains unsupported characters: $Value"
    }
}

function New-SmokeScript {
    param(
        [Parameter(Mandatory)][string]$RelaxId,
        [string]$ScfId = '',
        [string]$BandId = ''
    )

    $queueIds = $RelaxId
    if ($ScfId) { $queueIds += ",$ScfId" }
    if ($BandId) { $queueIds += ",$BandId" }

    return @'
set -u
slurm="__SLURM_BIN__"
dir="$HOME/__WORK_ROOT__/__RELAX__"
echo QUEUE
$slurm/squeue -j "__QUEUE_IDS__" -o '%.18i|%.36j|%.8T|%.10M|%.6D|%R'
if grep -Eqi '__FATAL_LAUNCH_REGEX__' "$dir/slurm-__RELAX_ID__.err" "$dir/slurm-__RELAX_ID__.out" 2>/dev/null; then
    echo 'SMOKE_STATUS=FAILED_LAUNCH'
elif grep -Eqi '__STRUCTURE_WARNING_REGEX__' "$dir/slurm-__RELAX_ID__.out" 2>/dev/null; then
    echo 'SMOKE_STATUS=FAILED_STRUCTURE_WARNING'
elif $slurm/squeue -h -j __RELAX_ID__ | grep -q .; then
    echo 'SMOKE_STATUS=STARTED_OR_QUEUED'
elif grep -Fq '__COMPLETION_PATTERN__' "$dir/OUTCAR" 2>/dev/null; then
    echo 'SMOKE_STATUS=COMPLETED_EARLY'
else
    echo 'SMOKE_STATUS=UNKNOWN'
fi
tail -n 20 "$dir/slurm-__RELAX_ID__.err" 2>/dev/null || true
tail -n 20 "$dir/slurm-__RELAX_ID__.out" 2>/dev/null || true
'@.Replace('__SLURM_BIN__', $slurmBin).Replace('__WORK_ROOT__', $workRoot).Replace('__RELAX__', $relaxName).Replace('__QUEUE_IDS__', $queueIds).Replace('__RELAX_ID__', $RelaxId).Replace('__FATAL_LAUNCH_REGEX__', [string]$smokeRules.FatalLaunchRegex).Replace('__STRUCTURE_WARNING_REGEX__', [string]$smokeRules.StructureWarningRegex).Replace('__COMPLETION_PATTERN__', [string]$smokeRules.CompletionPattern)
}

$root = (Resolve-Path -LiteralPath $RootDirectory).Path
$manifestPath = Join-Path $root 'chain-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Chain manifest does not exist: $manifestPath. Run render_band_chain.ps1 first."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1 -or $manifest.Stages.Count -ne 3) {
    throw 'Unsupported or invalid chain manifest.'
}

$stageMap = @{}
foreach ($stage in $manifest.Stages) {
    Assert-SafeName ([string]$stage.JobName) "Job name for stage $($stage.Name)"
    $stageDirectory = Join-Path $root ([string]$stage.Name)
    if (-not (Test-Path -LiteralPath $stageDirectory -PathType Container)) {
        throw "Stage directory does not exist: $stageDirectory"
    }
    $stageMap[[string]$stage.Name] = [pscustomobject]@{
        Name = [string]$stage.Name
        JobName = [string]$stage.JobName
        Walltime = [string]$stage.Walltime
        Directory = $stageDirectory
    }
}

foreach ($requiredStage in $requiredStages) {
    if (-not $stageMap.ContainsKey($requiredStage)) {
        throw "Manifest is missing stage: $requiredStage"
    }
}

if ([string]$manifest.WorkRoot -notmatch '^[A-Za-z0-9._/-]+$' -or [string]$manifest.WorkRoot -match '(^|/)\.\.(/|$)') {
    throw 'Manifest WorkRoot is unsafe.'
}

$selectServer = Join-Path $PSScriptRoot 'select_server.ps1'
$checkSsh = Join-Path $PSScriptRoot 'check_ssh_hosts.ps1'
$runtimeCheck = Join-Path $PSScriptRoot 'check_vasp_runtime.ps1'
$preflight = Join-Path $PSScriptRoot 'preflight_job.ps1'
& $selectServer -Server $Server | Out-Host

$expectedSettings = @{
    Partition = $env:VASP_PARTITION
    SlurmBin = $env:VASP_SLURM_BIN
    VaspBin = $env:VASP_VASP_BIN
    OneApiSetup = $env:VASP_ONEAPI_SETUP
    MpiLauncher = $env:VASP_MPI_LAUNCHER
    VaspExecutable = $env:VASP_EXECUTABLE
    MemoryPerCpu = $env:VASP_MEMORY_PER_CPU
}
foreach ($setting in $expectedSettings.Keys) {
    $manifestValue = [string]$manifest.Resources.$setting
    if ($manifestValue -cne [string]$expectedSettings[$setting]) {
        throw "Manifest setting $setting='$manifestValue' does not match selected server value '$($expectedSettings[$setting])'. Re-render the chain after selecting the server."
    }
}
if ([string]$manifest.WorkRoot -cne $env:VASP_WORK_ROOT) {
    throw "Manifest WorkRoot '$($manifest.WorkRoot)' does not match selected server WorkRoot '$($env:VASP_WORK_ROOT)'."
}

& $preflight -InputDirectory $stageMap.relax.Directory -JobName $stageMap.relax.JobName -CalculationType Relax -RulesPath $InputRulesPath -RulesOverridePath $InputRulesOverridePath | Out-Host
& $preflight -InputDirectory $stageMap.scf.Directory -JobName $stageMap.scf.JobName -CalculationType Scf -RulesPath $InputRulesPath -RulesOverridePath $InputRulesOverridePath | Out-Host
& $preflight -InputDirectory $stageMap.band.Directory -JobName $stageMap.band.JobName -CalculationType Band -RulesPath $InputRulesPath -RulesOverridePath $InputRulesOverridePath | Out-Host

$plan = [pscustomobject]@{
    Server = $env:VASP_SERVER_KEY
    SshAlias = $env:VASP_SSH_ALIAS
    WorkRoot = $env:VASP_WORK_ROOT
    RelaxJobName = $stageMap.relax.JobName
    ScfJobName = $stageMap.scf.JobName
    BandJobName = $stageMap.band.JobName
    Cores = [int]$manifest.Resources.Cores
    StagedSubmit = [bool]$StagedSubmit
    DryRun = [bool]$DryRun
}

if ($DryRun) {
    Write-Output 'Dry run: local validation passed; no remote directories were created and no jobs were submitted.'
    return $plan
}

& $checkSsh -Server $env:VASP_SERVER_KEY | Out-Host
& $runtimeCheck -Server $env:VASP_SERVER_KEY -SkipSshCheck | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'VASP runtime compatibility check failed; no remote directories or jobs were created.'
}

$relaxName = $stageMap.relax.JobName
$scfName = $stageMap.scf.JobName
$bandName = $stageMap.band.JobName
$workRoot = $env:VASP_WORK_ROOT
$slurmBin = $env:VASP_SLURM_BIN
$stagedFlag = if ($StagedSubmit) { 'yes' } else { 'no' }

$createScript = @'
set -euo pipefail
work_root="$HOME/__WORK_ROOT__"
for name in __RELAX__ __SCF__ __BAND__; do
    target="$work_root/$name"
    if [[ -e "$target" ]]; then
        echo "ERROR: target already exists: $target" >&2
        exit 4
    fi
done
__SLURM_BIN__/sinfo -o 'PARTITION|AVAIL|TIMELIMIT|NODES|CPUS|MEMORY' | head -n 8
mkdir -p "$work_root/__RELAX__" "$work_root/__SCF__" "$work_root/__BAND__"
'@.Replace('__WORK_ROOT__', $workRoot).Replace('__RELAX__', $relaxName).Replace('__SCF__', $scfName).Replace('__BAND__', $bandName).Replace('__SLURM_BIN__', $slurmBin)
Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $createScript | Out-Host

foreach ($stage in @($stageMap.relax, $stageMap.scf, $stageMap.band)) {
    $sourceFiles = $requiredRemoteFiles | ForEach-Object { Join-Path $stage.Directory $_ }
    $prepareStage = Join-Path $stage.Directory 'prepare_stage.sh'
    if (Test-Path -LiteralPath $prepareStage -PathType Leaf) {
        $sourceFiles += $prepareStage
    }
    $destination = "$($env:VASP_SSH_ALIAS):~/$workRoot/$($stage.JobName)/"
    $scpArguments = @('-q') + $sourceFiles + $destination
    & scp @scpArguments
    if ($LASTEXITCODE -ne 0) {
        throw "SCP upload failed for stage $($stage.Name). Remote directories were created but no cleanup was performed."
    }
}

$submitScript = @'
set -euo pipefail
work_root="$HOME/__WORK_ROOT__"
slurm="__SLURM_BIN__"
relax="$work_root/__RELAX__"
scf="$work_root/__SCF__"
band="$work_root/__BAND__"
for dir in "$relax" "$scf" "$band"; do
    for file in __REQUIRED_REMOTE_FILES__; do
        [[ -s "$dir/$file" ]] || { echo "ERROR: missing or empty $dir/$file" >&2; exit 5; }
    done
    ! grep -q $'\r' "$dir/run_vasp.slurm" || { echo "ERROR: CRLF in $dir/run_vasp.slurm" >&2; exit 5; }
    bash -n "$dir/run_vasp.slurm"
    grep -q '^export PATH="$slurm_bin:' "$dir/run_vasp.slurm" || { echo "ERROR: SLURM PATH guard missing in $dir/run_vasp.slurm" >&2; exit 5; }
    if [[ -e "$dir/prepare_stage.sh" ]]; then
        [[ -s "$dir/prepare_stage.sh" ]] || { echo "ERROR: empty $dir/prepare_stage.sh" >&2; exit 5; }
        bash -n "$dir/prepare_stage.sh"
    fi
done
cd "$relax"
relax_raw=$($slurm/sbatch --parsable run_vasp.slurm)
relax_id=${relax_raw%%;*}
[[ "$relax_id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid relax job id: $relax_raw" >&2; exit 6; }
echo "RELAX_JOB_ID=$relax_id"
if [[ "__STAGED_SUBMIT__" == "yes" ]]; then
    $slurm/squeue -j "$relax_id" -o '%.18i|%.36j|%.8T|%.10M|%.6D|%R'
    exit 0
fi
cd "$scf"
if $slurm/sbatch --help 2>&1 | grep -q -- '__KILL_DEPENDENCY_PROBE__'; then
    scf_raw=$($slurm/sbatch --parsable __KILL_DEPENDENCY_OPTION__ --dependency="__DEPENDENCY_TYPE__:$relax_id" run_vasp.slurm)
else
    scf_raw=$($slurm/sbatch --parsable --dependency="__DEPENDENCY_TYPE__:$relax_id" run_vasp.slurm)
fi
scf_id=${scf_raw%%;*}
[[ "$scf_id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid SCF job id: $scf_raw" >&2; exit 6; }
cd "$band"
if $slurm/sbatch --help 2>&1 | grep -q -- '__KILL_DEPENDENCY_PROBE__'; then
    band_raw=$($slurm/sbatch --parsable __KILL_DEPENDENCY_OPTION__ --dependency="__DEPENDENCY_TYPE__:$scf_id" run_vasp.slurm)
else
    band_raw=$($slurm/sbatch --parsable --dependency="__DEPENDENCY_TYPE__:$scf_id" run_vasp.slurm)
fi
band_id=${band_raw%%;*}
[[ "$band_id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid band job id: $band_raw" >&2; exit 6; }
echo "SCF_JOB_ID=$scf_id"
echo "BAND_JOB_ID=$band_id"
$slurm/squeue -j "$relax_id,$scf_id,$band_id" -o '%.18i|%.36j|%.8T|%.10M|%.6D|%R'
'@.Replace('__WORK_ROOT__', $workRoot).Replace('__RELAX__', $relaxName).Replace('__SCF__', $scfName).Replace('__BAND__', $bandName).Replace('__SLURM_BIN__', $slurmBin).Replace('__STAGED_SUBMIT__', $stagedFlag).Replace('__REQUIRED_REMOTE_FILES__', $requiredRemoteFileWords).Replace('__KILL_DEPENDENCY_PROBE__', $killDependencyProbe).Replace('__KILL_DEPENDENCY_OPTION__', $killDependencyOption).Replace('__DEPENDENCY_TYPE__', $dependencyType)
$submissionOutput = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $submitScript
$submissionOutput | Out-Host

$submissionText = $submissionOutput -join [Environment]::NewLine
$relaxId = [regex]::Match($submissionText, '(?m)^RELAX_JOB_ID=(\d+)$').Groups[1].Value
$scfId = [regex]::Match($submissionText, '(?m)^SCF_JOB_ID=(\d+)$').Groups[1].Value
$bandId = [regex]::Match($submissionText, '(?m)^BAND_JOB_ID=(\d+)$').Groups[1].Value
if (-not $relaxId) {
    throw 'Submission returned without a valid Relax Job ID.'
}

if ($SmokeCheckSeconds -gt 0) {
    Start-Sleep -Seconds $SmokeCheckSeconds
}

if ($StagedSubmit) {
    if ($scfId -or $bandId) {
        throw 'Staged submission unexpectedly returned dependent Job IDs before the Relax smoke check.'
    }
    $initialSmokeOutput = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script (New-SmokeScript -RelaxId $relaxId)
    $initialSmokeOutput | Out-Host
    $initialSmokeStatus = [regex]::Match(($initialSmokeOutput -join [Environment]::NewLine), '(?m)^SMOKE_STATUS=([^\r\n]+)$').Groups[1].Value
    if ($initialSmokeStatus -like 'FAILED_*') {
        throw "Staged submission stopped after Relax smoke check $initialSmokeStatus. No SCF or Band job was submitted."
    }
    if ($initialSmokeStatus -notin $allowedInitialSmokeStatuses) {
        throw "Staged submission stopped because Relax smoke status is inconclusive: $initialSmokeStatus. No SCF or Band job was submitted."
    }

    $dependentSubmitScript = @'
set -euo pipefail
work_root="$HOME/__WORK_ROOT__"
slurm="__SLURM_BIN__"
scf="$work_root/__SCF__"
band="$work_root/__BAND__"
for dir in "$scf" "$band"; do
    for file in __REQUIRED_REMOTE_FILES__; do
        [[ -s "$dir/$file" ]] || { echo "ERROR: missing or empty $dir/$file" >&2; exit 5; }
    done
    ! grep -q $'\r' "$dir/run_vasp.slurm" || { echo "ERROR: CRLF in $dir/run_vasp.slurm" >&2; exit 5; }
    bash -n "$dir/run_vasp.slurm"
    if [[ -e "$dir/prepare_stage.sh" ]]; then bash -n "$dir/prepare_stage.sh"; fi
done
cd "$scf"
if $slurm/sbatch --help 2>&1 | grep -q -- '__KILL_DEPENDENCY_PROBE__'; then
    scf_raw=$($slurm/sbatch --parsable __KILL_DEPENDENCY_OPTION__ --dependency="__DEPENDENCY_TYPE__:__RELAX_ID__" run_vasp.slurm)
else
    scf_raw=$($slurm/sbatch --parsable --dependency="__DEPENDENCY_TYPE__:__RELAX_ID__" run_vasp.slurm)
fi
scf_id=${scf_raw%%;*}
[[ "$scf_id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid SCF job id: $scf_raw" >&2; exit 6; }
cd "$band"
if $slurm/sbatch --help 2>&1 | grep -q -- '__KILL_DEPENDENCY_PROBE__'; then
    band_raw=$($slurm/sbatch --parsable __KILL_DEPENDENCY_OPTION__ --dependency="__DEPENDENCY_TYPE__:$scf_id" run_vasp.slurm)
else
    band_raw=$($slurm/sbatch --parsable --dependency="__DEPENDENCY_TYPE__:$scf_id" run_vasp.slurm)
fi
band_id=${band_raw%%;*}
[[ "$band_id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid Band job id: $band_raw" >&2; exit 6; }
echo "SCF_JOB_ID=$scf_id"
echo "BAND_JOB_ID=$band_id"
$slurm/squeue -j "__RELAX_ID__,$scf_id,$band_id" -o '%.18i|%.36j|%.8T|%.10M|%.6D|%R'
'@.Replace('__WORK_ROOT__', $workRoot).Replace('__SCF__', $scfName).Replace('__BAND__', $bandName).Replace('__SLURM_BIN__', $slurmBin).Replace('__RELAX_ID__', $relaxId).Replace('__REQUIRED_REMOTE_FILES__', $requiredRemoteFileWords).Replace('__KILL_DEPENDENCY_PROBE__', $killDependencyProbe).Replace('__KILL_DEPENDENCY_OPTION__', $killDependencyOption).Replace('__DEPENDENCY_TYPE__', $dependencyType)
    $dependentOutput = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $dependentSubmitScript
    $dependentOutput | Out-Host
    $dependentText = $dependentOutput -join [Environment]::NewLine
    $scfId = [regex]::Match($dependentText, '(?m)^SCF_JOB_ID=(\d+)$').Groups[1].Value
    $bandId = [regex]::Match($dependentText, '(?m)^BAND_JOB_ID=(\d+)$').Groups[1].Value
    if (-not $scfId -or -not $bandId) {
        throw 'Staged submission returned without valid SCF and Band Job IDs.'
    }
} elseif (-not $scfId -or -not $bandId) {
    throw 'Submission returned without three valid Job IDs.'
}

if ($StagedSubmit -and $SmokeCheckSeconds -gt 0) {
    Start-Sleep -Seconds $SmokeCheckSeconds
}

$smokeOutput = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script (New-SmokeScript -RelaxId $relaxId -ScfId $scfId -BandId $bandId)
$smokeOutput | Out-Host
$smokeStatus = [regex]::Match(($smokeOutput -join [Environment]::NewLine), '(?m)^SMOKE_STATUS=([^\r\n]+)$').Groups[1].Value
if ($smokeStatus -like 'FAILED_*') {
    throw "Submission succeeded, but smoke check reported $smokeStatus. Do not resubmit or cancel automatically; inspect the listed jobs and obtain explicit user confirmation before cancellation."
}

[pscustomobject]@{
    Server = $env:VASP_SERVER_KEY
    SshAlias = $env:VASP_SSH_ALIAS
    RelaxJobId = $relaxId
    ScfJobId = $scfId
    BandJobId = $bandId
    RelaxDirectory = "~/$workRoot/$relaxName"
    ScfDirectory = "~/$workRoot/$scfName"
    BandDirectory = "~/$workRoot/$bandName"
    SmokeStatus = $smokeStatus
}

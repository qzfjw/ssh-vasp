[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('yang', 'lan')]
    [string]$Server,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d+$')]
    [string]$JobId,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$JobName = '',

    [ValidateRange(1, 200)]
    [int]$TailLines = 40,

    [switch]$SkipSshCheck
)

$ErrorActionPreference = 'Stop'

function Invoke-RemoteBash {
    param([string]$SshAlias, [string]$Script)

    $normalized = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $output = @(& ssh -o BatchMode=yes -o ConnectTimeout=20 $SshAlias "echo $encoded | base64 -d | bash" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Remote job query failed on ${SshAlias}:`n$($output -join "`n")"
    }
    return $output
}

$selectServer = Join-Path $PSScriptRoot 'select_server.ps1'
$checkSsh = Join-Path $PSScriptRoot 'check_ssh_hosts.ps1'
& $selectServer -Server $Server | Out-Host
if (-not $SkipSshCheck) {
    & $checkSsh -Server $env:VASP_SERVER_KEY | Out-Host
}

$jobTail = if ($JobName) {
@'
job_dir="$HOME/__WORK_ROOT__/__JOB_NAME__"
echo '== FILES =='
if [[ -d "$job_dir" ]]; then
    find "$job_dir" -maxdepth 1 -type f -printf '%f|%s\n' | sort
    echo '== STDERR =='
    tail -n __TAIL_LINES__ "$job_dir/slurm-__JOB_ID__.err" 2>/dev/null || true
    echo '== STDOUT =='
    tail -n __TAIL_LINES__ "$job_dir/slurm-__JOB_ID__.out" 2>/dev/null || true
    echo '== OSZICAR =='
    tail -n __TAIL_LINES__ "$job_dir/OSZICAR" 2>/dev/null || true
    echo '== OUTCAR =='
    tail -n __TAIL_LINES__ "$job_dir/OUTCAR" 2>/dev/null || true
else
    echo "JOB_DIRECTORY_STATUS=NOT_FOUND:$job_dir"
fi
'@.Replace('__WORK_ROOT__', $env:VASP_WORK_ROOT).Replace('__JOB_NAME__', $JobName).Replace('__JOB_ID__', $JobId).Replace('__TAIL_LINES__', [string]$TailLines)
} else { '' }

$remoteScript = @'
set -u
slurm='__SLURM_BIN__'
job_id='__JOB_ID__'
echo '== IDENTITY =='
echo "SERVER=__SERVER_KEY__"
echo "SSH_ALIAS=__SSH_ALIAS__"
echo "JOB_ID=$job_id"
echo "REMOTE_USER=$(id -un)"
echo '== SQUEUE =='
queue_output=$($slurm/squeue -h -j "$job_id" -o '%i|%j|%u|%T|%M|%D|%R' 2>&1)
queue_status=$?
printf '%s\n' "$queue_output"
echo "SQUEUE_EXIT=$queue_status"
if [[ "$queue_status" -eq 0 && -n "$queue_output" ]]; then
    echo 'QUEUE_STATUS=PRESENT'
else
    echo 'QUEUE_STATUS=ABSENT_OR_UNAVAILABLE'
fi
echo '== SACCT =='
if [[ -x "$slurm/sacct" ]]; then
    sacct_output=$($slurm/sacct -j "$job_id" --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End -n -X 2>&1)
    sacct_status=$?
    printf '%s\n' "$sacct_output"
    echo "SACCT_EXIT=$sacct_status"
else
    echo 'SACCT_STATUS=UNAVAILABLE'
fi
__JOB_TAIL__
'@.Replace('__SLURM_BIN__', $env:VASP_SLURM_BIN).Replace('__JOB_ID__', $JobId).Replace('__SERVER_KEY__', $env:VASP_SERVER_KEY).Replace('__SSH_ALIAS__', $env:VASP_SSH_ALIAS).Replace('__JOB_TAIL__', $jobTail)

$output = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $remoteScript
$output | Write-Output

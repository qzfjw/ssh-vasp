[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('yang', 'lan')]
    [string]$Server,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d+$')]
    [string]$JobId,

    [Parameter(Mandatory)]
    [string]$ConfirmedTarget,

    [switch]$SkipSshCheck
)

$ErrorActionPreference = 'Stop'

function Invoke-RemoteBash {
    param([string]$SshAlias, [string]$Script)

    $normalized = $Script.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $output = @(& ssh -o BatchMode=yes -o ConnectTimeout=20 $SshAlias "echo $encoded | base64 -d | bash" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Remote cancellation failed on ${SshAlias}:`n$($output -join "`n")"
    }
    return $output
}

$selectServer = Join-Path $PSScriptRoot 'select_server.ps1'
$checkSsh = Join-Path $PSScriptRoot 'check_ssh_hosts.ps1'
& $selectServer -Server $Server | Out-Host
if (-not $SkipSshCheck) {
    & $checkSsh -Server $env:VASP_SERVER_KEY | Out-Host
}

$expectedConfirmation = "$($env:VASP_SERVER_KEY)/$JobId"
if ($ConfirmedTarget -cne $expectedConfirmation) {
    throw "Cancellation confirmation mismatch. After showing the current queue entry, obtain explicit user confirmation and pass -ConfirmedTarget '$expectedConfirmation'."
}

$remoteScript = @'
set -euo pipefail
slurm='__SLURM_BIN__'
job_id='__JOB_ID__'
current_user=$(id -un)
queue_line=$($slurm/squeue -h -j "$job_id" -o '%i|%j|%u|%T|%M|%R')
if [[ -z "$queue_line" ]]; then
    echo "ERROR: job is not present in squeue: $job_id" >&2
    exit 4
fi
job_user=$(printf '%s\n' "$queue_line" | head -n 1 | cut -d'|' -f3 | xargs)
if [[ "$job_user" != "$current_user" ]]; then
    echo "ERROR: refusing to cancel job owned by '$job_user' while logged in as '$current_user'" >&2
    exit 5
fi
echo "CANCEL_TARGET=$queue_line"
$slurm/scancel "$job_id"
echo "SCANCEL_STATUS=SUBMITTED"
remaining=$($slurm/squeue -h -j "$job_id" -o '%i|%j|%u|%T|%M|%R')
if [[ -n "$remaining" ]]; then
    echo "POST_CANCEL_QUEUE=$remaining"
else
    echo 'POST_CANCEL_QUEUE=ABSENT'
fi
'@.Replace('__SLURM_BIN__', $env:VASP_SLURM_BIN).Replace('__JOB_ID__', $JobId)

$output = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $remoteScript
$output | Write-Output

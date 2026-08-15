[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('yang', 'lan')]
    [string]$Server,

    [string]$RulesPath = (Join-Path $PSScriptRoot '..\config\rules\runtime-rules.psd1'),

    [string]$RulesOverridePath = '',

    [string]$IncidentsPath = (Join-Path $PSScriptRoot '..\config\rules\incidents'),

    [switch]$SkipSshCheck,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force

function Invoke-RemoteBash {
    param(
        [Parameter(Mandatory)][string]$SshAlias,
        [Parameter(Mandatory)][string]$Script
    )

    $normalized = $Script.Replace([Environment]::NewLine, [string][char]10).Replace([string][char]13, [string][char]10)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
    $output = @(& ssh -o BatchMode=yes -o ConnectTimeout=20 $SshAlias "echo $encoded | base64 -d | bash" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Remote VASP runtime check failed on $SshAlias. Output: $($output -join [Environment]::NewLine)"
    }
    return $output
}

$rules = Import-VaspRuleSet -BasePath $RulesPath -OverridePath $RulesOverridePath -RequiredKeys @('Common', 'Servers')

$selectServer = Join-Path $PSScriptRoot 'select_server.ps1'
& $selectServer -Server $Server | Out-Host
$serverKey = [string]$env:VASP_SERVER_KEY
if (-not $rules.Servers.Contains($serverKey)) {
    throw "Runtime rules do not define server '$serverKey'."
}

$serverRules = $rules.Servers[$serverKey]
$activeIncidents = @()
if (Test-Path -LiteralPath $IncidentsPath -PathType Container) {
    $activeIncidents = @(
        Get-ChildItem -LiteralPath $IncidentsPath -Filter '*.psd1' -File | ForEach-Object {
            $incident = Import-VaspRuleSet -BasePath $_.FullName -RequiredKeys @('Id', 'AppliesTo', 'Symptoms', 'PreventedBy')
            if (
                [string]$incident.AppliesTo.Server -ieq $serverKey -and
                [string]$incident.AppliesTo.VaspVersion -eq [string]$serverRules.ExpectedVaspVersion
            ) {
                $incident
            }
        }
    )
}
$settingChecks = @{
    VaspBin = [string]$serverRules.ExpectedVaspBin
    VaspExecutable = [string]$serverRules.ExpectedVaspExecutable
    MpiLauncher = [string]$serverRules.ExpectedMpiLauncher
}
$selectedSettings = @{
    VaspBin = [string]$env:VASP_VASP_BIN
    VaspExecutable = [string]$env:VASP_EXECUTABLE
    MpiLauncher = [string]$env:VASP_MPI_LAUNCHER
}
foreach ($settingName in $settingChecks.Keys) {
    if ([string]::IsNullOrWhiteSpace($settingChecks[$settingName])) {
        throw "Runtime rule '$settingName' is missing for server '$serverKey'."
    }
    if ($settingChecks[$settingName] -cne $selectedSettings[$settingName]) {
        throw "Selected server setting $settingName='$($selectedSettings[$settingName])' does not match runtime rule '$($settingChecks[$settingName])'."
    }
}

$requiredExecutableType = [string]$rules.Common.RequiredExecutableType
$forbiddenLddText = @($rules.Common.ForbiddenLddText | ForEach-Object { [string]$_ })
$requiredMpiLddText = @($rules.Common.RequiredMpiLddText | ForEach-Object { [string]$_ })
$requiredLddText = @($serverRules.RequiredLddText | ForEach-Object { [string]$_ })
$expectedVersion = [string]$serverRules.ExpectedVaspVersion
$expectedMpiRegex = [string]$serverRules.ExpectedMpiVersionRegex
$oneApiSetup = [string]$env:VASP_ONEAPI_SETUP

foreach ($value in @($requiredExecutableType, $expectedVersion, $expectedMpiRegex, $oneApiSetup)) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Runtime rules or selected server configuration is incomplete for '$serverKey'."
    }
}

Write-Output "Runtime rules: server=$serverKey"
Write-Output "  VASP executable: $($env:VASP_VASP_BIN)/$($env:VASP_EXECUTABLE)"
Write-Output "  MPI launcher: $($env:VASP_MPI_LAUNCHER)"
Write-Output "  oneAPI setup: $oneApiSetup"
Write-Output "  expected VASP version label: $expectedVersion"
Write-Output "  expected MPI version pattern: $expectedMpiRegex"
if ($activeIncidents.Count -gt 0) {
    Write-Output "  active incident guards: $(@($activeIncidents.Id) -join ', ')"
}

if ($DryRun) {
    Write-Output 'Dry run: runtime rules validated; no SSH connection was made.'
    return
}

$checkSsh = Join-Path $PSScriptRoot 'check_ssh_hosts.ps1'
if (-not $SkipSshCheck) {
    & $checkSsh -Server $serverKey | Out-Host
}

$remoteScript = @'
set -euo pipefail
server_key='__SERVER_KEY__'
vasp_bin='__VASP_BIN__'
vasp_executable="$vasp_bin/__VASP_EXECUTABLE__"
expected_vasp_version='__EXPECTED_VASP_VERSION__'
oneapi_setup='__ONEAPI_SETUP__'
mpi_launcher='__MPI_LAUNCHER__'
expected_mpi_regex='__EXPECTED_MPI_REGEX__'
required_executable_type='__REQUIRED_EXECUTABLE_TYPE__'

fail() {
    echo "RUNTIME_STATUS=FAIL"
    echo "RUNTIME_REASON=$1" >&2
    exit 1
}

[[ -d "$vasp_bin" ]] || fail "VASP directory does not exist: $vasp_bin"
[[ "$vasp_bin" == *"$expected_vasp_version"* ]] || fail "VASP directory does not contain expected version label: $expected_vasp_version"
[[ -f "$oneapi_setup" ]] || fail "oneAPI setup file does not exist: $oneapi_setup"
[[ -x "$mpi_launcher" ]] || fail "MPI launcher is not executable: $mpi_launcher"
[[ -x "$vasp_executable" ]] || fail "VASP executable is not executable: $vasp_executable"

file_output=$(file "$vasp_executable" 2>&1) || fail "file inspection failed: $file_output"
echo "$file_output"
echo "$file_output" | grep -Fqi "$required_executable_type" || fail "VASP executable type does not match: $required_executable_type"

set +e
set +u
source "$oneapi_setup" intel64 --force >"/tmp/codex_vasp_setvars.$$.log" 2>&1
setvars_status=$?
set -u
set -e
if [[ "$setvars_status" -ne 0 ]]; then
    cat "/tmp/codex_vasp_setvars.$$.log" >&2 || true
    rm -f "/tmp/codex_vasp_setvars.$$.log"
    fail "oneAPI setup failed with status $setvars_status"
fi
rm -f "/tmp/codex_vasp_setvars.$$.log"

set +e
ldd_output=$(ldd "$vasp_executable" 2>&1)
ldd_status=$?
set -e
[[ "$ldd_status" -eq 0 ]] || fail "ldd failed with status $ldd_status: $ldd_output"
echo "$ldd_output"
__FORBIDDEN_LDD_CHECKS__
__REQUIRED_MPI_LDD_CHECKS__
__REQUIRED_LDD_CHECKS__

set +e
mpi_output=$("$mpi_launcher" -version 2>&1)
mpi_status=$?
set -e
[[ "$mpi_status" -eq 0 ]] || fail "MPI version probe failed with status $mpi_status: $mpi_output"
echo "$mpi_output"
echo "$mpi_output" | grep -Eq "$expected_mpi_regex" || fail "MPI version does not match expected pattern: $expected_mpi_regex"

version_evidence=$(strings "$vasp_executable" 2>/dev/null | grep -E -i -m1 "vasp|$expected_vasp_version" || true)
if [[ -n "$version_evidence" ]]; then
    echo "VASP_VERSION_EVIDENCE=$version_evidence"
else
    echo 'VASP_VERSION_EVIDENCE=not exposed by executable strings (informational only)'
fi

echo 'RUNTIME_STATUS=PASS'
'@

$forbiddenChecks = foreach ($pattern in $forbiddenLddText) {
    ('printf ''%s\\n'' "$ldd_output" | grep -Fqi ''__PATTERN__'' && fail ''ldd contains forbidden text: __PATTERN__''').Replace('__PATTERN__', $pattern)
}
$requiredMpiChecks = foreach ($pattern in $requiredMpiLddText) {
    ('printf ''%s\\n'' "$ldd_output" | grep -Fqi ''__PATTERN__'' || fail ''ldd is missing required MPI library text: __PATTERN__''').Replace('__PATTERN__', $pattern)
}
$requiredPathChecks = foreach ($pattern in $requiredLddText) {
    ('printf ''%s\\n'' "$ldd_output" | grep -Fqi ''__PATTERN__'' || fail ''ldd is missing required server library path: __PATTERN__''').Replace('__PATTERN__', $pattern)
}
$remoteScript = $remoteScript.Replace('__SERVER_KEY__', $serverKey).Replace('__VASP_BIN__', [string]$serverRules.ExpectedVaspBin).Replace('__VASP_EXECUTABLE__', [string]$serverRules.ExpectedVaspExecutable).Replace('__EXPECTED_VASP_VERSION__', $expectedVersion).Replace('__ONEAPI_SETUP__', $oneApiSetup).Replace('__MPI_LAUNCHER__', [string]$serverRules.ExpectedMpiLauncher).Replace('__EXPECTED_MPI_REGEX__', $expectedMpiRegex).Replace('__REQUIRED_EXECUTABLE_TYPE__', $requiredExecutableType).Replace('__FORBIDDEN_LDD_CHECKS__', ($forbiddenChecks -join [Environment]::NewLine)).Replace('__REQUIRED_MPI_LDD_CHECKS__', ($requiredMpiChecks -join [Environment]::NewLine)).Replace('__REQUIRED_LDD_CHECKS__', ($requiredPathChecks -join [Environment]::NewLine))

$runtimeOutput = Invoke-RemoteBash -SshAlias $env:VASP_SSH_ALIAS -Script $remoteScript
$runtimeOutput | Out-Host
$runtimeText = $runtimeOutput -join [Environment]::NewLine
if ($runtimeText -notmatch '(?m)^RUNTIME_STATUS=PASS$') {
    throw "VASP runtime compatibility check did not pass on $serverKey."
}
Write-Output "VASP runtime compatibility check passed on $serverKey; no VASP process was started."

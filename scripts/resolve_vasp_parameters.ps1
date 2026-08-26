[CmdletBinding()]
param(
    [ValidateSet('Relax', 'Scf', 'Dos', 'Band', 'Phonon')]
    [string]$Task = 'Relax',

    [string]$PoscarPath = '',

    [string]$RulesRoot = '',

    [ValidateSet('Text', 'Object')]
    [string]$Format = 'Text'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RulesRoot)) {
    $RulesRoot = Join-Path $PSScriptRoot '..\config\rules'
}
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force

function ConvertTo-InvariantDouble {
    param([Parameter(Mandatory)][string]$Text)

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $value = 0.0
    if (-not [double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $culture, [ref]$value)) {
        throw "Invalid numeric value in POSCAR: $Text"
    }
    return $value
}

function Get-VectorLength {
    param([double[]]$Vector)
    return [math]::Sqrt($Vector[0] * $Vector[0] + $Vector[1] * $Vector[1] + $Vector[2] * $Vector[2])
}

function Get-CellVolume {
    param([object[]]$Lattice)

    $cross = @(
        ($Lattice[1][1] * $Lattice[2][2] - $Lattice[1][2] * $Lattice[2][1]),
        ($Lattice[1][2] * $Lattice[2][0] - $Lattice[1][0] * $Lattice[2][2]),
        ($Lattice[1][0] * $Lattice[2][1] - $Lattice[1][1] * $Lattice[2][0])
    )
    return [math]::Abs(
        $Lattice[0][0] * $cross[0] +
        $Lattice[0][1] * $cross[1] +
        $Lattice[0][2] * $cross[2]
    )
}

function Get-PoscarSummary {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "POSCAR does not exist: $Path"
    }

    $lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Path).Path)
    if ($lines.Count -lt 7) {
        throw 'POSCAR is too short to read lattice and species.'
    }

    $rawScale = ConvertTo-InvariantDouble $lines[1].Trim()
    if ($rawScale -eq 0) {
        throw 'POSCAR scale factor must not be zero.'
    }

    $rawLattice = @()
    for ($lineIndex = 2; $lineIndex -le 4; $lineIndex++) {
        $parts = @($lines[$lineIndex].Trim() -split '\s+' | Where-Object { $_ })
        if ($parts.Count -lt 3) {
            throw "POSCAR lattice line $($lineIndex + 1) has fewer than three values."
        }
        $rawLattice += ,@(
            (ConvertTo-InvariantDouble $parts[0]),
            (ConvertTo-InvariantDouble $parts[1]),
            (ConvertTo-InvariantDouble $parts[2])
        )
    }

    $scale = $rawScale
    if ($rawScale -lt 0) {
        $rawVolume = Get-CellVolume $rawLattice
        if ($rawVolume -le 0) {
            throw 'POSCAR lattice volume is zero.'
        }
        $scale = [math]::Pow([math]::Abs($rawScale) / $rawVolume, 1.0 / 3.0)
    }

    $lattice = @()
    foreach ($vector in $rawLattice) {
        $lattice += ,@(($vector[0] * $scale), ($vector[1] * $scale), ($vector[2] * $scale))
    }

    $lineFive = @($lines[5].Trim() -split '\s+' | Where-Object { $_ })
    $hasElementLine = $lineFive.Count -gt 0 -and
        @($lineFive | Where-Object { $_ -notmatch '^[A-Z][a-z]?$' }).Count -eq 0
    $elements = if ($hasElementLine) { @($lineFive) } else { @() }

    return [pscustomobject]@{
        Elements = $elements
        Lengths = @(
            (Get-VectorLength $lattice[0]),
            (Get-VectorLength $lattice[1]),
            (Get-VectorLength $lattice[2])
        )
    }
}

function Merge-ParameterMap {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Override
    )

    $merged = @{}
    foreach ($key in $Base.Keys) {
        $merged[$key] = [string]$Base[$key]
    }
    foreach ($key in $Override.Keys) {
        $merged[$key] = [string]$Override[$key]
    }
    return $merged
}

function Test-ContainsElementGroup {
    param(
        [string[]]$Elements,
        [System.Collections.IDictionary]$ElementGroups,
        [object]$GroupNames
    )

    foreach ($groupName in @($GroupNames)) {
        if (-not $ElementGroups.Contains($groupName)) {
            continue
        }
        foreach ($element in $Elements) {
            if (@($ElementGroups[$groupName]) -contains $element) {
                return $true
            }
        }
    }
    return $false
}

$parameterRoot = Join-Path $RulesRoot 'parameters'
$incarRules = Import-VaspRuleSet -BasePath (Join-Path $parameterRoot 'incar-rules.psd1') -RequiredKeys @('DefaultParameters', 'Profiles')
$kpointsRules = Import-VaspRuleSet -BasePath (Join-Path $parameterRoot 'kpoints-rules.psd1') -RequiredKeys @('MeshProfiles')
$profiles = Import-VaspRuleSet -BasePath (Join-Path $parameterRoot 'profiles.psd1') -RequiredKeys @('Tasks')

$taskProfile = $profiles.Tasks[$Task]
if ($null -eq $taskProfile) {
    throw "No parameter profile is defined for task: $Task"
}

$incarProfileName = [string]$taskProfile.IncarProfile
$incarProfile = $incarRules.Profiles[$incarProfileName]
if ($null -eq $incarProfile) {
    throw "INCAR profile '$incarProfileName' is not defined."
}

$poscar = $null
if (-not [string]::IsNullOrWhiteSpace($PoscarPath)) {
    $poscar = Get-PoscarSummary -Path $PoscarPath
}

$parameters = Merge-ParameterMap -Base $incarRules.DefaultParameters -Override $incarProfile.Parameters
$ruleNotes = [System.Collections.Generic.List[string]]::new()
if ($null -ne $poscar -and $poscar.Elements.Count -gt 0) {
    foreach ($rule in @($incarRules.ConditionalRules)) {
        if ($rule.Contains('IfContainsAnyElementGroup') -and
            (Test-ContainsElementGroup -Elements $poscar.Elements -ElementGroups $incarRules.ElementGroups -GroupNames $rule.IfContainsAnyElementGroup)) {
            foreach ($key in $rule.Parameters.Keys) {
                $parameters[$key] = [string]$rule.Parameters[$key]
            }
            $ruleNotes.Add([string]$rule.Reason)
        }
    }
}

$kpointsProfileName = [string]$taskProfile.KpointsProfile
$kpointsProfile = $kpointsRules.MeshProfiles[$kpointsProfileName]
if ($null -eq $kpointsProfile) {
    throw "KPOINTS profile '$kpointsProfileName' is not defined."
}

$kpoints = $null
if ([string]$kpointsProfile.Style -eq 'Gamma' -and $null -ne $poscar) {
    $target = [double]$kpointsProfile.TargetLengthProduct
    $minimum = [int]$kpointsProfile.MinimumComponent
    $mesh = @()
    foreach ($length in $poscar.Lengths) {
        if ($length -le 0) {
            throw 'POSCAR contains a non-positive lattice length.'
        }
        $mesh += [math]::Max($minimum, [int][math]::Ceiling($target / $length))
    }
    $kpoints = [pscustomobject]@{
        Style = 'Gamma'
        Mesh = $mesh
        TargetLengthProduct = $target
    }
} elseif ([string]$kpointsProfile.Style -eq 'Line-mode') {
    $kpoints = [pscustomobject]@{
        Style = 'Line-mode'
        RequiresManualPath = $true
    }
}

$result = [pscustomobject]@{
    Task = $Task
    Description = [string]$taskProfile.Description
    IncarProfile = $incarProfileName
    KpointsProfile = $kpointsProfileName
    Elements = if ($null -ne $poscar) { $poscar.Elements } else { @() }
    LatticeLengthsAngstrom = if ($null -ne $poscar) { $poscar.Lengths } else { @() }
    IncarParameters = $parameters
    Kpoints = $kpoints
    Review = @($incarProfile.Review + $ruleNotes + $kpointsRules.Notes)
}

if ($Format -eq 'Object') {
    $result
    return
}

Write-Output "Task: $($result.Task)"
Write-Output "Description: $($result.Description)"
if ($result.Elements.Count -gt 0) {
    Write-Output "Elements: $($result.Elements -join ', ')"
    Write-Output ("Lattice lengths (Angstrom): {0}" -f (($result.LatticeLengthsAngstrom | ForEach-Object { '{0:F4}' -f $_ }) -join ', '))
}
Write-Output ''
Write-Output 'INCAR recommendation:'
foreach ($key in @($result.IncarParameters.Keys | Sort-Object)) {
    Write-Output ("{0} = {1}" -f $key, $result.IncarParameters[$key])
}
Write-Output ''
Write-Output 'KPOINTS recommendation:'
if ($null -eq $result.Kpoints) {
    Write-Output "No automatic KPOINTS recommendation because POSCAR was not supplied."
} elseif ($result.Kpoints.Style -eq 'Gamma') {
    Write-Output 'Automatic mesh'
    Write-Output '0'
    Write-Output 'Gamma'
    Write-Output ($result.Kpoints.Mesh -join ' ')
    Write-Output '0 0 0'
} else {
    Write-Output 'Use Line-mode KPOINTS with a manually chosen high-symmetry path.'
}
Write-Output ''
Write-Output 'Review notes:'
foreach ($note in $result.Review) {
    Write-Output "- $note"
}

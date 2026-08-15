[CmdletBinding()]
param(
    [string]$InputDirectory = '.',

    [Parameter(Mandatory)]
    [string]$JobName,

    [string]$SlurmFile = 'run_vasp.slurm',

    [ValidateSet('Auto', 'Relax', 'Scf', 'Static', 'Band')]
    [string]$CalculationType = 'Auto',

    [string]$RulesPath = (Join-Path $PSScriptRoot '..\config\rules\input-rules.psd1'),

    [string]$RulesOverridePath = '',

    [ValidateRange(0.0, 1.5)]
    [double]$MinimumCovalentRatio = 0.0,

    [ValidateRange(0.0, 5.0)]
    [double]$AbsoluteMinimumDistance = 0.0,

    [switch]$SkipGeometryCheck
)

$ErrorActionPreference = 'Stop'
$ruleModule = Join-Path $PSScriptRoot 'lib\VaspRuleEngine.psm1'
Import-Module $ruleModule -Force
$inputRules = Import-VaspRuleSet -BasePath $RulesPath -OverridePath $RulesOverridePath -RequiredKeys @('RequiredFiles', 'Geometry', 'AutoDetection', 'CalculationTypes')
if ($MinimumCovalentRatio -eq 0.0) {
    $MinimumCovalentRatio = [double]$inputRules.Geometry.MinimumCovalentRatio
}
if ($AbsoluteMinimumDistance -eq 0.0) {
    $AbsoluteMinimumDistance = [double]$inputRules.Geometry.AbsoluteMinimumDistanceAngstrom
}
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$culture = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-Number {
    param([Parameter(Mandatory)][string]$Text)

    $value = 0.0
    $parsed = [double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $culture, [ref]$value)
    if (-not $parsed) {
        throw "Invalid numeric value: $Text"
    }
    return $value
}

function Get-VectorLength {
    param([double[]]$Vector)
    return [math]::Sqrt($Vector[0] * $Vector[0] + $Vector[1] * $Vector[1] + $Vector[2] * $Vector[2])
}

function Convert-FractionalToCartesian {
    param(
        [double[]]$Fractional,
        [object[]]$Lattice
    )

    return @(
        ($Fractional[0] * $Lattice[0][0] + $Fractional[1] * $Lattice[1][0] + $Fractional[2] * $Lattice[2][0]),
        ($Fractional[0] * $Lattice[0][1] + $Fractional[1] * $Lattice[1][1] + $Fractional[2] * $Lattice[2][1]),
        ($Fractional[0] * $Lattice[0][2] + $Fractional[1] * $Lattice[1][2] + $Fractional[2] * $Lattice[2][2])
    )
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

function Get-IncarSettings {
    param([string]$Path)

    $settings = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $settings
    }

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $content = ($line -split '[#!]', 2)[0].Trim()
        if ($content -match '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $settings[$matches[1].ToUpperInvariant()] = $matches[2].Trim()
        }
    }
    return $settings
}

function Test-InputRuleCheck {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Check,
        [Parameter(Mandatory)][hashtable]$Incar,
        [Parameter(Mandatory)][string]$KpointsText,
        [Parameter(Mandatory)][string]$Directory
    )

    $kind = [string]$Check.Kind
    switch ($kind) {
        'IncarEquals' {
            $key = [string]$Check.Key
            return $Incar.ContainsKey($key) -and [string]$Incar[$key] -eq [string]$Check.Value
        }
        'IncarIntegerGreaterThan' {
            $key = [string]$Check.Key
            if (-not $Incar.ContainsKey($key)) { return $false }
            $value = 0
            if (-not [int]::TryParse(([string]$Incar[$key] -split '\s+')[0], [ref]$value)) { return $false }
            return $value -gt [int]$Check.Value
        }
        'IncarIntegerEquals' {
            $key = [string]$Check.Key
            if (-not $Incar.ContainsKey($key)) {
                return $Check.Contains('AllowMissing') -and [bool]$Check.AllowMissing
            }
            $value = 0
            if (-not [int]::TryParse(([string]$Incar[$key] -split '\s+')[0], [ref]$value)) { return $false }
            return $value -eq [int]$Check.Value
        }
        'KpointsRegex' {
            return $KpointsText -match [string]$Check.Pattern
        }
        'AnyFileExists' {
            foreach ($fileName in @($Check.Files)) {
                if (Test-Path -LiteralPath (Join-Path $Directory ([string]$fileName)) -PathType Leaf) {
                    return $true
                }
            }
            return $false
        }
        default {
            throw "Unsupported input rule check kind: $kind"
        }
    }
}

function Get-PoscarData {
    param([string]$Path)

    $lines = [System.IO.File]::ReadAllLines($Path)
    if ($lines.Count -lt 8) {
        throw 'POSCAR is too short to contain a structure.'
    }

    $rawScale = ConvertTo-Number $lines[1].Trim()
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
            (ConvertTo-Number $parts[0]),
            (ConvertTo-Number $parts[1]),
            (ConvertTo-Number $parts[2])
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

    if ($hasElementLine) {
        $elements = $lineFive
        $countLineIndex = 6
    } else {
        $elements = @()
        $countLineIndex = 5
    }

    $countParts = @($lines[$countLineIndex].Trim() -split '\s+' | Where-Object { $_ })
    if ($countParts.Count -eq 0 -or @($countParts | Where-Object { $_ -notmatch '^\d+$' }).Count -gt 0) {
        throw 'POSCAR atom-count line is invalid.'
    }
    $counts = @($countParts | ForEach-Object { [int]$_ })
    if ($hasElementLine -and $elements.Count -ne $counts.Count) {
        throw 'POSCAR element and atom-count columns have different lengths.'
    }

    $coordinateModeIndex = $countLineIndex + 1
    if ($lines[$coordinateModeIndex].Trim() -match '^[Ss]') {
        $coordinateModeIndex++
    }
    $mode = $lines[$coordinateModeIndex].Trim()
    $isDirect = $mode -match '^[Dd]'
    $isCartesian = $mode -match '^[CcKk]'
    if (-not $isDirect -and -not $isCartesian) {
        throw "Unsupported POSCAR coordinate mode: $mode"
    }

    $atomCount = ($counts | Measure-Object -Sum).Sum
    $coordinateStart = $coordinateModeIndex + 1
    if ($lines.Count -lt $coordinateStart + $atomCount) {
        throw "POSCAR contains fewer than $atomCount coordinate lines."
    }

    $coordinates = @()
    for ($atomIndex = 0; $atomIndex -lt $atomCount; $atomIndex++) {
        $parts = @($lines[$coordinateStart + $atomIndex].Trim() -split '\s+' | Where-Object { $_ })
        if ($parts.Count -lt 3) {
            throw "POSCAR coordinate line $($coordinateStart + $atomIndex + 1) has fewer than three values."
        }
        $coordinate = @(
            (ConvertTo-Number $parts[0]),
            (ConvertTo-Number $parts[1]),
            (ConvertTo-Number $parts[2])
        )
        if ($isCartesian) {
            $coordinate = @(($coordinate[0] * $scale), ($coordinate[1] * $scale), ($coordinate[2] * $scale))
        }
        $coordinates += ,$coordinate
    }

    $species = @()
    if ($hasElementLine) {
        for ($elementIndex = 0; $elementIndex -lt $elements.Count; $elementIndex++) {
            for ($copyIndex = 0; $copyIndex -lt $counts[$elementIndex]; $copyIndex++) {
                $species += $elements[$elementIndex]
            }
        }
    }

    return [pscustomobject]@{
        Lines          = $lines
        Elements       = $elements
        Counts         = $counts
        Species        = $species
        AtomCount      = $atomCount
        Lattice        = $lattice
        Coordinates    = $coordinates
        IsDirect       = $isDirect
        HasElementLine = $hasElementLine
    }
}

function Get-NearestNeighbor {
    param([pscustomobject]$Poscar)

    $nearest = $null
    for ($first = 0; $first -lt $Poscar.AtomCount; $first++) {
        for ($second = $first + 1; $second -lt $Poscar.AtomCount; $second++) {
            for ($tx = -1; $tx -le 1; $tx++) {
                for ($ty = -1; $ty -le 1; $ty++) {
                    for ($tz = -1; $tz -le 1; $tz++) {
                        if ($Poscar.IsDirect) {
                            $deltaFractional = @(
                                ($Poscar.Coordinates[$second][0] - $Poscar.Coordinates[$first][0] + $tx),
                                ($Poscar.Coordinates[$second][1] - $Poscar.Coordinates[$first][1] + $ty),
                                ($Poscar.Coordinates[$second][2] - $Poscar.Coordinates[$first][2] + $tz)
                            )
                            $delta = Convert-FractionalToCartesian $deltaFractional $Poscar.Lattice
                        } else {
                            $translation = Convert-FractionalToCartesian @($tx, $ty, $tz) $Poscar.Lattice
                            $delta = @(
                                ($Poscar.Coordinates[$second][0] - $Poscar.Coordinates[$first][0] + $translation[0]),
                                ($Poscar.Coordinates[$second][1] - $Poscar.Coordinates[$first][1] + $translation[1]),
                                ($Poscar.Coordinates[$second][2] - $Poscar.Coordinates[$first][2] + $translation[2])
                            )
                        }
                        $distance = Get-VectorLength $delta
                        if ($null -eq $nearest -or $distance -lt $nearest.Distance) {
                            $nearest = [pscustomobject]@{
                                First    = $first
                                Second   = $second
                                Distance = $distance
                            }
                        }
                    }
                }
            }
        }
    }
    return $nearest
}

if ($JobName -notmatch '^[A-Za-z0-9._-]+$') {
    $errors.Add('JobName may contain only letters, digits, dot, underscore, and hyphen.')
}

try {
    $directory = (Resolve-Path -LiteralPath $InputDirectory).Path
} catch {
    throw "Input directory does not exist: $InputDirectory"
}

$requiredFiles = @($inputRules.RequiredFiles | ForEach-Object { [string]$_ })
foreach ($fileName in $requiredFiles) {
    $filePath = Join-Path $directory $fileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $errors.Add("Missing required file: $fileName")
        continue
    }
    if ((Get-Item -LiteralPath $filePath).Length -eq 0) {
        $errors.Add("Required file is empty: $fileName")
    }
}

$slurmPath = Join-Path $directory $SlurmFile
if (-not (Test-Path -LiteralPath $slurmPath -PathType Leaf)) {
    $errors.Add("Missing SLURM script: $SlurmFile")
} else {
    $slurmText = [System.IO.File]::ReadAllText($slurmPath)
    if (-not $slurmText.StartsWith('#!/bin/bash')) {
        $errors.Add("SLURM script must start with #!/bin/bash: $SlurmFile")
    }
    if ($slurmText.Contains("`r")) {
        $errors.Add("SLURM script contains CR or CRLF line endings: $SlurmFile")
    }
    if ($slurmText -match '\{\{[A-Z_]+\}\}') {
        $errors.Add("SLURM script contains unresolved template variables: $SlurmFile")
    }
    if ($slurmText -match 'mpi_launcher|mpiexec' -and $slurmText -notmatch '(?m)^\s*export PATH=.*(?:slurm_bin|/opt/slurm/bin|/usr/bin)') {
        $warnings.Add('SLURM script launches MPI but does not visibly add the configured SLURM bin directory to PATH.')
    }
}

$prepareStagePath = Join-Path $directory 'prepare_stage.sh'
if (Test-Path -LiteralPath $prepareStagePath -PathType Leaf) {
    $prepareText = [System.IO.File]::ReadAllText($prepareStagePath)
    if ([string]::IsNullOrWhiteSpace($prepareText)) {
        $errors.Add('prepare_stage.sh exists but is empty.')
    }
    if ($prepareText.Contains("`r")) {
        $errors.Add('prepare_stage.sh contains CR or CRLF line endings.')
    }
    if (-not $prepareText.StartsWith('#!/bin/bash')) {
        $errors.Add('prepare_stage.sh must start with #!/bin/bash.')
    }
}

$poscarPath = Join-Path $directory 'POSCAR'
$potcarPath = Join-Path $directory 'POTCAR'
$poscar = $null
if (Test-Path -LiteralPath $poscarPath -PathType Leaf) {
    try {
        $poscar = Get-PoscarData $poscarPath
    } catch {
        $errors.Add("POSCAR parse failed at script line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)")
    }
}

if ($null -ne $poscar -and (Test-Path -LiteralPath $potcarPath -PathType Leaf)) {
    $titleLines = @(Select-String -LiteralPath $potcarPath -Pattern '^\s*TITEL\s*=')
    if ($titleLines.Count -eq 0) {
        $warnings.Add('No TITEL records were found in POTCAR; species validation was skipped.')
    } elseif ($poscar.HasElementLine -and $poscar.Elements.Count -ne $titleLines.Count) {
        $errors.Add("POSCAR lists $($poscar.Elements.Count) species but POTCAR contains $($titleLines.Count) TITEL records.")
    } elseif ($poscar.HasElementLine) {
        $potcarElements = @()
        foreach ($titleLine in $titleLines) {
            if ($titleLine.Line -match 'TITEL\s*=\s*\S+\s+(?<label>[A-Z][a-z]?(?:_[A-Za-z0-9]+)?)\b') {
                $potcarElements += ($matches.label -split '_', 2)[0]
            }
        }
        if ($potcarElements.Count -ne $titleLines.Count) {
            $warnings.Add('Some POTCAR TITEL species labels could not be parsed; order validation was incomplete.')
        } else {
            for ($speciesIndex = 0; $speciesIndex -lt $poscar.Elements.Count; $speciesIndex++) {
                if ($poscar.Elements[$speciesIndex] -cne $potcarElements[$speciesIndex]) {
                    $errors.Add("POTCAR species order mismatch at position $($speciesIndex + 1): POSCAR=$($poscar.Elements[$speciesIndex]), POTCAR=$($potcarElements[$speciesIndex]).")
                }
            }
        }
    } else {
        $warnings.Add('POSCAR appears to use VASP 4 style; POTCAR species order must be checked manually.')
    }
}

$nearest = $null
if ($null -ne $poscar -and -not $SkipGeometryCheck) {
    if ($poscar.AtomCount -lt 2) {
        $warnings.Add('POSCAR contains fewer than two atoms; nearest-neighbor validation was skipped.')
    } else {
        $nearest = Get-NearestNeighbor $poscar
        if ($null -ne $nearest) {
            if ($nearest.Distance -lt $AbsoluteMinimumDistance) {
                $errors.Add(('Implausibly short periodic distance: {0:F4} angstrom between atoms {1} and {2}; absolute threshold is {3:F4} angstrom.' -f $nearest.Distance, ($nearest.First + 1), ($nearest.Second + 1), $AbsoluteMinimumDistance))
            }

            if ($poscar.HasElementLine) {
                $radii = $inputRules.Geometry.CovalentRadiiAngstrom
                $firstElement = $poscar.Species[$nearest.First]
                $secondElement = $poscar.Species[$nearest.Second]
                if ($radii.Contains($firstElement) -and $radii.Contains($secondElement)) {
                    $radiusSum = [double]$radii[$firstElement] + [double]$radii[$secondElement]
                    $ratio = $nearest.Distance / $radiusSum
                    if ($ratio -lt $MinimumCovalentRatio) {
                        $errors.Add(('Implausibly short {0}-{1} distance: {2:F4} angstrom ({3:F3} x covalent-radius sum; threshold {4:F3}).' -f $firstElement, $secondElement, $nearest.Distance, $ratio, $MinimumCovalentRatio))
                    }
                } else {
                    $warnings.Add("Covalent-radius validation was unavailable for $firstElement-$secondElement.")
                }
            }
        }
    }
}

$incarPath = Join-Path $directory 'INCAR'
$kpointsPath = Join-Path $directory 'KPOINTS'
$incar = Get-IncarSettings $incarPath
$kpointsText = if (Test-Path -LiteralPath $kpointsPath -PathType Leaf) { [System.IO.File]::ReadAllText($kpointsPath) } else { '' }
$effectiveCalculationType = $CalculationType
if ($effectiveCalculationType -eq 'Auto') {
    $effectiveCalculationType = [string]$inputRules.AutoDetection.DefaultCalculationType
    foreach ($check in @($inputRules.AutoDetection.Checks)) {
        if (Test-InputRuleCheck -Check $check -Incar $incar -KpointsText $kpointsText -Directory $directory) {
            $effectiveCalculationType = [string]$check.CalculationType
            break
        }
    }
}

$calculationRules = $inputRules.CalculationTypes[$effectiveCalculationType]
if ($null -eq $calculationRules) {
    throw "Input rules do not define calculation type: $effectiveCalculationType"
}
foreach ($check in @($calculationRules.Checks)) {
    if (-not (Test-InputRuleCheck -Check $check -Incar $incar -KpointsText $kpointsText -Directory $directory)) {
        switch ([string]$check.Severity) {
            'Warning' { $warnings.Add([string]$check.Message) }
            'Error' { $errors.Add([string]$check.Message) }
            default { throw "Unsupported input rule severity: $($check.Severity)" }
        }
    }
}

Write-Output "Preflight directory: $directory"
Write-Output "Job name: $JobName"
Write-Output "Calculation type: $effectiveCalculationType"
if ($null -ne $nearest) {
    $pair = if ($poscar.HasElementLine) { "$($poscar.Species[$nearest.First])-$($poscar.Species[$nearest.Second])" } else { "atoms $($nearest.First + 1)-$($nearest.Second + 1)" }
    Write-Output ('Nearest periodic distance: {0:F4} angstrom ({1})' -f $nearest.Distance, $pair)
}

foreach ($warning in $warnings) {
    Write-Warning $warning
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Error $message
    }
    exit 1
}

Write-Output 'Required file checks: PASS'
$hashNames = @($requiredFiles + $SlurmFile)
if (Test-Path -LiteralPath $prepareStagePath -PathType Leaf) {
    $hashNames += 'prepare_stage.sh'
}
$hashPaths = @($hashNames | ForEach-Object { Join-Path $directory $_ })
Get-FileHash -Algorithm SHA256 -LiteralPath $hashPaths | Select-Object Path, Hash

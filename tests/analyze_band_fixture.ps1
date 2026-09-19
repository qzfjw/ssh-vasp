[CmdletBinding()]
param(
    [string]$Node = 'node'
)

$ErrorActionPreference = 'Stop'
$skillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$analyzer = Join-Path $skillRoot 'scripts\analyze_band.cjs'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('fang-band-test-' + [guid]::NewGuid().ToString('N'))
$scf = Join-Path $tempRoot 'scf'
$band = Join-Path $tempRoot 'band'
$output = Join-Path $tempRoot 'output'

try {
    New-Item -ItemType Directory -Path $scf, $band | Out-Null

    $eigenval = @'
header
header
header
header
header
 2 2 3

 0.000000 0.000000 0.000000 1.000000
 1 -1.000000 2.000000
 2  1.000000 0.000000
 3  2.000000 0.000000

 0.500000 0.000000 0.000000 1.000000
 1 -0.800000 2.000000
 2  1.200000 0.000000
 3  2.200000 0.000000
'@
    Set-Content -LiteralPath (Join-Path $scf 'EIGENVAL') -Value $eigenval -Encoding utf8
    Set-Content -LiteralPath (Join-Path $band 'EIGENVAL') -Value $eigenval -Encoding utf8

    $poscar = @'
synthetic negative scale
-8.0
1 0 0
0 1 0
0 0 1
Si
1
Direct
0 0 0
'@
    Set-Content -LiteralPath (Join-Path $band 'POSCAR') -Value $poscar -Encoding utf8
    $kpoints = @'
Line-mode test
2
synthetic
Reciprocal
0 0 0 ! Gamma
0.5 0 0 ! X
'@
    Set-Content -LiteralPath (Join-Path $band 'KPOINTS') -Value $kpoints -Encoding utf8
    Set-Content -LiteralPath (Join-Path $band 'INCAR') -Value "ISPIN = 1`n" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $band 'OUTCAR') -Value " ISPIN  = 1`n" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $scf 'OUTCAR') -Value " ISPIN  = 1`n" -Encoding utf8

    & $Node $analyzer $scf $band $output
    if ($LASTEXITCODE -ne 0) { throw "Analyzer exited with code $LASTEXITCODE" }
    $summary = Get-Content -LiteralPath (Join-Path $output 'band_gap_summary.json') -Raw | ConvertFrom-Json
    if ([math]::Abs([double]$summary.plottedPath.indirectGapEv - 1.8) -gt 1e-8) {
        throw "Unexpected plotted-path gap: $($summary.plottedPath.indirectGapEv)"
    }
    if ((Get-Content -LiteralPath (Join-Path $output 'band_gap_summary.txt') -Raw) -notmatch 'SCF E-fermi: not found') {
        throw 'Missing-Fermi fallback was not reported.'
    }
    Write-Output 'Synthetic band analysis: PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

@{
    SchemaVersion = 1
    Id = 'lan-init-mpi-integer-divide-by-zero'
    AppliesTo = @{ Server='lan'; VaspVersion='6.5.1' }
    Symptoms = @('forrtl: severe (71): integer divide by zero', 'init_mpi')
    Severity = 'Fatal'
    PreventedBy = @('ApprovedVaspPath', 'ApprovedMpiLauncher', 'RequiredMpiLibraries', 'ExpectedMpiVersion')
    Resolution = 'Use the approved Lan VASP 6.5.1 executable with Intel MPI 2021.15 and verify linkage before creating remote directories.'
}

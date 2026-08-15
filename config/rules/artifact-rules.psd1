@{
    SchemaVersion = 1

    Download = @{
        EssentialFiles = @(
            'INCAR', 'POSCAR', 'KPOINTS', 'CONTCAR', 'OUTCAR', 'OSZICAR',
            'EIGENVAL', 'DOSCAR', 'PROCAR', 'vasprun.xml', 'XDATCAR',
            'run_vasp.slurm', 'prepare_stage.sh'
        )
        AdditionalNameRegex = '^slurm-.*\.(out|err)$'
        LargeFiles = @('WAVECAR', 'CHGCAR')
    }
}

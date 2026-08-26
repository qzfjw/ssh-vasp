@{
    SchemaVersion = 1

    Tasks = @{
        Relax = @{
            Description = 'Structure optimization with ordinary force and electronic convergence settings.'
            IncarProfile = 'Relax'
            KpointsProfile = 'GammaLengthProduct25'
            RequiredInputs = @('POSCAR', 'POTCAR')
            Produces = @('CONTCAR', 'OUTCAR', 'OSZICAR')
        }

        Scf = @{
            Description = 'Static self-consistent calculation, commonly after a converged Relax task.'
            IncarProfile = 'Scf'
            KpointsProfile = 'DenseScfLengthProduct35'
            RequiredInputs = @('POSCAR', 'POTCAR')
            Produces = @('CHGCAR', 'OUTCAR', 'OSZICAR')
        }

        Dos = @{
            Description = 'DOS calculation from a converged charge density.'
            IncarProfile = 'Dos'
            KpointsProfile = 'DenseScfLengthProduct35'
            RequiredInputs = @('POSCAR', 'POTCAR', 'CHGCAR')
            Produces = @('DOSCAR', 'PROCAR', 'OUTCAR')
        }

        Band = @{
            Description = 'Band calculation from SCF charge density and Line-mode KPOINTS.'
            IncarProfile = 'Band'
            KpointsProfile = 'BandLineMode'
            RequiredInputs = @('POSCAR', 'POTCAR', 'CHGCAR')
            Produces = @('EIGENVAL', 'PROCAR', 'OUTCAR')
        }

        Phonon = @{
            Description = 'Force-sensitive setup for phonon-related relaxation or displacements.'
            IncarProfile = 'Phonon'
            KpointsProfile = 'GammaLengthProduct25'
            RequiredInputs = @('POSCAR', 'POTCAR')
            Produces = @('CONTCAR', 'OUTCAR', 'vasprun.xml')
        }
    }
}

@{
    SchemaVersion = 1

    ElementGroups = @{
        Transition3d = @('Sc', 'Ti', 'V', 'Cr', 'Mn', 'Fe', 'Co', 'Ni', 'Cu', 'Zn')
        Lanthanide4f = @('Ce', 'Pr', 'Nd', 'Pm', 'Sm', 'Eu', 'Gd', 'Tb', 'Dy', 'Ho', 'Er', 'Tm', 'Yb')
        Actinide5f   = @('Th', 'Pa', 'U', 'Np', 'Pu', 'Am', 'Cm')
    }

    DefaultParameters = @{
        ISTART    = '0'
        ICHARG    = '2'
        ISPIN     = '2'
        PREC      = 'M'
        GGA       = 'PE'
        VOSKOWN   = '1'
        ENCUT     = '500.0'
        LMAXMIX   = '2'
        ALGO      = 'FAST'
        NPAR      = '4'
        ADDGRID   = '.F.'
        AMIX      = '0.2'
        AMIX_MAG  = '0.8'
        BMIX_MAG  = '0.00001'
        NELM      = '50'
        NELMIN    = '6'
        LREAL     = 'Auto'
        EDIFF     = '1E-5'
        ISMEAR    = '0'
        SIGMA     = '0.1'
        LORBIT    = '11'
        LWAVE     = '.F.'
        LCHARG    = '.F.'
    }

    Profiles = @{
        Relax = @{
            Description = 'General structural relaxation.'
            Parameters = @{
                EDIFFG = '-0.02'
                NSW    = '500'
                IBRION = '2'
                ISIF   = '2'
                ISYM   = '2'
                POTIM  = '0.2'
            }
            Review = @(
                'Use ISIF=3 when the lattice vectors should relax.'
                'Set MAGMOM explicitly for magnetic systems and for special molecules such as O2.'
                'Use ADDGRID=.T. for force-sensitive tasks such as phonons or difficult relaxations.'
            )
        }

        Scf = @{
            Description = 'Static self-consistent calculation after relaxation.'
            Parameters = @{
                NSW    = '0'
                IBRION = '-1'
                ISIF   = '2'
                LCHARG = '.T.'
                LWAVE  = '.F.'
            }
            Review = @(
                'Use a denser KPOINTS mesh than relaxation when accurate energies or band inputs are needed.'
            )
        }

        Dos = @{
            Description = 'DOS calculation using a converged charge density.'
            Parameters = @{
                NSW     = '0'
                IBRION  = '-1'
                ICHARG  = '11'
                LORBIT  = '11'
                NEDOS   = '2000'
                LCHARG  = '.F.'
                LWAVE   = '.F.'
            }
            Review = @(
                'Increase SIGMA only when DOS peaks are too sharp for interpretation.'
            )
        }

        Band = @{
            Description = 'Band structure calculation using the SCF CHGCAR.'
            Parameters = @{
                NSW     = '0'
                IBRION  = '-1'
                ICHARG  = '11'
                LORBIT  = '11'
                LCHARG  = '.F.'
                LWAVE   = '.F.'
            }
            Review = @(
                'Band calculations need Line-mode KPOINTS and a valid CHGCAR from SCF.'
            )
        }

        Phonon = @{
            Description = 'Force-sensitive relaxation or displacement calculation support.'
            Parameters = @{
                EDIFF   = '1E-6'
                EDIFFG  = '-0.01'
                NSW     = '500'
                IBRION  = '2'
                ISIF    = '2'
                ADDGRID = '.T.'
            }
            Review = @(
                'Use tighter force convergence and check whether symmetry should be disabled for the chosen phonon workflow.'
            )
        }
    }

    ConditionalRules = @(
        @{
            Name = 'LMAXMIX_3d'
            IfContainsAnyElementGroup = 'Transition3d'
            Parameters = @{ LMAXMIX = '4' }
            Reason = '3d transition-metal systems usually need LMAXMIX=4.'
        }
        @{
            Name = 'LMAXMIX_4f_5f'
            IfContainsAnyElementGroup = @('Lanthanide4f', 'Actinide5f')
            Parameters = @{ LMAXMIX = '6' }
            Reason = 'f-electron systems usually need LMAXMIX=6.'
        }
    )
}

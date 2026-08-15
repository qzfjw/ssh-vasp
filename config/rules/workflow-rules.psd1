@{
    SchemaVersion = 1

    Defaults = @{
        Cores = 48
        RequiredInputFiles = @('INCAR', 'POSCAR', 'KPOINTS', 'POTCAR')
        RequiredRemoteFiles = @('INCAR', 'POSCAR', 'KPOINTS', 'POTCAR', 'run_vasp.slurm')
    }

    Stages = @(
        @{ Name='relax'; CalculationType='Relax'; DefaultWalltime='24:00:00' }
        @{ Name='scf'; CalculationType='Scf'; DefaultWalltime='04:00:00'; DependsOn='relax' }
        @{ Name='band'; CalculationType='Band'; DefaultWalltime='04:00:00'; DependsOn='scf' }
    )

    PreparationGates = @{
        scf = @{
            SourceStage = 'relax'
            RequiredNonEmptyFiles = @('OUTCAR', 'CONTCAR')
            MissingFilesMessage = 'relaxation OUTCAR or CONTCAR is missing: $source_dir'
            RequiredTextChecks = @(
                @{ File='OUTCAR'; MatchMode='Fixed'; Pattern='reached required accuracy - stopping structural energy minimisation'; Message='relaxation did not reach the ionic stopping criterion' }
                @{ File='OUTCAR'; MatchMode='Fixed'; Pattern='General timing and accounting informations for this job'; Message='relaxation OUTCAR lacks the normal timing footer' }
            )
            CopyFiles = @(
                @{ Source='CONTCAR'; Destination='POSCAR' }
            )
        }
        band = @{
            SourceStage = 'scf'
            RequiredNonEmptyFiles = @('OUTCAR', 'POSCAR', 'CHGCAR')
            MissingFilesMessage = 'SCF OUTCAR, POSCAR, or CHGCAR is missing: $source_dir'
            RequiredTextChecks = @(
                @{ File='OUTCAR'; MatchMode='Fixed'; Pattern='General timing and accounting informations for this job'; Message='SCF OUTCAR lacks the normal timing footer' }
            )
            ForbiddenRegexChecks = @(
                @{ Files=@('slurm-*.err', 'OUTCAR'); Pattern='MPI_Abort|VERY BAD NEWS|EDDDAV|BRMIX|internal error'; Message='SCF output contains a fatal marker' }
            )
            CopyFiles = @(
                @{ Source='POSCAR'; Destination='POSCAR' }
                @{ Source='CHGCAR'; Destination='CHGCAR' }
            )
        }
    }

    Submission = @{
        RequiredStages = @('relax', 'scf', 'band')
        DependencyType = 'afterok'
        KillOnInvalidDependencyProbe = '--kill-on-invalid-dep'
        KillOnInvalidDependencyOption = '--kill-on-invalid-dep=yes'
        Smoke = @{
            FatalLaunchRegex = 'MPI_Abort|Unable to run bstrap_proxy|execvp error|No such file or directory|VASP exit code: [1-9]'
            StructureWarningRegex = 'distance between some ions is very small'
            CompletionPattern = 'General timing and accounting informations for this job'
            AllowedInitialStatuses = @('STARTED_OR_QUEUED', 'COMPLETED_EARLY')
        }
    }
}

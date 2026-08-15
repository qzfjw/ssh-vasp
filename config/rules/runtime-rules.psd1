@{
    SchemaVersion = 1

    Common = @{
        RequiredExecutableType = 'ELF 64-bit'
        ForbiddenLddText = @('not found')
        RequiredMpiLddText = @('libmpi', 'libmpifort')
    }

    Servers = @{
        yang = @{
            ExpectedVaspBin = '/home/public/vasp.6.5.1/bin'
            ExpectedVaspExecutable = 'vasp_std'
            ExpectedVaspVersion = '6.5.1'
            ExpectedMpiLauncher = '/home/public/oneapi/mpi/2021.12/bin/mpiexec'
            ExpectedMpiVersionRegex = '2021\.12'
            RequiredLddText = @('/home/public/oneapi/mpi/2021.12')
        }

        lan = @{
            ExpectedVaspBin = '/data/yangjianhui_group/share_group_folder_yangjianhui_group/vasp.6.5.1'
            ExpectedVaspExecutable = 'vasp_std'
            ExpectedVaspVersion = '6.5.1'
            ExpectedMpiLauncher = '/data/industry/oneapi/mpi/2021.15/bin/mpiexec'
            ExpectedMpiVersionRegex = '2021\.15'
            RequiredLddText = @('/data/industry/oneapi/mpi/2021.15')
        }
    }
}

@{
    Common = @{
        WorkRoot       = 'vasp_codex'
        VaspExecutable = 'vasp_std'
        MemoryPerCpu   = ''
    }

    Servers = @{
        yang = @{
            DisplayName = 'Yang'
            SshAlias    = 'yang-login'
            HostName    = '172.17.19.200'
            Port        = 22
            Settings    = @{
                SlurmBin     = '/opt/slurm/bin'
                VaspBin      = '/home/public/vasp.6.5.1/bin'
                OneApiSetup  = '/home/public/oneapi/setvars.sh'
                Partition    = 'cluster'
                MpiLauncher  = '/home/public/oneapi/mpi/2021.12/bin/mpiexec'
                PawPotentialRoot = '/home/shared/potpaw_PBE54'
            }
        }
        lan = @{
            DisplayName = 'Lan'
            SshAlias    = 'lan-login'
            HostName    = '192.168.22.201'
            Port        = 22
            Settings    = @{
                SlurmBin     = '/usr/bin'
                VaspBin      = '/data/yangjianhui_group/share_group_folder_yangjianhui_group/vasp.6.5.1'
                OneApiSetup  = '/data/industry/oneapi/setvars.sh'
                Partition    = 'cu'
                MpiLauncher  = '/data/industry/oneapi/mpi/2021.15/bin/mpiexec'
                MemoryPerCpu = '7G'
                PawPotentialRoot = '/data/yangjianhui_group/share_group_folder_yangjianhui_group/potpaw_PBE54'
            }
        }
    }
}

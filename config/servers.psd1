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
            HostName    = 'CHANGE_ME_YANG_HOST'
            Port        = 22
            Settings    = @{
                SlurmBin     = '/opt/slurm/bin'
                VaspBin      = '/home/public/vasp.6.5.1/bin'
                OneApiSetup  = '/home/public/oneapi/setvars.sh'
                Partition    = 'cluster'
                MpiLauncher  = '/home/public/oneapi/mpi/2021.12/bin/mpiexec'
            }
        }
        lan = @{
            DisplayName = 'Lan'
            SshAlias    = 'lan-login'
            HostName    = 'CHANGE_ME_LAN_HOST'
            Port        = 22
            Settings    = @{
                SlurmBin     = '/usr/bin'
                VaspBin      = '/data/yangjianhui_group/share_group_folder_yangjianhui_group/vasp.6.5.1'
                OneApiSetup  = '/data/industry/oneapi/setvars.sh'
                Partition    = 'cu'
                MpiLauncher  = '/data/industry/oneapi/mpi/2021.15/bin/mpiexec'
                MemoryPerCpu = '7G'
            }
        }
    }
}

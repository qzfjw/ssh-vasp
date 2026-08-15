# Yang/Lan 服务器配置与 SSH 模式

## 服务器定义

组内公共服务器配置保存在 `config/servers.psd1`；存在 `config/servers.local.psd1` 时脚本优先加载本地覆盖：

| 选择名 | SSH 别名 | 工作目录 |
|---|---|---|
| `yang` | `yang-login` | `~/vasp_codex/` |
| `lan` | `lan-login` | `~/vasp_codex/` |

用户名、主机地址、端口和私钥以本机 `~/.ssh/config` 与 `ssh -G <alias>` 的实时解析结果为准。不要在 Skill 中硬编码实际用户名；Skill 只保存 SSH 别名，也不保存密码或私钥。

配置采用两层合并：

1. `Common` 保存真正相同的默认值。
2. `Servers.<name>.Settings` 保存该服务器的值，并覆盖同名默认值。

当前已验证配置：

| 配置项 | Yang | Lan |
|---|---|---|
| `SlurmBin` | `/opt/slurm/bin` | `/usr/bin` |
| `VaspBin` | `/home/public/vasp.6.5.1/bin` | `/data/yangjianhui_group/share_group_folder_yangjianhui_group/vasp.6.5.1` |
| `OneApiSetup` | `/home/public/oneapi/setvars.sh` | `/data/industry/oneapi/setvars.sh` |
| `Partition` | `cluster` | `cu` |
| `MpiLauncher` | `/home/public/oneapi/mpi/2021.12/bin/mpiexec` | `/data/industry/oneapi/mpi/2021.15/bin/mpiexec` |
| `VaspExecutable` | `vasp_std`（继承 `Common`） | `vasp_std`（继承 `Common`） |
| `MemoryPerCpu` | 空，不生成内存指令 | `7G` |

修改原则：相同值放进 `Common`；只有某台服务器不同的值放进该服务器的 `Settings`。选择脚本会先复制 `Common`，再用 `Settings` 覆盖。不要再把这些路径写死到 SLURM 模板或 SSH 命令中。

## 强制选择服务器

每次新任务必须选择服务器，不设置默认值：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/select_server.ps1" -Server yang
```

或：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/select_server.ps1" -Server lan
```

脚本接受选择名或 SSH 别名，例如 `yang`、`yang-login`、`lan`、`lan-login`。成功后在当前 PowerShell 进程设置：

- `$env:VASP_SERVER_KEY`
- `$env:VASP_SERVER_NAME`
- `$env:VASP_SSH_ALIAS`
- `$env:VASP_WORK_ROOT`
- `$env:VASP_SLURM_BIN`
- `$env:VASP_VASP_BIN`
- `$env:VASP_ONEAPI_SETUP`
- `$env:VASP_PARTITION`
- `$env:VASP_MPI_LAUNCHER`
- `$env:VASP_EXECUTABLE`
- `$env:VASP_MEMORY_PER_CPU`

选择脚本和后续 SSH/SCP 命令必须位于同一次 PowerShell 调用中。每次产生副作用前都要报告 `$env:VASP_SSH_ALIAS`，避免发错服务器。

## 本地连接预检

在不连接服务器的情况下检查 SSH 解析：

```powershell
ssh -G $env:VASP_SSH_ALIAS | Select-String -Pattern '^(hostname|user|port|identityfile) '
```

实际连接、资源查询和用户队列检查：

```powershell
$sshAlias = $env:VASP_SSH_ALIAS
$slurmBin = $env:VASP_SLURM_BIN
$remoteCommand = "echo user=`$(id -un) host=`$(hostname); $slurmBin/sinfo -N -o '%N %T %C %m'; $slurmBin/squeue -u `$(id -un)"
ssh -o ConnectTimeout=10 $sshAlias $remoteCommand
```

确认远程输出的用户和主机与所选服务器一致后，才能创建目录或提交任务。

## 连接策略

每个逻辑事务合并为一次 SSH 调用，不为每个 `grep`、`tail` 或 `test` 单独连接，也不依赖交互式会话工具。

遇到 `banner exchange timeout` 时停止快速重连，等待后有限重试。对提交或取消命令，重试前必须先在同一服务器查询状态，防止重复提交或误取消。

## 安全创建任务目录

Codex 必须先验证 `job_name`，再将其插入命令。以下示例使用当前已选服务器：

```powershell
$workRoot = $env:VASP_WORK_ROOT
$remoteCommand = 'set -eu; job="my_relax"; dir="$HOME/{0}/$job"; test ! -e "$dir"; mkdir -p "$dir"; printf "%s\n" "$dir"' -f $workRoot
ssh $env:VASP_SSH_ALIAS $remoteCommand
```

目录已存在时停止并报告服务器与路径。不要自动删除、清空或覆盖远程目录。

## 上传与提交

上传使用当前已选服务器：

```powershell
$remoteDestination = "$($env:VASP_SSH_ALIAS):~/$($env:VASP_WORK_ROOT)/my_relax/"
scp ./INCAR ./POSCAR ./KPOINTS ./POTCAR ./run_vasp.slurm $remoteDestination
```

远程验证和提交合并为一次 SSH 调用：

```powershell
$sshAlias = $env:VASP_SSH_ALIAS
$slurmBin = $env:VASP_SLURM_BIN
$workRoot = $env:VASP_WORK_ROOT
ssh $sshAlias "cd ~/$workRoot/my_relax && test -s INCAR && test -s POSCAR && test -s KPOINTS && test -s POTCAR && test -s run_vasp.slurm && $slurmBin/sbatch --parsable run_vasp.slurm"
```

只有 `sbatch --parsable` 返回 Job ID 时才能报告提交成功。报告格式必须包含服务器，例如：`lan-login / Job 12345`。

## 查询作业

先选择任务所属服务器，再查询。不能用 Job ID 自动猜测服务器：

```powershell
$sshAlias = $env:VASP_SSH_ALIAS
$slurmBin = $env:VASP_SLURM_BIN
$workRoot = $env:VASP_WORK_ROOT
$jobId = '12345'
ssh $sshAlias "$slurmBin/squeue -j $jobId -o %.18i,%.20j,%.8T,%.10M,%.6D,%R; cd ~/$workRoot/my_relax; tail -n 40 slurm-$jobId.err 2>/dev/null || true; tail -n 20 OSZICAR 2>/dev/null || true"
```

## 取消作业

Job ID 在不同服务器上可能重复，因此取消时必须同时确认服务器：

```powershell
$slurmBin = $env:VASP_SLURM_BIN
ssh $env:VASP_SSH_ALIAS "$slurmBin/squeue -j 12345 -o %.18i,%.20j,%.8T,%.10M,%R"
```

用户确认“服务器别名 + Job ID”后，才能在同一服务器执行：

```powershell
$slurmBin = $env:VASP_SLURM_BIN
ssh $env:VASP_SSH_ALIAS "$slurmBin/scancel 12345"
```

## 计算启动器

SLURM 模板使用所选服务器的 `OneApiSetup`、`MpiLauncher`、`VaspBin` 和 `VaspExecutable`，最终执行：

```bash
"$mpi_launcher" -np "$SLURM_NTASKS" "$vasp_executable"
```

除非管理员或已验证作业明确要求，不要自行改成 `srun`、更换 MPI 实现或修改 oneAPI 初始化顺序。

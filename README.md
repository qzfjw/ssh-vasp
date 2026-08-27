# Yang/Lan VASP 作业操作指南

本 Skill 通过 Windows OpenSSH 管理 Yang 和 Lan 两台服务器上的 VASP/SLURM 作业。

每次操作由用户显式选择服务器；两台服务器可使用不同的远程用户名，用户名、私钥和免密登录信息保存在各用户自己的 SSH 配置中。

## 安装

仓库根目录就是一个完整的 Codex skill。

### 推荐：Codex 对话安装

在 Codex 中新建任务并发送：

```text
请使用 $skill-installer 从 GitHub 仓库 qzfjw/ssh-vasp 安装 Skill。
仓库根目录就是 Skill 目录，安装名称为 fang_ssh_skill。
安装完成后检查 SKILL.md 是否可识别，并告诉我下一步如何配置 Yang/Lan SSH。
```

安装完成后，新建一个 Codex 任务并发送：

```text
使用 $fang-ssh-skill 帮我配置 yang-login 和 lan-login 的 SSH 免密登录。
```

只使用其中一台服务器时，可以在第二条消息中只指定 `yang-login` 或 `lan-login`。

### 备用：PowerShell 安装

也可以直接调用 Codex 自带的 skill 安装器：

```powershell
$Installer = Join-Path $HOME '.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py'
python $Installer --repo qzfjw/ssh-vasp --path . --name fang_ssh_skill
```

若目标目录已经存在，请先备份现有 skill；安装器不会覆盖已有目录。

### 备用：Git 克隆

需要通过 `git pull` 持续更新时，可以直接克隆：

```powershell
git clone https://github.com/qzfjw/ssh-vasp.git "$HOME/.codex/skills/fang_ssh_skill"
```

后续更新：

```powershell
git -C "$HOME/.codex/skills/fang_ssh_skill" pull --ff-only
```

安装或更新后，请在下一次 Codex 对话中使用该 skill。

## 首次配置

公开仓库已按组内约定预置 Yang/Lan 服务器地址，但不保存 API Key、用户名或私钥。安装后按需创建本机配置：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
Copy-Item "$SkillRoot/config/local.example.psd1" "$SkillRoot/config/local.psd1"

# 可选：只有需要覆盖公共服务器配置时才创建
Copy-Item "$SkillRoot/config/servers.psd1" "$SkillRoot/config/servers.local.psd1"
```

然后：

1. Yang/Lan 主机地址已写入 `config/servers.psd1`；仅当服务器地址或运行路径与公共配置不同时，才创建并修改 `config/servers.local.psd1`。
2. 仅在需要 Materials Project 时，在 `config/local.psd1` 中填写个人 API Key。
3. 运行 `scripts/setup_ssh_hosts.ps1` 配置个人 SSH 用户名和密钥。
4. 运行 `scripts/check_ssh_hosts.ps1` 与 `scripts/check_vasp_runtime.ps1` 验证环境。

`config/servers.local.psd1` 和 `config/local.psd1` 已被 `.gitignore` 排除，不得提交到仓库。

更新已有安装时，如果已经创建 `config/servers.local.psd1`，需将公共配置中新增加的必需字段同步到该文件；例如本次新增的 `PawPotentialRoot`。选择脚本会在字段缺失时停止并报告，不会猜测势库路径。

## 1. 功能与目录

- 配置 SSH 别名、专用密钥和免密登录。
- 在 `yang-login` 或 `lan-login` 之间显式选择目标服务器。
- 按服务器配置生成 `run_vasp.slurm`。
- 检查输入文件、上传、提交、查询、分析和安全取消作业。
- 从本机配置加载 Materials Project API Key。

Skill 推荐安装位置：

```text
%USERPROFILE%\.codex\skills\fang_ssh_skill
```

主要文件：

| 文件 | 用途 |
|---|---|
| `config/servers.psd1` | 组内共享的 Yang/Lan 服务器地址与运行环境配置 |
| `config/servers.local.psd1` | 本机服务器地址和路径覆盖；不入库 |
| `config/local.example.psd1` | Materials Project 本机配置模板 |
| `config/local.psd1` | 本机 Materials Project API Key；不入库 |
| `config/rules/*.psd1` | 输入、工作流、运行时和下载经验规则 |
| `config/rules/parameters/*.psd1` | INCAR、KPOINTS 和任务 Profile 参数经验 |
| `config/rules/analysis-rules.json` | 能带分析与绘图参数 |
| `config/rules/incidents/` | 已知问题、症状和预防措施 |
| `scripts/lib/VaspRuleEngine.psm1` | 规则 Schema 校验和递归覆盖合并 |
| `scripts/resolve_vasp_parameters.ps1` | 按 Relax、SCF、DOS、Band、Phonon 等任务解析推荐 INCAR/KPOINTS 参数 |
| `references/rule-system-tutorial.md` | 经验、解释、算法和安全边界的工作原理、使用和维护教程 |
| `scripts/setup_ssh_hosts.ps1` | 首次配置 SSH 别名、密钥和免密登录 |
| `scripts/check_ssh_hosts.ps1` | 检查 SSH 解析和无人值守登录 |
| `scripts/check_vasp_runtime.ps1` | 提交前检查 VASP 可执行文件、MPI 动态库和 oneAPI/MPI 版本 |
| `scripts/select_server.ps1` | 选择服务器并加载环境变量 |
| `scripts/render_slurm.ps1` | 生成服务器对应的 SLURM 脚本 |
| `scripts/preflight_job.ps1` | 检查输入、POTCAR 顺序和周期性最近邻距离 |
| `scripts/render_band_chain.ps1` | 生成 Relax→SCF→Band 脚本、门控和清单 |
| `scripts/submit_vasp_chain.ps1` | 预检、上传、依赖提交和启动冒烟检查 |
| `scripts/download_vasp_results.ps1` | 安全下载一个或多个远程结果目录 |
| `scripts/analyze_band.cjs` | 解析带隙并输出 CSV、JSON 和 SVG |
| `scripts/load_mp_config.ps1` | 加载 Materials Project Key |

### 1.1 规则架构

可变化的 VASP 经验集中保存在 `config/rules/`，执行脚本只保留解析、SSH/SLURM 操作和不可绕过的安全边界：

```text
config/rules/
├─ input-rules.psd1                 现有文件完整性、几何和计算类型检查
├─ runtime-rules.psd1               VASP、MPI、oneAPI 和 SLURM 运行时兼容性
├─ workflow-rules.psd1              Relax→SCF→Band 阶段门控和提交冒烟检查
├─ artifact-rules.psd1              下载结果清单
├─ analysis-rules.json              能带分析与绘图参数
├─ incidents/                       历史问题记录
└─ parameters/
   ├─ incar-rules.psd1              INCAR 参数经验
   ├─ kpoints-rules.psd1            KPOINTS 网格经验
   └─ profiles.psd1                 Relax、SCF、DOS、Band、Phonon 等组合

references/
└─ vasp-parameter-rules.md          参数规则的原理、适用范围和例外说明

scripts/
└─ resolve_vasp_parameters.ps1      按任务解析并展示最终参数建议
```

`input-rules.psd1` 与 `parameters/*.psd1` 分工不同：前者用于提交前判断“输入是否明显有问题”，例如缺文件、POTCAR 顺序不匹配、Band 计算没有 `ICHARG=11`；后者用于生成或审阅参数建议，例如普通结构优化的 `NSW=500`、`ISIF=2`，3d 元素时 `LMAXMIX=4`，以及 KPOINTS 各分量与晶格长度乘积不小于 25 的经验。

三个参数规则文件的职责是：

- `incar-rules.psd1` 保存单个 INCAR 参数、任务参数组和元素相关条件规则。例如 Relax 参数组、SCF 参数组，以及含 3d 或 4f/5f 元素时调整 `LMAXMIX`。
- `kpoints-rules.psd1` 保存 KPOINTS 生成策略。例如默认使用 Gamma-centered 网格、普通任务使用 `N_i * L_i >= 25 Angstrom`，SCF/DOS 可使用更密的目标。
- `profiles.psd1` 保存任务组合。Codex 或脚本看到 `Relax`、`Scf`、`Dos`、`Band`、`Phonon` 时，先从这里找到对应的 INCAR profile 和 KPOINTS profile，再加载前两个文件得到最终建议。

Codex 使用这些规则时遵循“先加载 profile，再合并参数，再交给用户确认”的流程。`scripts/resolve_vasp_parameters.ps1` 是这个流程的可执行入口，例如：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" -Task Relax -PoscarPath ./POSCAR
```

该脚本会读取 `config/rules/parameters/profiles.psd1` 选择任务组合，再读取 `incar-rules.psd1` 和 `kpoints-rules.psd1` 输出推荐 INCAR 参数与 KPOINTS 网格。它提供的是经验建议，不替代材料体系所需的收敛性测试、磁矩设置、DFT+U、SOC、vdW 或赝势版本选择。

PowerShell 规则通过 `scripts/lib/VaspRuleEngine.psm1` 加载，支持任务级覆盖文件。优先级为“技能默认规则 < 服务器配置 < 项目覆盖文件 < 用户显式参数”。完整扩展流程见 `references/rule-extension.md`。

建议在 PowerShell 中先定义：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
```

## 2. 当前服务器配置

公共配置：

```powershell
Common = @{
    WorkRoot       = 'vasp_codex'
    VaspExecutable = 'vasp_std'
    MemoryPerCpu   = ''
}
```

差异配置：

| 配置项 | Yang | Lan |
|---|---|---|
| 选择名 | `yang` | `lan` |
| SSH 别名 | `yang-login` | `lan-login` |
| 主机地址 | `172.17.19.200` | `192.168.22.201` |
| `SlurmBin` | `/opt/slurm/bin` | `/usr/bin` |
| `VaspBin` | `/home/public/vasp.6.5.1/bin` | `/data/yangjianhui_group/share_group_folder_yangjianhui_group/vasp.6.5.1` |
| `OneApiSetup` | `/home/public/oneapi/setvars.sh` | `/data/industry/oneapi/setvars.sh` |
| `Partition` | `cluster` | `cu` |
| `MpiLauncher` | `/home/public/oneapi/mpi/2021.12/bin/mpiexec` | `/data/industry/oneapi/mpi/2021.15/bin/mpiexec` |
| `PawPotentialRoot` | `/home/shared/potpaw_PBE54` | `/data/yangjianhui_group/share_group_folder_yangjianhui_group/potpaw_PBE54` |
| `VaspExecutable` | `vasp_std` | `vasp_std` |
| `MemoryPerCpu` | 空，不生成内存指令 | `7G` |
| 远程任务根目录 | `~/vasp_codex` | `~/vasp_codex` |

远程用户名和私钥不写入 `servers.psd1`，而由 `%USERPROFILE%\.ssh\config` 管理。因此，同一用户可以分别为 Yang 和 Lan 填写不同的登录名。

## 3. 使用前准备

检查 Windows OpenSSH：

```powershell
Get-Command ssh, scp, ssh-keygen
```

三个命令都应返回可执行文件路径。若不存在，请先安装 Windows **OpenSSH 客户端**。同时确认本机已连接到可以访问服务器的内网或 VPN。

## 4. 首次配置 SSH

### 4.1 交互式配置

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" -Server yang
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" -Server lan
```

向导会分别询问两台服务器的远程用户名，并执行：

1. 默认使用 `~/.ssh/id_ed25519_yang` 或 `~/.ssh/id_ed25519_lan`。
2. 私钥不存在时询问是否生成 ED25519 密钥。
3. 首次安装公钥时，由原生 `ssh` 提示输入一次服务器密码。
4. 修改 SSH config 前创建带时间戳的备份。
5. 只更新带 `BEGIN/END CODEX VASP` 标记的托管配置块。
6. 使用 `BatchMode=yes` 验证真正的无人值守登录。

密码只交给原生 SSH，不要写入配置文件、脚本参数或聊天内容。

### 4.2 指定用户名并生成密钥

```powershell
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" `
  -Server yang `
  -RemoteUser '<Yang服务器用户名>' `
  -GenerateKey

& "$SkillRoot/scripts/setup_ssh_hosts.ps1" `
  -Server lan `
  -RemoteUser '<Lan服务器用户名>' `
  -GenerateKey
```

如果明确接受无口令私钥的风险，可增加 `-NoPassphrase`。更推荐为私钥设置口令并使用 `ssh-agent`，但后续 `BatchMode=yes` 检查必须能够通过。

复用已有私钥：

```powershell
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" `
  -Server lan `
  -RemoteUser '<Lan服务器用户名>' `
  -IdentityFile "$HOME/.ssh/id_ed25519"
```

若已有同名但不受 Skill 管理的 `Host yang-login` 或 `Host lan-login` 配置块，向导不会静默覆盖，必须由用户确认接管。

### 4.3 检查免密登录

```powershell
& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server all
```

单独检查：

```powershell
& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server yang
& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server lan
```

检查内容包括 SSH 别名、主机地址、用户名、私钥文件和 `BatchMode=yes` 登录。检查失败时不要继续自动提交。

## 5. 选择服务器

```powershell
# 选择 Yang
& "$SkillRoot/scripts/select_server.ps1" -Server yang

# 或选择 Lan
& "$SkillRoot/scripts/select_server.ps1" -Server lan
```

选择成功后，当前 PowerShell 进程会获得：

```text
VASP_SERVER_KEY
VASP_SERVER_NAME
VASP_SSH_ALIAS
VASP_WORK_ROOT
VASP_SLURM_BIN
VASP_VASP_BIN
VASP_ONEAPI_SETUP
VASP_PARTITION
VASP_MPI_LAUNCHER
VASP_PAW_POTENTIAL_ROOT
VASP_EXECUTABLE
VASP_MEMORY_PER_CPU
```

检查当前选择：

```powershell
Get-ChildItem Env:VASP_*
ssh -o BatchMode=yes -o ConnectTimeout=10 $env:VASP_SSH_ALIAS 'echo "user=$USER host=$(hostname)"'
```

> 这些环境变量只属于当前 PowerShell 进程。选择服务器与后续生成、SSH、SCP、提交或查询命令必须在同一个 PowerShell 窗口或同一次脚本调用中执行。新开窗口后需要重新选择服务器。

## 6. Materials Project API Key

Key 保存在本机：

```text
%USERPROFILE%\.codex\skills\fang_ssh_skill\config\local.psd1
```

保持以下格式，不要修改字段名：

```powershell
@{
    MaterialsProjectApiKey = '<在本机填写API Key>'
}
```

使用时通过脚本加载，禁止直接输出 Key：

```powershell
& "$SkillRoot/scripts/load_mp_config.ps1"
python ./download_structure.py
```

加载脚本和 Python 命令必须在同一个 PowerShell 进程中运行。需要安装官方客户端时执行：

```powershell
python -m pip install --upgrade mp-api
```

示例 `download_structure.py`：

```python
from mp_api.client import MPRester

material_id = "mp-149"

with MPRester() as mpr:
    structure = mpr.get_structure_by_material_id(material_id)

structure.to(filename="POSCAR", fmt="poscar")
```

Materials Project 不提供可直接用于 VASP 计算的授权 POTCAR。POTCAR 必须来自用户有权使用的 VASP 势库，并与 POSCAR 元素顺序一致。选择服务器后，PBE 5.4 PAW 势库根目录位于 `$env:VASP_PAW_POTENTIAL_ROOT`；具体使用普通、`_pv` 或 `_sv` 等哪个势目录必须明确，不得猜测。

## 7. 准备输入文件

本地任务目录至少包含：

```text
INCAR
POSCAR
KPOINTS
POTCAR
```

任务名只允许字母、数字、点、下划线和连字符：

```text
^[A-Za-z0-9._-]+$
```

提交前确认：

- POSCAR 元素顺序与 POTCAR 拼接顺序一致。
- 指定相和空间群正确，周期性最近邻距离合理。
- INCAR 与 relax、static 或其他计算类型匹配。
- KPOINTS、核数和时限符合计算要求。
- POTCAR 来自用户获授权的势库。
- 生成 POTCAR 时从 `$env:VASP_PAW_POTENTIAL_ROOT` 读取，并按 POSCAR 元素顺序拼接已明确选择的势目录。

## 8. 生成 SLURM 脚本

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
$JobName = 'my_relax'

& "$SkillRoot/scripts/select_server.ps1" -Server yang

& "$SkillRoot/scripts/render_slurm.ps1" `
  -JobName $JobName `
  -Cores 48 `
  -Walltime '24:00:00' `
  -Partition $env:VASP_PARTITION `
  -SlurmBin $env:VASP_SLURM_BIN `
  -VaspBin $env:VASP_VASP_BIN `
  -OneApiSetup $env:VASP_ONEAPI_SETUP `
  -MpiLauncher $env:VASP_MPI_LAUNCHER `
  -VaspExecutable $env:VASP_EXECUTABLE `
  -MemoryPerCpu $env:VASP_MEMORY_PER_CPU `
  -OutputPath './run_vasp.slurm'
```

选择 Lan 时把 `-Server yang` 改为 `-Server lan`，服务器差异会从环境变量自动传入。

目标文件已存在时脚本默认停止。只有确认可以覆盖后才增加 `-Force`。

## 9. 提交前检查

```powershell
& "$SkillRoot/scripts/preflight_job.ps1" `
  -InputDirectory '.' `
  -JobName $JobName `
  -CalculationType Relax
```

脚本检查：

- 四个 VASP 输入文件存在且非空。
- `run_vasp.slurm` 存在、使用 LF 换行且无残留模板变量。
- POSCAR 具备基本格式，并能解析 Direct、Cartesian 和 Selective Dynamics。
- POSCAR 物种顺序与 POTCAR 的 `TITEL` 基础元素逐项一致。
- 计算周期性最近邻距离，并基于绝对距离和共价半径比例拒绝明显重叠结构。
- Band 类型检查 `ICHARG=11`、Line-mode KPOINTS 和 `NSW=0`。
- 输出五个文件的 SHA256。

预检通过不代表物理参数一定正确，INCAR、KPOINTS 和赝势类型仍需用户确认。

## 10. 完整提交示例

在包含四个 VASP 输入文件的目录中执行。将 `$Server` 设置为 `yang` 或 `lan`：

```powershell
$ErrorActionPreference = 'Stop'
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
$Server = 'yang'
$JobName = 'my_relax'
$Cores = 48
$Walltime = '24:00:00'

& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server $Server
& "$SkillRoot/scripts/select_server.ps1" -Server $Server

& "$SkillRoot/scripts/render_slurm.ps1" `
  -JobName $JobName `
  -Cores $Cores `
  -Walltime $Walltime `
  -Partition $env:VASP_PARTITION `
  -SlurmBin $env:VASP_SLURM_BIN `
  -VaspBin $env:VASP_VASP_BIN `
  -OneApiSetup $env:VASP_ONEAPI_SETUP `
  -MpiLauncher $env:VASP_MPI_LAUNCHER `
  -VaspExecutable $env:VASP_EXECUTABLE `
  -MemoryPerCpu $env:VASP_MEMORY_PER_CPU `
  -OutputPath './run_vasp.slurm'

& "$SkillRoot/scripts/preflight_job.ps1" -InputDirectory '.' -JobName $JobName -CalculationType Relax

$SshAlias = $env:VASP_SSH_ALIAS
$WorkRoot = $env:VASP_WORK_ROOT
$SlurmBin = $env:VASP_SLURM_BIN

$CreateCommand = 'set -eu; job="{0}"; dir="$HOME/{1}/$job"; test ! -e "$dir"; mkdir -p "$dir"; printf "%s\n" "$dir"' -f $JobName, $WorkRoot
ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias $CreateCommand
if ($LASTEXITCODE -ne 0) {
    throw "Remote directory creation failed or directory already exists: $SshAlias / ~/$WorkRoot/$JobName"
}

$RemoteDestination = '{0}:~/{1}/{2}/' -f $SshAlias, $WorkRoot, $JobName
scp ./INCAR ./POSCAR ./KPOINTS ./POTCAR ./run_vasp.slurm $RemoteDestination
if ($LASTEXITCODE -ne 0) {
    throw "File upload failed: $SshAlias / ~/$WorkRoot/$JobName"
}

$SubmitCommand = 'cd "$HOME/{0}/{1}" && test -s INCAR && test -s POSCAR && test -s KPOINTS && test -s POTCAR && test -s run_vasp.slurm && {2}/sbatch --parsable run_vasp.slurm' -f $WorkRoot, $JobName, $SlurmBin
$SubmitResult = ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias $SubmitCommand
if ($LASTEXITCODE -ne 0) {
    throw "Remote validation or sbatch failed: $SshAlias / ~/$WorkRoot/$JobName"
}

$JobId = (($SubmitResult -join '').Trim() -split ';')[0]
if ($JobId -notmatch '^\d+$') {
    throw "sbatch did not return a valid Job ID: $SubmitResult"
}

[pscustomobject]@{
    Server    = $SshAlias
    JobId     = $JobId
    Directory = "~/$WorkRoot/$JobName"
    Cores     = $Cores
    Walltime  = $Walltime
    Vasp      = $env:VASP_EXECUTABLE
}
```

远程目录已经存在时必须停止。不要自动删除、清空或复用旧目录。只有 `sbatch --parsable` 返回有效 Job ID 才能认为提交成功。

记录任务时必须同时保存服务器和 Job ID，例如 `lan-login / Job 12345`，因为两台服务器可能出现相同的 Job ID。

## 11. 查询作业

每次查询都先选择服务器，并在同一个 PowerShell 进程中执行后续 SSH 命令。

### 11.1 查询当前用户的全部作业

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server lan
$QueueCommand = '{0}/squeue -u $(id -un) -o "%.18i %.12P %.24j %.2t %.10M %.6D %R"' -f $env:VASP_SLURM_BIN
ssh $env:VASP_SSH_ALIAS $QueueCommand
```

### 11.2 查询服务器上所有用户的作业

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server lan
$QueueCommand = '{0}/squeue -a -o "%.18i %.12P %.24j %.16u %.2t %.10M %.6D %R"' -f $env:VASP_SLURM_BIN
ssh $env:VASP_SSH_ALIAS $QueueCommand
```

将 `lan` 改为 `yang` 即可查询 Yang。能否看到全部用户和分区取决于服务器的 SLURM 权限与集群配置。

### 11.3 查询指定 Job ID

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server yang
$JobId = '12345'
if ($JobId -notmatch '^\d+$') { throw 'JobId must contain digits only.' }

$StatusCommand = '{0}/squeue -j {1} -o "%.18i %.20j %.16u %.8T %.10M %.6D %R"; {0}/sacct -j {1} --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End -n -X' -f $env:VASP_SLURM_BIN, $JobId
ssh $env:VASP_SSH_ALIAS $StatusCommand
```

- `PD`、`CF` 等归为 `QUEUED`。
- `R`、`CG` 等归为 `RUNNING`。
- 作业运行中只能报告当前进度，不能提前声称最终收敛。

## 12. 查看进度与结果

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server yang
$JobName = 'my_relax'
$JobId = '12345'
if ($JobName -notmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid JobName.' }
if ($JobId -notmatch '^\d+$') { throw 'Invalid JobId.' }

$InspectCommand = 'cd "$HOME/{0}/{1}" || exit 1; printf "== queue ==\n"; {2}/squeue -j {3} -o "%.18i %.20j %.8T %.10M %R"; printf "== stderr ==\n"; tail -n 40 "slurm-{3}.err" 2>/dev/null || true; printf "== OSZICAR ==\n"; tail -n 30 OSZICAR 2>/dev/null || true; printf "== OUTCAR end ==\n"; tail -n 30 OUTCAR 2>/dev/null || true; printf "== files ==\n"; ls -l OUTCAR OSZICAR CONTCAR "slurm-{3}.out" "slurm-{3}.err" 2>/dev/null || true' -f $env:VASP_WORK_ROOT, $JobName, $env:VASP_SLURM_BIN, $JobId
ssh $env:VASP_SSH_ALIAS $InspectCommand
```

状态分类：

| 分类 | 判断原则 |
|---|---|
| `QUEUED` | 作业仍在队列且未正式运行 |
| `RUNNING` | 作业正在执行，可读取 OSZICAR 当前进度 |
| `COMPLETED` | 已离开队列，OUTCAR 正常结束，错误日志无致命错误；relax 还需确认离子收敛和非空 CONTCAR |
| `FAILED` | 存在超时、取消、MPI abort、输入缺失、VASP 致命错误或非零退出等证据 |
| `UNKNOWN` | 已离开队列，但输出缺失、截断或证据不足 |

不要仅凭作业不在 `squeue` 中就认定成功，也不要输出完整 OUTCAR。默认只读取必要尾部、能量行、收敛标志和错误摘要。

## 13. 安全取消作业

取消前必须确认服务器、Job ID、作业名和状态。

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server lan
$JobId = '12345'
if ($JobId -notmatch '^\d+$') { throw 'JobId must contain digits only.' }

$CheckCommand = '{0}/squeue -j {1} -o "%.18i %.20j %.16u %.8T %.10M %R"' -f $env:VASP_SLURM_BIN, $JobId
ssh $env:VASP_SSH_ALIAS $CheckCommand
```

用户明确确认“取消 `lan-login / Job 12345`”后再运行：

```powershell
$CancelCommand = '{0}/scancel {1} && {0}/squeue -j {1} -o "%.18i %.20j %.16u %.8T %.10M %R"' -f $env:VASP_SLURM_BIN, $JobId
ssh $env:VASP_SSH_ALIAS $CancelCommand
```

不要仅凭 Job ID 猜测服务器，也不要批量取消或取消其他用户的任务。

## 14. Relax、Static 与 Band 链

### 14.1 Relax 转 Static

1. 确认 relax 所属服务器和 Job ID。
2. 确认作业正常结束，而不是仅仅离开队列。
3. 检查 `CONTCAR` 存在且非空。
4. 默认在同一服务器创建新的 static 目录，不覆盖 relax 目录。
5. 将 `CONTCAR` 复制为新任务的 `POSCAR`。
6. 复制并核对 `KPOINTS`、`POTCAR`，使用 static 专用 INCAR。
7. 重新生成 SLURM 脚本、运行预检、上传并提交。

跨服务器迁移必须由用户明确要求，并重新验证目标服务器的 SSH、路径、分区和输入文件。

### 14.2 Relax→SCF→Band

本地根目录包含 `relax`、`scf` 和 `band` 三个子目录，每个目录先准备四个 VASP 输入文件：

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server yang

& "$SkillRoot/scripts/render_band_chain.ps1" `
  -RootDirectory './my_band_chain' `
  -RelaxJobName 'my_relax' `
  -ScfJobName 'my_scf' `
  -BandJobName 'my_band' `
  -Cores 48 `
  -Partition $env:VASP_PARTITION `
  -WorkRoot $env:VASP_WORK_ROOT `
  -SlurmBin $env:VASP_SLURM_BIN `
  -VaspBin $env:VASP_VASP_BIN `
  -OneApiSetup $env:VASP_ONEAPI_SETUP `
  -MpiLauncher $env:VASP_MPI_LAUNCHER `
  -VaspExecutable $env:VASP_EXECUTABLE `
  -MemoryPerCpu $env:VASP_MEMORY_PER_CPU

& "$SkillRoot/scripts/submit_vasp_chain.ps1" `
  -Server yang `
  -RootDirectory './my_band_chain'
```

如果希望避免 Relax 启动失败后留下 SCF/Band 阻塞作业，可使用分阶段提交：

```powershell
& "$SkillRoot/scripts/submit_vasp_chain.ps1" `
  -Server lan `
  -RootDirectory './my_band_chain' `
  -StagedSubmit
```

`-StagedSubmit` 会先提交 Relax 并执行启动冒烟检查；只有 Relax 正常启动后才提交带 `afterok` 依赖的 SCF 和 Band。默认模式仍保留一次提交完整依赖链的行为。

提交链在创建远程目录和执行 `sbatch` 之前自动运行 `scripts/check_vasp_runtime.ps1`。检查规则集中在 `config/rules/runtime-rules.psd1`，包括批准的 VASP 版本目录、MPI 启动器、动态库路径和 MPI 版本模式；该检查只执行 `file`、`ldd`、`strings` 和 `mpiexec -version` 等只读探测，不启动 VASP。

- SCF 的 `prepare_stage.sh` 检查 Relax 离子收敛、正常 timing 尾部和非空 CONTCAR，再复制为 POSCAR。
- Band 的 `prepare_stage.sh` 检查 SCF 正常结束和非空 CHGCAR，再复制 POSCAR、CHGCAR。
- 提交使用 `afterok`；服务器支持时自动增加 `--kill-on-invalid-dep=yes`。
- 提交后执行短冒烟检查。发现 MPI bootstrap、`srun` 路径或异常短距离问题时停止，不自动取消或重投。
- 可先使用 `submit_vasp_chain.ps1 -DryRun` 只运行本地校验。

### 14.3 下载与能带分析

```powershell
& "$SkillRoot/scripts/download_vasp_results.ps1" `
  -Server yang `
  -JobName my_relax,my_scf,my_band `
  -OutputDirectory './downloaded_results'

node "$SkillRoot/scripts/analyze_band.cjs" `
  './downloaded_results/my_scf' `
  './downloaded_results/my_band' `
  './band_analysis'
```

下载脚本默认排除 WAVECAR、CHGCAR 等大型文件；需要完整目录时增加 `-IncludeLargeFiles`。分析器当前支持 `ISPIN=1`，输出带隙摘要、CSV 和 SVG，并记录 SOC 是否开启。

## 15. 修改服务器设置

编辑：

```text
%USERPROFILE%\.codex\skills\fang_ssh_skill\config\servers.local.psd1
```

配置采用 `Common` 加服务器 `Settings` 覆盖的两层结构：

- 真正相同的值放在 `Common`。
- 仅某台服务器不同的值放在该服务器的 `Settings`。
- `Settings` 中的同名字段覆盖 `Common`。
- 不要把远程用户名、密码或私钥内容写入该文件。
- 修改后分别运行 `select_server.ps1` 查看合并结果。

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server yang
Get-ChildItem Env:VASP_*

& "$SkillRoot/scripts/select_server.ps1" -Server lan
Get-ChildItem Env:VASP_*
```

远程用户名需要变化时，不修改 `servers.local.psd1`，而是重新运行对应服务器的 `setup_ssh_hosts.ps1` 更新本机 SSH config。

## 16. 常见故障

### 16.1 SSH 检查失败

```powershell
ssh -G yang-login | Select-String -Pattern '^(hostname|user|port|identityfile) '
ssh -o BatchMode=yes -o ConnectTimeout=10 yang-login 'printf CODEX_SSH_READY'
```

- `Could not resolve hostname`：检查 `%USERPROFILE%\.ssh\config` 中是否有正确别名。
- `Permission denied (publickey)`：检查远程用户名、私钥和 `authorized_keys`。
- 私钥带口令且 BatchMode 失败：将密钥加入 `ssh-agent`。
- 连接超时：检查网络、VPN、服务器地址和防火墙。
- `banner exchange timeout`：停止快速并发重试，等待后有限次数重试。

### 16.2 SLURM 路径变化

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server lan
$CheckCommand = 'test -x "{0}/squeue" && test -x "{0}/sbatch" && "{0}/sinfo" -h -o "%P %a %l %D"' -f $env:VASP_SLURM_BIN
ssh $env:VASP_SSH_ALIAS $CheckCommand
```

若路径变化，应修改 `config/servers.local.psd1`，不要在多个命令中分别硬编码新路径。`render_slurm.ps1` 必须接收 `-SlurmBin $env:VASP_SLURM_BIN`，生成的脚本会验证 `<SlurmBin>/srun` 并加入 PATH。

### 16.3 任务目录已存在

不要自动覆盖。先检查旧目录和作业记录，再使用新任务名、创建独立续算目录，或由用户明确决定如何处理。

### 16.4 提交后没有获得 Job ID

不要立即重复运行 `sbatch`。先在同一服务器按用户名、任务名和提交时间查询 `squeue`/`sacct`，确认是否已经提交，避免重复作业。

### 16.5 MPI bootstrap 或 `srun` 失败

若 stderr 包含 `Unable to run bstrap_proxy`、`execvp error` 或找不到 `srun`，检查 `VASP_SLURM_BIN`、生成脚本中的 `slurm_bin` 和 PATH。不要在登录节点运行 VASP 测试；修复后使用新目录，并在重新提交前获得确认。

### 16.6 `DependencyNeverSatisfied`

确认上游作业状态和下游 Job ID。不得自动取消依赖作业；展示服务器与 Job ID，获得用户确认后执行 `scancel`。服务器支持时优先使用 `--kill-on-invalid-dep=yes`。

## 17. 安全规则与最短清单

- 每次新任务显式选择 `yang` 或 `lan`。
- 提交、查询、取消和结果报告始终标注服务器与 Job ID。
- 不在登录节点直接运行 VASP。
- 不自动覆盖、删除或递归清理远程目录。
- 不自动重复提交状态不明的任务。
- 不从公共网页或 Materials Project 获取 POTCAR。
- 不保存或回显服务器密码、私钥内容和 Materials Project API Key。
- 覆盖 SLURM 文件、接管 SSH 配置和取消作业前必须明确确认。

首次使用：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" -Server yang
& "$SkillRoot/scripts/setup_ssh_hosts.ps1" -Server lan
& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server all
```

每次提交按顺序执行：选择服务器、生成 SLURM、运行几何与 POTCAR 预检、创建 `~/vasp_codex/<job_name>`、上传文件、运行 `sbatch --parsable`、执行启动冒烟检查，最后保存“服务器 + Job ID + 任务目录”。

---
name: fang-ssh-skill
description: "通过 Windows 本机 OpenSSH 在用户明确选择的 yang-login 或 lan-login 上创建、提交、查询、取消和续接 VASP/SLURM 作业；支持输入与结构校验、Relax→SCF→Band 依赖链、结果下载、带隙解析和能带 SVG 绘图。适用于用户要求在 Yang 或 Lan 服务器上准备、运行、监控、续算或分析 VASP 第一性原理计算；仅当结构获取属于该流程时使用 Materials Project。"
---

# Yang/Lan HPC VASP Workflow

## 核心原则

- 仅从本机通过 OpenSSH 操作 `yang-login` 或 `lan-login`；禁止在登录节点直接运行 VASP 主计算。
- 每个新任务必须由用户明确选择 `yang` 或 `lan`，任务生命周期内保持同一服务器。
- 所有主计算必须通过 `sbatch` 提交；每个逻辑操作尽量合并为一次 SSH 调用。
- 远程任务只允许位于 `~/vasp_codex/<job_name>`，任务名必须匹配 `^[A-Za-z0-9._-]+$`。
- 默认不覆盖现有目录或文件；覆盖、删除、`scancel` 和重新提交前必须展示目标并获得明确确认。
- POTCAR 只能来自用户有权使用的 VASP 势库；不得从公共网页或 Materials Project 下载或猜测 POTCAR。
- Materials Project API Key 只允许保存在 `config/local.psd1`，只能通过 `scripts/load_mp_config.ps1` 加载，不得回显、上传或写入命令参数。

## 资源与脚本

- 用户配置和完整手册：`README.md`
- 服务器差异：`references/hpc-servers.md`
- VASP 状态分类：`references/vasp-validation.md`
- Materials Project：`references/materials-project.md`
- SSH 初始化：`references/ssh-onboarding.md`
- 规则扩展与维护：`references/rule-extension.md`
- 选择服务器：`scripts/select_server.ps1 -Server <yang|lan>`
- 检查 SSH：`scripts/check_ssh_hosts.ps1 -Server <yang|lan>`
- 提交前检查 VASP/MPI 运行时：`scripts/check_vasp_runtime.ps1 -Server <yang|lan>`
- 生成单任务 SLURM：`scripts/render_slurm.ps1`
- 输入与几何预检：`scripts/preflight_job.ps1`
- 生成 Relax→SCF→Band 链：`scripts/render_band_chain.ps1`
- 安全提交三阶段链：`scripts/submit_vasp_chain.ps1`
- 下载结果：`scripts/download_vasp_results.ps1`
- 带隙与 SVG 分析：`scripts/analyze_band.cjs`

## 规则维护

1. 将可变经验写入 `config/rules/`：运行时兼容性、几何阈值、计算类型检查、阶段门控、冒烟特征、下载清单和绘图参数不得散落硬编码在执行脚本中。
2. 将解析算法、远程执行、路径安全、禁止自动覆盖/取消/重提等不可绕过边界保留在脚本中。
3. 使用 `scripts/lib/VaspRuleEngine.psm1` 加载 PowerShell 规则；项目覆盖文件通过各脚本的 `*RulesOverridePath` 参数递归合并。
4. 遇到新问题时先在 `config/rules/incidents/` 新增事故记录，再扩展现有规则；只有现有规则类型无法表达时才修改执行脚本。
5. 新增或修改规则后必须使用历史正常目录和问题夹具回归，运行 PowerShell 语法检查、Node `--check` 和 skill 快速校验。

## 服务器选择

1. 用户明确指定 Yang、`yang` 或 `yang-login` 时选择 `yang`；明确指定 Lan、`lan` 或 `lan-login` 时选择 `lan`。
2. 用户未指定服务器时先询问，不设置默认服务器。
3. 运行 `scripts/select_server.ps1`，后续 SSH、SCP、渲染和提交必须处于同一次 PowerShell 调用或同一进程。
4. 运行 `scripts/check_ssh_hosts.ps1`；检查失败时停止远程操作，不自动修改 SSH 配置。

## 单任务准备与提交

1. 明确服务器、任务名、计算类型、核数、时限、VASP 可执行文件和本地输入目录。
2. 确认 `INCAR`、`POSCAR`、`KPOINTS`、`POTCAR` 来源；对新结构确认化学式、相、空间群、晶格、元素顺序和最近邻距离。
3. 使用当前服务器的 `SlurmBin`、oneAPI、MPI 和 VASP 配置生成脚本：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/select_server.ps1" -Server yang
& "$HOME/.codex/skills/fang_ssh_skill/scripts/render_slurm.ps1" -JobName my_relax -Cores 48 -Walltime 24:00:00 -Partition $env:VASP_PARTITION -SlurmBin $env:VASP_SLURM_BIN -VaspBin $env:VASP_VASP_BIN -OneApiSetup $env:VASP_ONEAPI_SETUP -MpiLauncher $env:VASP_MPI_LAUNCHER -VaspExecutable $env:VASP_EXECUTABLE -MemoryPerCpu $env:VASP_MEMORY_PER_CPU -OutputPath ./run_vasp.slurm
& "$HOME/.codex/skills/fang_ssh_skill/scripts/preflight_job.ps1" -InputDirectory . -JobName my_relax -CalculationType Relax
```

4. 预检必须通过文件、LF 换行、模板变量、POSCAR/POTCAR 物种顺序和周期性最近邻检查。不得用 `-SkipGeometryCheck` 静默绕过失败；仅在用户明确接受特殊结构时使用并报告。
5. 用一次 SSH 调用查询 `sinfo` 并确认远程目录不存在；存在时停止。
6. 创建目录后上传输入和 SLURM 文件；远程再次检查非空和 `bash -n`，再执行 `sbatch --parsable`。
7. 只有获得纯数字 Job ID 后才能报告提交成功。
8. 提交后进行短时间冒烟检查：查询 `squeue`，读取 SLURM stderr/stdout，确认无 MPI bootstrap、缺失 `srun`、可执行文件错误或原子间距过短警告。
9. 冒烟检查失败时不得自动取消或重新提交；展示服务器、Job ID、错误和建议目标，获取用户确认。

## Relax→SCF→Band 链

1. 本地根目录必须包含 `relax`、`scf`、`band` 三个子目录，每个目录包含四个 VASP 输入文件。
2. Band 计算使用独立 SCF 电荷密度，通常设置 `ICHARG=11` 和 Line-mode KPOINTS；明确记录是否启用 SOC、磁性、DFT+U 或混合泛函。
3. 先选择服务器，再生成链：

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/select_server.ps1" -Server yang
& "$HOME/.codex/skills/fang_ssh_skill/scripts/render_band_chain.ps1" -RootDirectory ./my_band_chain -RelaxJobName my_relax -ScfJobName my_scf -BandJobName my_band -Cores 48 -Partition $env:VASP_PARTITION -WorkRoot $env:VASP_WORK_ROOT -SlurmBin $env:VASP_SLURM_BIN -VaspBin $env:VASP_VASP_BIN -OneApiSetup $env:VASP_ONEAPI_SETUP -MpiLauncher $env:VASP_MPI_LAUNCHER -VaspExecutable $env:VASP_EXECUTABLE -MemoryPerCpu $env:VASP_MEMORY_PER_CPU
& "$HOME/.codex/skills/fang_ssh_skill/scripts/submit_vasp_chain.ps1" -Server yang -RootDirectory ./my_band_chain
```

4. 生成器为 SCF 创建运行时门控：只有 Relax 包含离子收敛标志、正常 timing 尾部和非空 CONTCAR 时才复制为 POSCAR。
5. 生成器为 Band 创建运行时门控：只有 SCF 正常结束且 POSCAR、CHGCAR 非空时才继续。
6. 提交器使用 `afterok` 依赖；服务器支持时使用 `--kill-on-invalid-dep=yes`。若出现 `DependencyNeverSatisfied`，报告阻塞链并在用户确认后取消下游 Job ID。
7. 提交前运行 `scripts/check_vasp_runtime.ps1`：检查配置中的 VASP 路径、ELF 类型、动态库、oneAPI 和 MPI 版本；检查失败时不得创建远程目录或提交作业。
8. Lan 或运行时环境不确定时，使用 `scripts/submit_vasp_chain.ps1 -StagedSubmit`：先提交 Relax 并确认其启动冒烟状态为 `STARTED_OR_QUEUED` 或 `COMPLETED_EARLY`，再提交 SCF 和 Band，避免启动失败时产生阻塞下游作业。

## 查询与状态分类

1. 先确认任务服务器，不得凭 Job ID 猜测服务器。
2. 优先查询 `squeue`，并在一次 SSH 调用中获取队列状态、SLURM 输出和必要的 VASP 输出尾部。
3. 作业仍在队列时分类为 `QUEUED` 或 `RUNNING`，不得提前声称收敛。
4. 作业离开队列后按 `references/vasp-validation.md` 分类为 `COMPLETED`、`FAILED` 或 `UNKNOWN`。
5. 不得仅凭“已不在队列”、单个 `reached required accuracy` 或单个错误关键词作结论。
6. `ZBRENT` 只有在未正常结束、退出码非零或伴随明确失败时才作为失败证据；若后续成功 bracket、达到精度且存在正常尾部，不判失败。

## 取消和重新提交

1. 明确服务器并验证 Job ID 为纯数字。
2. 在该服务器执行 `squeue -j <job_id>`，展示名称、状态、运行时间和节点。
3. 明确询问用户是否取消“该服务器上的该 Job ID”；用户确认后执行 `scancel` 并复查。
4. 失败作业的重新提交必须使用新任务名和新目录；不得覆盖失败目录。重新提交前展示根因、修复内容和新目标，并获得确认。

## 结果下载与能带分析

```powershell
& "$HOME/.codex/skills/fang_ssh_skill/scripts/download_vasp_results.ps1" -Server yang -JobName my_relax,my_scf,my_band -OutputDirectory ./downloaded_results
node "$HOME/.codex/skills/fang_ssh_skill/scripts/analyze_band.cjs" ./downloaded_results/my_scf ./downloaded_results/my_band ./band_analysis
```

- 下载脚本默认排除 WAVECAR、CHGCAR 等大型文件；需要时显式使用 `-IncludeLargeFiles`。
- 分析器当前支持 `ISPIN=1`，输出 `band_gap_summary.json`、文本摘要、CSV 和 `band_structure.svg`。
- 报告 SCF 网格带隙和高对称路径带隙，并说明二者可能因 k 点采样不同而略有差异。
- 报告 VBM、CBM、直接/间接性质和 SOC 是否启用，不将无 SOC 结果描述为 SOC 结果。

## Materials Project 结构

1. 仅在计算流程确实需要结构时读取 `references/materials-project.md`。
2. 搜索公式可能返回多个多型；不得仅按化学式或最低能量自动选取。必须匹配用户要求的相、空间群、层数或磁性状态。
3. 下载后运行几何预检，并核对最近邻距离；若来源结构需要晶胞变换，记录材料 ID、原空间群和变换方式。

## 禁止事项

- 禁止递归删除远程任务目录、修改系统目录或清理无关文件。
- 禁止猜测或自动拼接用户未提供的 POTCAR。
- 禁止将 CONTCAR 覆盖回原任务 POSCAR，除非用户明确要求且已备份。
- 禁止在错误状态不明时自动重复提交、自动取消依赖作业或静默切换服务器。
- 禁止保存密码、复制私钥内容、静默修改 SSH config，或泄露 Materials Project API Key。

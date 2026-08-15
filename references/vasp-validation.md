# VASP 校验与状态分类

## 提交前检查

- `INCAR`、`POSCAR`、`KPOINTS`、`POTCAR` 和 SLURM 脚本必须存在且非空。
- SLURM 脚本必须使用 LF 换行，并且不能残留 `{{...}}` 模板变量。
- POSCAR 的元素顺序必须与 POTCAR 的 `TITEL` 顺序逐项一致；`Mo_sv`、`Fe_pv` 等标签按基础元素符号比较。
- 解析 POSCAR 并报告周期性最近邻距离；距离低于绝对阈值或低于共价半径和的安全比例时停止提交。
- 对特殊高压结构或含未知元素半径的结构，只有在用户明确接受后才能使用 `-SkipGeometryCheck`，并在报告中说明跳过原因。
- 核数、分区和时限必须与当前 `sinfo` 结果及用户意图一致。
- POTCAR 只能来自用户获授权的 VASP 势库；不要从公共网页或 Materials Project 下载 POTCAR。
- 对已有目录、已有 Job ID 或疑似续算任务，先确认所属服务器并检查现状，不得自动覆盖或重复提交。

## 状态分类

### QUEUED

作业仍在 `squeue`，状态为 `PD`、`CF` 等尚未正式运行的状态。报告调度原因，不检查收敛结果。

依赖作业显示 `DependencyNeverSatisfied` 时，报告上游 Job ID 和阻塞链；不得自动取消，获得用户确认后再清理下游作业。

### RUNNING

作业仍在 `squeue`，状态为 `R`、`CG` 等执行相关状态。可报告当前 OSZICAR 进度，但不得声称最终收敛。

### COMPLETED

只有满足以下条件时才报告完成：

- 作业已离开 `squeue`；
- `OUTCAR` 存在且非空；
- `OUTCAR` 包含正常结束的 timing/accounting 尾部；
- `slurm-<job_id>.err` 没有 MPI abort、超时、文件缺失或 VASP 致命错误；
- 对结构优化，另外检查离子收敛标志和非空 `CONTCAR`；静态计算不要求离子收敛标志。

### FAILED

发现明确失败证据时报告失败，并引用相关文件中的短摘要。常见线索包括：

- SLURM 超时、取消、节点故障或非零退出；
- MPI abort、可执行文件不存在、输入文件缺失；
- 持续的 `ZBRENT` 失败、`BRMIX`、`EDDDAV`、`VERY BAD NEWS` 等严重错误；
- OUTCAR 未正常结束且错误日志给出明确原因。

错误字符串必须结合上下文解释，不能仅凭一次匹配自动给出物理结论。

`ZBRENT: can't locate minimum` 可能只是暂时扩大搜索区间。若后续出现成功 bracket/interpolation、结构达到要求精度、VASP 退出码为 0 且 OUTCAR 有正常 timing 尾部，不把单次 `ZBRENT` 判为失败。

### UNKNOWN

作业已离开队列，但输出缺失、截断或没有足够证据判断成功或失败。报告未知状态以及需要继续检查的文件，不得默认成功。

## 结果摘要

根据计算类型报告：

- 服务器别名、Job ID、任务目录、最后已知 SLURM 状态；
- 最后一个离子步和电子步；
- 最后自由能或适用的总能；
- 电子收敛与离子收敛是否分别满足；
- OUTCAR 是否正常结束；
- `CONTCAR` 是否存在且非空；
- SLURM/VASP 错误摘要。

不要输出完整 OUTCAR。默认只读取必要的尾部和匹配行。

## Relax 转 Static

- 只有在已确认服务器上，relax 被分类为 `COMPLETED` 且 `CONTCAR` 非空时才自动进入准备阶段。
- 默认在同一服务器创建 static 任务；跨服务器复制必须由用户明确要求，并重新验证目标服务器配置。
- 新建独立 static 目录，不覆盖原 relax 输入和输出。
- 复制前记录源 relax 目录；复制后检查新 POSCAR 非空。
- 使用静态计算专用 INCAR，并重新运行全部预检。

## Relax 转 SCF 转 Band

- SCF 必须在独立目录中运行，并仅在 Relax 具有离子收敛标志、正常 timing 尾部和非空 CONTCAR 后复制结构。
- Band 必须在独立目录中运行，并仅在 SCF 正常结束且 CHGCAR 非空后继续；通常使用 `ICHARG=11` 和 Line-mode KPOINTS。
- 使用 `afterok` 依赖；服务器支持时使用 `--kill-on-invalid-dep=yes`，否则监控 `DependencyNeverSatisfied` 并请求用户确认后取消。
- 提交后进行冒烟检查，识别 MPI bootstrap、`srun` 路径、可执行文件和异常短距离警告；失败时不得自动重新提交。

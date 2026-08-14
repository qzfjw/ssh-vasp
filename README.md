# ssh-vasp
通过 Windows 本机 OpenSSH 管理 yang-login 或 lan-login 上的 VASP/SLURM 作业，要求用户显式选择服务器，并完成输入检查、任务目录创建、SLURM 脚本生成、文件上传、sbatch 提交、squeue 监控、OUTCAR/OSZICAR 分析和安全取消。适用于用户要求在 Yang 或 Lan 服务器上创建、提交、查询、续算或管理 VASP 第一性原理计算；仅当结构获取属于该计算流程时使用 Materials Project。

# Slurm 三档 QoS 任务提交帮助

## 1. 适用范围

本说明适用于已经配置以下三种 QoS 的用户：

| QoS | 用途 | 默认状态 |
|---|---|---|
| `normal` | 普通任务 | 是 |
| `urgent` | 紧急任务，优先调度 | 否 |
| `low` | 不紧急任务，低优先级调度 | 否 |

当前示例使用：

- 集群：`cluster`
- 默认账号：`vasp`

用户的默认账号已经设置为 `vasp`，因此下面的常用提交命令不需要写 `--account=vasp`。

## 2. 提交任务

### 2.1 普通任务

不指定 QoS 时，默认使用 `normal`：

```bash
sbatch job.sh
```

如果需要显式指定账号和 QoS，也可以写成：

```bash
sbatch --account=vasp --qos=normal job.sh
```

### 2.2 紧急任务

紧急任务使用 `urgent`：

```bash
sbatch --qos=urgent job.sh
```

显式指定账号的写法为：

```bash
sbatch --account=vasp --qos=urgent job.sh
```

### 2.3 不紧急任务

不紧急任务使用 `low`：

```bash
sbatch --qos=low job.sh
```

显式指定账号的写法为：

```bash
sbatch --account=vasp --qos=low job.sh
```

## 3. 在脚本中指定 QoS

也可以把账号和 QoS 写入作业脚本。

### 普通任务脚本

```bash
#!/bin/bash
#SBATCH --job-name=normal_test
#SBATCH --qos=normal
#SBATCH --partition=compute
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=4

./run_program.sh
```

### 紧急任务脚本

```bash
#!/bin/bash
#SBATCH --job-name=urgent_test
#SBATCH --qos=urgent
#SBATCH --partition=compute
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=4

./run_program.sh
```

### 不紧急任务脚本

```bash
#!/bin/bash
#SBATCH --job-name=low_test
#SBATCH --qos=low
#SBATCH --partition=compute
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=4

./run_program.sh
```

提交脚本：

```bash
sbatch normal_job.sh
sbatch urgent_job.sh
sbatch low_job.sh
```

## 4. 快速测试命令

可以使用下面的命令提交三个简单测试任务：

```bash
sbatch --qos=normal --job-name=test_normal --wrap="hostname; id; sleep 60"

sbatch --qos=urgent --job-name=test_urgent --wrap="hostname; id; sleep 60"

sbatch --qos=low --job-name=test_low --wrap="hostname; id; sleep 60"
```

如果希望显式指定账号，可使用：

```bash
sbatch --account=vasp --qos=urgent --job-name=test_urgent --wrap="hostname; id; sleep 60"
```

## 5. 查看任务

查看当前用户的任务：

```bash
squeue -u $USER
```

查看任务的 QoS、状态、优先级和等待原因：

```bash
squeue -u $USER -o "%.18i %.10P %.12q %.10T %.12Q %.20R %.20j"
```

常见状态：

| 状态 | 含义 |
|---|---|
| `PD` | 排队等待中 |
| `R` | 正在运行 |
| `CG` | 正在结束 |
| `CD` | 已完成 |
| `F` | 失败 |
| `CA` | 已取消 |

查看任务优先级组成：

```bash
sprio -j <JOB_ID>
```

查看任务详细信息：

```bash
scontrol show job <JOB_ID>
```

查看任务历史和最终状态：

```bash
sacct -j <JOB_ID> \\
    --format=JobID,JobName,User,Account,Partition,QOS,State,Elapsed,ExitCode
```

## 6. 查看输出文件

如果没有指定输出文件，Slurm 默认生成：

```text
slurm-<JOB_ID>.out
```

查看输出：

```bash
cat slurm-<JOB_ID>.out
```

也可以在脚本中指定输出和错误日志：

```bash
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
```

其中：

- `%x`：作业名称
- `%j`：作业 ID

提交前请先创建日志目录：

```bash
mkdir -p logs
```

## 7. 取消任务

取消指定任务：

```bash
scancel <JOB_ID>
```

取消当前用户的全部任务：

```bash
scancel -u $USER
```

## 8. 交互式任务

申请一个紧急交互式任务：

```bash
srun --qos=urgent \\
     --partition=compute \\
     --time=01:00:00 \\
     --cpus-per-task=4 \\
     --pty bash
```

申请普通交互式任务：

```bash
srun --qos=normal \\
     --partition=compute \\
     --time=01:00:00 \\
     --pty bash
```

申请不紧急交互式任务：

```bash
srun --qos=low \\
     --partition=compute \\
     --time=01:00:00 \\
     --pty bash
```

## 9. 优先级说明

优先级顺序为：

```text
urgent > normal > low
```

这表示在任务竞争同一批资源时，`urgent` 任务优先于 `normal`，`normal` 优先于 `low`。

注意：

1. `urgent` 不一定会中断已经运行的任务。
2. 如果当前有足够空闲资源，三种 QoS 的任务可能同时运行。
3. 只有在资源不足、任务需要排队时，QoS 优先级才会明显体现。
4. `low` 任务可能需要等待更高优先级的待调度任务完成。

## 10. 常见问题

### 10.1 提示没有权限使用 QoS

例如：

```text
Invalid qos specification
```

请联系管理员检查用户的账号和 QoS association：

```bash
sacctmgr show assoc where user=$USER \\
    format=Cluster,Account,User,QOS,DefaultQOS
```

### 10.2 提示账号无效

请确认提交时使用的账号正确：

```bash
sacctmgr show assoc where user=$USER \\
    format=Cluster,Account,User,DefaultAccount
```

如果默认账号已经是 `vasp`，可以省略 `--account=vasp`。

### 10.3 任务一直处于 `PD` 状态

查看等待原因：

```bash
squeue -j <JOB_ID> -o "%.18i %.10T %.30R"
```

常见原因包括：

- 资源不足；
- 申请的 CPU、内存、GPU 或节点数量过多；
- 达到 Partition 或 QoS 限制；
- 前面有更高优先级任务等待；
- 作业请求的时间或资源无法满足。

## 11. 最常用命令速查

```bash
# 普通任务，账号和 QoS 均使用默认值
sbatch job.sh

# 紧急任务，使用默认账号 vasp
sbatch --qos=urgent job.sh

# 不紧急任务，使用默认账号 vasp
sbatch --qos=low job.sh

# 显式指定账号的写法
sbatch --account=vasp --qos=urgent job.sh

# 查看任务
squeue -u $USER

# 查看优先级
sprio -u $USER

# 查看任务历史
sacct -u $USER

# 取消任务
scancel <JOB_ID>
```

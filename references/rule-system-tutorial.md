# Fang SSH Skill 规则系统教程：经验、解释、算法和安全边界

本文围绕 `fang-ssh-skill` 说明规则系统如何工作，以及用户和维护者应如何高效使用、扩展和验证规则。

这个 skill 的核心思想是：把会随经验变化的内容写成规则数据，把为什么这样做写成解释文档，把可重复执行的步骤写成脚本算法，把不能突破的底线写进安全边界。这样既能积累 VASP 计算经验，又不让自动化越界。

## 1. 四层分工

| 层次 | 回答的问题 | 放在哪里 | 典型例子 |
|---|---|---|---|
| 经验 | 通常应该怎么设置 | `config/rules/` | 结构优化 `NSW=500`；3d 元素 `LMAXMIX=4`；KPOINTS 包含 Gamma 点 |
| 解释 | 为什么这样做，什么时候例外 | `references/` | slab 真空方向不应机械套用三维 k 点密度 |
| 算法 | 如何机械读取、合并、检查规则 | `scripts/` | 解析 POSCAR 元素；计算 `ceil(25 / L_i)`；检查 POTCAR 顺序 |
| 安全边界 | 无论经验如何变化都不能做什么 | `SKILL.md` 和关键脚本 | 不猜 POTCAR；不覆盖远程目录；不在登录节点运行 VASP |

这四层不要混在一起。经验写进规则文件，解释写进参考文档，算法写进脚本，安全边界写进 `SKILL.md` 和提交、预检脚本。

## 2. 规则是如何表示的

大多数规则使用 PowerShell 数据文件 `.psd1` 表示。`.psd1` 是纯数据格式，适合保存嵌套的键值表和列表。

例如 `config/rules/parameters/incar-rules.psd1` 中的条件规则：

```powershell
ConditionalRules = @(
    @{
        Name = 'LMAXMIX_3d'
        IfContainsAnyElementGroup = 'Transition3d'
        Parameters = @{ LMAXMIX = '4' }
        Reason = '3d transition-metal systems usually need LMAXMIX=4.'
    }
)
```

这里：

- `ConditionalRules` 是规则列表。
- `@(...)` 表示数组。
- `@{...}` 表示哈希表，也就是键值对。
- `IfContainsAnyElementGroup` 不是 PowerShell 保留字，而是本 skill 自定义的规则字段。
- `Parameters` 表示规则触发后要覆盖的 INCAR 参数。

脚本只会理解它已经实现的字段。新增一个字段名并不会自动生效，除非相应脚本也加入解析逻辑。

## 3. 参数规则文件的职责

参数建议集中放在：

```text
config/rules/parameters/
├─ incar-rules.psd1
├─ kpoints-rules.psd1
└─ profiles.psd1
```

`incar-rules.psd1` 负责 INCAR 经验。它包含默认参数、任务参数组、元素分组和条件规则。例如普通 Relax 默认 `NSW=500`、`IBRION=2`、`ISIF=2`，如果 POSCAR 中含 3d 元素，则把 `LMAXMIX` 调整为 `4`。

`kpoints-rules.psd1` 负责 KPOINTS 经验。当前普通规则是优先使用 Gamma-centered 网格，并让每个方向满足：

```text
K_i * L_i >= 25 Angstrom
```

其中 `L_i` 是 POSCAR 中对应晶格矢量长度，`K_i` 是该方向 k 点数。脚本使用 `ceiling(25 / L_i)` 计算最小整数网格。

`profiles.psd1` 负责把任务类型组合起来。例如 `Relax` 指向 `IncarProfile = 'Relax'` 和 `KpointsProfile = 'GammaLengthProduct25'`；`Band` 指向 `IncarProfile = 'Band'` 和 `KpointsProfile = 'BandLineMode'`。

## 4. 脚本执行式推理

脚本执行式推理是确定性的：同样的规则和同样的 POSCAR 会得到同样的结果。

入口脚本是：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'

& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" `
  -Task Relax `
  -PoscarPath ./POSCAR
```

执行流程是：

```text
读取 profiles.psd1
→ 确定 Relax 使用哪个 INCAR profile 和 KPOINTS profile
→ 读取 incar-rules.psd1 的默认参数
→ 合并 Relax 参数
→ 解析 POSCAR 元素列表
→ 根据元素触发 ConditionalRules
→ 读取 kpoints-rules.psd1
→ 根据晶格长度计算 KPOINTS 网格
→ 输出参数建议和 Review notes
```

例如 POSCAR 中有 `Fe O`，脚本发现 `Fe` 属于 `Transition3d`，就会触发 `LMAXMIX_3d`，把：

```text
LMAXMIX = 2
```

覆盖为：

```text
LMAXMIX = 4
```

注意：当前 `resolve_vasp_parameters.ps1` 默认只打印建议，不直接写出 `INCAR` 或 `KPOINTS` 文件。需要保存结果时可用重定向：

```powershell
& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" `
  -Task Relax `
  -PoscarPath ./POSCAR `
  > parameter_suggestion.txt
```

## 5. 知识加载式推理

知识加载式推理是 Codex 阅读规则文件和参考文档后，在对话中结合上下文进行解释和判断。

例如你问：

```text
MoS2 单层有 20 Angstrom 真空层，z 方向也要按 K_i * L_i >= 25 取 k 点吗？
```

Codex 会结合 `kpoints-rules.psd1` 和 `references/vasp-parameter-rules.md` 中的例外说明，判断这是 slab 体系，真空方向通常不机械增加 k 点，可能建议平面方向保持足够密度，真空方向取 `1`。

脚本执行式适合自动生成、硬检查和重复流程；知识加载式适合解释规则、处理例外、讨论参数选择和修改规则。

## 6. Preflight 属于哪一层

`preflight_job.ps1` 是提交前闸门，属于“规则检查 + 安全边界”的结合体。

它主要读取：

```text
config/rules/input-rules.psd1
```

它不负责推荐参数，而是判断当前目录是否可以进入上传和 `sbatch` 提交流程。它检查：

- `INCAR`、`POSCAR`、`KPOINTS`、`POTCAR` 是否存在且非空。
- `run_vasp.slurm` 是否存在，是否使用 LF 换行，是否还有模板变量。
- POSCAR 是否能解析。
- POSCAR 和 POTCAR 的元素顺序是否一致。
- 周期性最近邻距离是否明显过短。
- Band 计算是否满足 `ICHARG=11` 和 Line-mode KPOINTS。
- SCF、Static、Band 是否满足 `NSW=0`。

所以二者关系是：

```text
resolve_vasp_parameters.ps1
→ 给建议：应该怎样写 INCAR/KPOINTS

preflight_job.ps1
→ 做门禁：现有输入是否明显错误，能否继续提交
```

## 7. 安全边界如何工作

安全边界是这个 skill 最重要的一层。它保证自动化不会因为一条经验规则而做出高风险动作。

例如 POTCAR：

```text
经验：PBE 5.4 PAW 势库路径保存在 PawPotentialRoot。
解释：POTCAR 必须来自用户有授权的 VASP 势库。
算法：select_server.ps1 读取服务器配置并导出 VASP_PAW_POTENTIAL_ROOT。
安全边界：不得从公共网页或 Materials Project 下载 POTCAR，不得猜测 Fe、Fe_pv、Fe_sv 等势版本。
```

也就是说，即使 Codex 知道某个结构含 Fe，它也不能擅自决定用 `Fe` 还是 `Fe_pv`。这需要用户确认。

再例如远程目录：

```text
经验：所有任务放在 ~/vasp_codex/<job_name>。
算法：提交脚本在远程创建任务目录。
安全边界：如果目录已存在，必须停止；不能自动删除、清空或复用旧目录。
```

这类边界不能放到可随意覆盖的项目规则里，否则自动化会变得危险。

## 8. 如何新增或修改经验规则

推荐流程：

```text
发现经验
→ 判断属于 INCAR、KPOINTS、profile、preflight、runtime、workflow、artifact 还是 analysis
→ 修改对应规则文件
→ 增加 Reason 或 Review 说明
→ 运行数据文件加载检查
→ 运行相关脚本验证
→ 用 Git 提交并同步给其他用户
```

常见修改位置：

| 要改什么 | 推荐位置 |
|---|---|
| INCAR 默认参数 | `config/rules/parameters/incar-rules.psd1` 的 `DefaultParameters` |
| Relax、SCF、DOS、Band 参数组 | `config/rules/parameters/incar-rules.psd1` 的 `Profiles` |
| 元素触发规则 | `config/rules/parameters/incar-rules.psd1` 的 `ElementGroups` 和 `ConditionalRules` |
| KPOINTS 密度规则 | `config/rules/parameters/kpoints-rules.psd1` |
| 任务类型组合 | `config/rules/parameters/profiles.psd1` |
| 提交前硬检查 | `config/rules/input-rules.psd1` |
| VASP/MPI/oneAPI 兼容性 | `config/rules/runtime-rules.psd1` |
| Relax→SCF→Band 门控 | `config/rules/workflow-rules.psd1` |
| 下载文件清单 | `config/rules/artifact-rules.psd1` |
| 能带分析和绘图 | `config/rules/analysis-rules.json` |

## 9. 修改规则的具体例子

### 9.1 修改 Relax 默认参数

如果希望普通结构优化默认更重视力精度，可以在 `incar-rules.psd1` 的 `Profiles.Relax.Parameters` 中加入或修改：

```powershell
ADDGRID = '.T.'
```

同时在 `Review` 中保留说明：

```powershell
'Use ADDGRID=.T. for force-sensitive tasks such as phonons or difficult relaxations.'
```

### 9.2 增加新的元素条件规则

如果希望含稀土或锕系元素时提醒检查 DFT+U，可以增加 `Review` 或新的条件规则。但如果新规则只是提醒，优先放入说明或 Review；如果要自动改参数，才放到 `ConditionalRules`。

例如：

```powershell
@{
    Name = 'LMAXMIX_4f_5f'
    IfContainsAnyElementGroup = @('Lanthanide4f', 'Actinide5f')
    Parameters = @{ LMAXMIX = '6' }
    Reason = 'f-electron systems usually need LMAXMIX=6.'
}
```

### 9.3 修改 KPOINTS 经验

如果希望普通优化更稀疏，可以把：

```powershell
TargetLengthProduct = 25.0
```

改成：

```powershell
TargetLengthProduct = 20.0
```

但这会影响所有使用 `GammaLengthProduct25` 的任务。若只是某个项目需要，建议新建 profile 或项目覆盖规则，而不是改公共默认。

## 10. 项目覆盖和公共规则

公共规则适合写稳定、可复用的组内经验。单个项目、单个材料或临时测试参数不要直接写进公共默认规则。

`preflight_job.ps1` 等脚本支持通过 `*RulesOverridePath` 加载覆盖文件。覆盖合并由 `scripts/lib/VaspRuleEngine.psm1` 处理：字典递归合并，数组和普通值整体替换。

例如某个项目需要更严格的几何检查，可以创建：

```powershell
@{
    SchemaVersion = 1
    Geometry = @{
        MinimumCovalentRatio = 0.72
        AbsoluteMinimumDistanceAngstrom = 0.8
    }
}
```

然后运行：

```powershell
& "$SkillRoot/scripts/preflight_job.ps1" `
  -InputDirectory . `
  -JobName test_relax `
  -CalculationType Relax `
  -RulesOverridePath ./project-input-rules.psd1
```

注意：不是所有脚本都支持同一个覆盖参数。使用前应先查看脚本参数，或让 Codex 读取脚本确认。

## 11. 验证规则修改

每次修改 `.psd1` 后，先确认数据文件能被 PowerShell 正常读取：

```powershell
Import-PowerShellDataFile "$SkillRoot/config/rules/parameters/incar-rules.psd1"
Import-PowerShellDataFile "$SkillRoot/config/rules/parameters/kpoints-rules.psd1"
Import-PowerShellDataFile "$SkillRoot/config/rules/parameters/profiles.psd1"
```

再运行参数解析：

```powershell
& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" -Task Relax
```

如果有 POSCAR：

```powershell
& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" `
  -Task Relax `
  -PoscarPath ./POSCAR
```

提交前还要运行 preflight：

```powershell
& "$SkillRoot/scripts/preflight_job.ps1" `
  -InputDirectory . `
  -JobName my_relax `
  -CalculationType Relax
```

如果修改了 JavaScript 分析脚本或 JSON 绘图规则，还应运行：

```powershell
node --check "$SkillRoot/scripts/analyze_band.cjs"
```

## 12. 维护原则

维护时优先遵守以下原则：

- 能用现有字段表达，就不要新增规则语法。
- 能写成规则数据，就不要硬编码进脚本。
- 能写成解释，就不要伪装成自动规则。
- 单个项目的参数不要污染公共默认规则。
- 修改安全边界要非常谨慎，通常需要人工确认和回归测试。
- 新增事故经验时，先在 `config/rules/incidents/` 记录症状、原因和预防方式，再决定是否扩展默认规则。

## 13. 推荐日常用法

生成或审阅一个 Relax 参数建议：

```powershell
$SkillRoot = Join-Path $HOME '.codex\skills\fang_ssh_skill'

& "$SkillRoot/scripts/resolve_vasp_parameters.ps1" `
  -Task Relax `
  -PoscarPath ./POSCAR
```

检查当前输入能否提交：

```powershell
& "$SkillRoot/scripts/preflight_job.ps1" `
  -InputDirectory . `
  -JobName my_relax `
  -CalculationType Relax
```

检查服务器 SSH：

```powershell
& "$SkillRoot/scripts/check_ssh_hosts.ps1" -Server all
```

选择服务器并查看 PAW 势库路径：

```powershell
& "$SkillRoot/scripts/select_server.ps1" -Server yang
$env:VASP_PAW_POTENTIAL_ROOT
```

## 14. 一句话总结

`fang-ssh-skill` 的规则系统不是让 Codex 替代计算经验，而是把经验沉淀成可维护的数据，把解释留给人，把可重复步骤交给脚本，把危险动作挡在安全边界之外。

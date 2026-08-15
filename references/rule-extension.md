# VASP 规则扩展与维护

## 分层原则

- 将解析算法、SSH/SLURM 执行、安全边界保留在 `scripts/`。
- 将会随服务器、计算类型或经验变化的阈值、关键词、文件清单和绘图参数放在 `config/rules/`。
- 禁止在规则文件中保存密码、私钥、Materials Project Key 或任意可执行 Shell 片段。
- 新规则必须先经过 Schema、字符安全和本地回归验证，再用于真实提交。

## 规则文件

| 文件 | 负责内容 |
|---|---|
| `runtime-rules.psd1` | VASP/MPI 路径、版本、ELF 和动态库兼容性 |
| `input-rules.psd1` | 必需输入文件、几何阈值、共价半径和计算类型检查 |
| `workflow-rules.psd1` | 阶段、默认资源、准备门控、依赖和冒烟特征 |
| `artifact-rules.psd1` | 下载白名单、日志匹配和大文件分类 |
| `analysis-rules.json` | 能带分析模型声明和 SVG 绘图参数 |
| `incidents/*.psd1` | 已发生问题的症状、适用范围、严重性和预防检查 |

PowerShell 规则统一通过 `scripts/lib/VaspRuleEngine.psm1` 加载。基础规则与任务覆盖文件递归合并；字典递归合并，数组和标量由覆盖文件整体替换。

## 优先级

按以下顺序应用，右侧优先级更高：

```text
技能默认规则 < 服务器配置 < 项目/任务覆盖文件 < 用户本次显式参数
```

服务器路径继续由 `config/servers.psd1` 管理。规则脚本参数中的 `*RulesOverridePath` 用于项目或任务级覆盖。显式命令参数仅覆盖脚本公开允许覆盖的值，例如几何阈值、核数或时限。

## 新问题扩展流程

1. 保存原始错误证据，包括服务器、VASP/MPI 版本、Job ID、stderr、OUTCAR 尾部和触发阶段。
2. 判断问题属于运行时、输入、工作流、下载、分析还是通用安全机制。
3. 若现有规则类型能够表达，只修改对应规则文件，不修改执行脚本。
4. 在 `config/rules/incidents/` 新增事故记录，填写稳定 ID、适用范围、症状、严重性、预防项和解决方案。
5. 若需要新的检查语义，在执行脚本中新增通用规则类型，不为单个材料或单个 Job ID 编写特例。
6. 使用历史计算目录或最小测试夹具执行 DryRun，确认正常样例通过、问题样例在提交前失败。
7. 运行全部 PowerShell 语法检查、Node `--check` 和 skill `quick_validate.py`。

## 输入规则扩展

`input-rules.psd1` 的 `CalculationTypes.<类型>.Checks` 当前支持：

- `IncarEquals`
- `IncarIntegerGreaterThan`
- `IncarIntegerEquals`
- `KpointsRegex`
- `AnyFileExists`

每条检查设置 `Severity` 为 `Error` 或 `Warning`，并提供用户可直接理解的 `Message`。增加新 INCAR 数值或 KPOINTS 规则时优先复用这些检查类型。

## 工作流规则扩展

`workflow-rules.psd1` 的阶段门控由以下数据组成：

- `RequiredNonEmptyFiles`
- `RequiredTextChecks`
- `ForbiddenRegexChecks`
- `CopyFiles`

只在规则中保存文件名、受限正则表达式和消息，不写完整 Bash 命令。`render_band_chain.ps1` 负责生成并校验实际的 `prepare_stage.sh`。

## 覆盖文件示例

项目需要更严格的最短距离检查时创建独立覆盖文件：

```powershell
@{
    SchemaVersion = 1
    Geometry = @{
        MinimumCovalentRatio = 0.72
        AbsoluteMinimumDistanceAngstrom = 0.8
    }
}
```

然后调用：

```powershell
& "$SkillRoot/scripts/preflight_job.ps1" `
  -InputDirectory . `
  -JobName test_relax `
  -CalculationType Relax `
  -RulesOverridePath ./project-input-rules.psd1
```

不要直接修改默认规则来满足单个项目；确认经验具有普适性后，再提升为技能默认规则。
